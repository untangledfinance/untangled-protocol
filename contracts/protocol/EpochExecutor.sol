// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '../interfaces/INoteTokenVault.sol';
import '../interfaces/IEpochExecutor.sol';
import '../interfaces/INoteTokenManager.sol';
import '../interfaces/IPool.sol';
import '../libraries/Math.sol';
import '../libraries/ConfigHelper.sol';
import 'hardhat/console.sol';

contract EpochExecutor is
    IEpochExecutor,
    Initializable,
    PausableUpgradeable,
    AccessControlEnumerableUpgradeable,
    ReentrancyGuardUpgradeable
{
    uint256 constant RATE_SCALING_FACTOR = 10 ** 4;
    uint256 constant ONE_HUNDRED_PERCENT = 100 * RATE_SCALING_FACTOR;
    int256 public constant SUCCESS = 0;
    int256 public constant NEW_BEST = 0;
    int256 public constant ERR_CURRENCY_AVAILABLE = -1;
    int256 public constant ERR_MAX_ORDER = -2;
    int256 public constant ERR_DEBT_CEILING_REACHED = -3;
    int256 public constant ERR_POOL_CLOSING = -4;
    int256 public constant ERR_MAX_SENIOR_RATIO = -5;
    int256 public constant ERR_NOT_NEW_BEST = -6;
    uint256 public constant WEIGHT_SENIOR_WITHDRAW = 1000000;
    uint256 public constant WEIGHT_JUNIOR_WITHDRAW = 100000;
    uint256 public constant WEIGHT_SENIOR_INVEST = 10000;
    uint256 public constant WEIGHT_JUNIOR_INVEST = 1000;

    using ConfigHelper for Registry;
    Registry public registry;

    modifier isNewEpoch(address pool) {
        _isNewEpoch(pool);
        _;
    }

    INoteTokenManager public sotManager;
    INoteTokenManager public jotManager;

    mapping(address => EpochInformation) epochInfor;

    function initialize(Registry registry_) public initializer {
        __Pausable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __AccessControlEnumerable_init_unchained();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        registry = registry_;
    }

    function _isNewEpoch(address pool) internal view {
        require(Math.safeSub(block.timestamp, epochInfor[pool].lastEpochClosed) >= epochInfor[pool].minimumEpochTime);
    }

    function setUpNoteTokenManger() public {
        INoteTokenManager sotManager_ = registry.getSeniorTokenManager();
        INoteTokenManager jotManager_ = registry.getJuniorTokenManager();
        require(
            address(sotManager_) != address(0) && address(jotManager_) != address(0),
            'note token manager not fully set up'
        );
        sotManager = sotManager_;
        jotManager = jotManager_;
    }

    function setupPool() public {
        epochInfor[msg.sender].lastEpochClosed = block.timestamp;
    }

    function setParam(address pool, bytes32 name, uint256 value) public {
        if (name == 'challengeTime') {
            epochInfor[pool].challengeTime = value;
        } else if (name == 'minimumEpochTime') {
            epochInfor[pool].minimumEpochTime = value;
        } else {
            revert('unknown-name');
        }
    }

    function setParam(address pool, bytes32 name, bool value) public {
        if (name == 'poolClosing') {
            epochInfor[pool].poolClosing = value;
        } else {
            revert('unknown-name');
        }
    }

    function setEpochInfor(address pool, uint256 _challengeTime, uint256 _minimumEpochTime, bool _poolClosing) public {
        epochInfor[pool].challengeTime = _challengeTime;
        epochInfor[pool].minimumEpochTime = _minimumEpochTime;
        epochInfor[pool].poolClosing = _poolClosing;
    }

    function closeEpoch(address pool) external returns (bool) {
        _isNewEpoch(pool);
        require(epochInfor[pool].submitPeriod == false);

        epochInfor[pool].lastEpochClosed = block.timestamp;
        epochInfor[pool].epochNAV = IPool(pool).currentNAV();
        epochInfor[pool].epochReserve = IPool(pool).reserve();
        epochInfor[pool].epochIncomeReserve = IPool(pool).incomeReserve();

        {
            (uint256 totalJuniorInvest, uint256 totalJuniorWithdraw) = jotManager.closeEpoch(pool);
            (uint256 totalSeniorInvest, uint256 totalSeniorWithdraw) = sotManager.closeEpoch(pool);

            (uint256 seniorDebt, uint256 seniorBalance) = IPool(pool).seniorDebtAndBalance();
            epochInfor[pool].epochSeniorAsset = Math.safeAdd(seniorDebt, seniorBalance);

            if (
                totalSeniorWithdraw == 0 && totalJuniorWithdraw == 0 && totalJuniorInvest == 0 && totalSeniorInvest == 0
            ) {
                jotManager.epochUpdate(pool, epochInfor[pool].currentEpoch, 0, 0, 0, 0, 0);
                sotManager.epochUpdate(pool, epochInfor[pool].currentEpoch, 0, 0, 0, 0, 0);
            }

            (uint256 sotPrice, uint256 jotPrice) = IPool(pool).calcTokenPrices();
            epochInfor[pool].sotPrice = sotPrice;
            epochInfor[pool].jotPrice = jotPrice;

            if (jotPrice == 0) {
                epochInfor[pool].poolClosing = true;
            }

            epochInfor[pool].order.sotWithdraw = totalSeniorWithdraw;
            epochInfor[pool].order.jotWithdraw = totalJuniorWithdraw;
            epochInfor[pool].order.sotInvest = totalSeniorInvest;
            epochInfor[pool].order.jotInvest = totalJuniorInvest;
        }
        if (
            validate(
                pool,
                epochInfor[pool].order.sotWithdraw,
                epochInfor[pool].order.jotWithdraw,
                epochInfor[pool].order.sotInvest,
                epochInfor[pool].order.jotInvest
            ) == SUCCESS
        ) {
            _executeEpoch(
                pool,
                epochInfor[pool].order.sotWithdraw,
                epochInfor[pool].order.jotWithdraw,
                epochInfor[pool].order.sotInvest,
                epochInfor[pool].order.jotInvest
            );
            return true;
        }

        epochInfor[pool].submitPeriod = true;
        return false;
    }

    function validate(
        address pool,
        uint256 seniorWithdraw,
        uint256 juniorWithdraw,
        uint256 seniorInvest,
        uint256 juniorInvest
    ) public view returns (int256 err) {
        return
            validate(
                pool,
                epochInfor[pool].epochReserve,
                epochInfor[pool].epochNAV,
                epochInfor[pool].epochSeniorAsset,
                seniorInvest,
                seniorWithdraw,
                juniorInvest,
                juniorWithdraw
            );
    }

    function validate(
        address pool,
        uint256 reserve_,
        uint256 nav_,
        uint256 seniorAsset_,
        uint256 seniorInvest,
        uint256 seniorWithdraw,
        uint256 juniorInvest,
        uint256 juniorWithdraw
    ) public view returns (int256) {
        uint256 currencyAvailable = Math.safeAdd(Math.safeAdd(reserve_, seniorInvest), juniorInvest);
        uint256 currencyOut = Math.safeAdd(seniorWithdraw, juniorWithdraw);
        int256 err = validateCoreConstraints(
            pool,
            currencyAvailable,
            currencyOut,
            seniorWithdraw,
            juniorWithdraw,
            seniorInvest,
            juniorInvest
        );
        if (err != SUCCESS) {
            return err;
        }
        uint256 newReserve = Math.safeSub(currencyAvailable, currencyOut);
        uint256 newSeniorAsset = Math.safeSub(Math.safeAdd(seniorAsset_, seniorInvest), seniorWithdraw); // seniorAsset_ + seniorInvest - seniorWithdraw
        if (epochInfor[pool].poolClosing == true) {
            if (seniorInvest == 0 && juniorInvest == 0) {
                return SUCCESS;
            }
            return ERR_POOL_CLOSING;
        }
        return validatePoolConstraints(pool, newReserve, newSeniorAsset, nav_);
    }

    function validateCoreConstraints(
        address pool,
        uint256 capitalCurrencyAvailable,
        uint256 currencyOut,
        uint256 seniorWithdraw, // seniorCapitalWithdraw
        uint256 juniorWithdraw, // juniorCapitalWithdraw
        uint256 seniorInvest,
        uint256 juniorInvest
    ) public view returns (int256) {
        // constraint 1: capital currency available
        if (currencyOut > capitalCurrencyAvailable) {
            return ERR_CURRENCY_AVAILABLE;
        }
        // constraint 2: max order
        if (
            seniorInvest > epochInfor[pool].order.sotInvest ||
            juniorInvest > epochInfor[pool].order.jotInvest ||
            seniorWithdraw > epochInfor[pool].order.sotWithdraw ||
            juniorWithdraw > epochInfor[pool].order.jotWithdraw
        ) {
            return ERR_MAX_ORDER;
        }
        // constraint 3: debt ceiling
        uint256 totalValueRaised = sotManager.getTotalValueRaised(pool) +
            jotManager.getTotalValueRaised(pool) +
            seniorInvest +
            juniorInvest -
            currencyOut;
        if (totalValueRaised >= IPool(pool).debtCeiling()) {
            return ERR_DEBT_CEILING_REACHED;
        }
        return SUCCESS;
    }

    function validatePoolConstraints(
        address pool,
        uint256 reserve_,
        uint256 seniorAsset,
        uint256 nav_
    ) public view returns (int256 err) {
        uint256 assets = Math.safeAdd(nav_, reserve_);
        // constraint 4: min first loss
        return validateMinFirstLoss(pool, assets, seniorAsset);
    }

    function validateMinFirstLoss(address pool, uint256 assets, uint256 seniorAsset) public view returns (int256) {
        uint256 minFirstLossCushion = IPool(pool).minFirstLossCushion();
        if (seniorAsset >= assets && minFirstLossCushion != 0) {
            return ERR_MAX_SENIOR_RATIO;
        }

        if (seniorAsset == 0 && assets > 0) {
            return SUCCESS;
        }

        if (ONE_HUNDRED_PERCENT - (seniorAsset * ONE_HUNDRED_PERCENT) / assets < minFirstLossCushion) {
            return ERR_MAX_SENIOR_RATIO;
        }
        return SUCCESS;
    }

    function submitSolution(
        address pool,
        uint256 seniorInvest,
        uint256 juniorInvest,
        uint256 seniorWithdraw,
        uint256 juniorWithdraw
    ) public returns (int256) {
        require(epochInfor[pool].submitPeriod == true, 'EpochExecutor: not submission period');
        int256 valid = _submitSolution(pool, seniorInvest, juniorInvest, seniorWithdraw, juniorWithdraw);
        if (valid == SUCCESS && epochInfor[pool].minChallengePeriodEnd == 0) {
            epochInfor[pool].minChallengePeriodEnd = Math.safeAdd(block.timestamp, epochInfor[pool].challengeTime);
        }
        return valid;
    }

    function _submitSolution(
        address pool,
        uint256 seniorInvest,
        uint256 juniorInvest,
        uint256 seniorWithdraw,
        uint256 juniorWithdraw
    ) internal returns (int256) {
        int256 valid = validate(pool, seniorWithdraw, juniorWithdraw, seniorInvest, juniorInvest);
        // every solution must satify all constraints
        if (valid != SUCCESS) {
            return valid;
        } else {
            uint256 score = scoreSolution(seniorInvest, juniorInvest, seniorWithdraw, juniorWithdraw);
            if (epochInfor[pool].gotFullValidation == false) {
                epochInfor[pool].gotFullValidation = true;
                _saveNewOptimum(pool, seniorInvest, juniorInvest, seniorWithdraw, juniorWithdraw, score);

                return SUCCESS;
            }
            if (score < epochInfor[pool].bestSubScore) {
                return ERR_NOT_NEW_BEST;
            }
            _saveNewOptimum(pool, seniorInvest, juniorInvest, seniorWithdraw, juniorWithdraw, score);

            return SUCCESS;
        }
        // TO DO: proposed solution does not satisfy all pool constraints.
        // if we never received a solution which satisfies all constraints for this epoch.
        // we might accept it as an improvement
    }

    function scoreSolution(
        uint256 seniorInvest,
        uint256 juniorInvest,
        uint256 seniorWithdraw,
        uint256 juniorWithdraw
    ) internal pure returns (uint256) {
        return
            Math.safeAdd(
                Math.safeAdd(
                    Math.safeMul(seniorInvest, WEIGHT_SENIOR_INVEST),
                    Math.safeMul(juniorInvest, WEIGHT_JUNIOR_INVEST)
                ),
                Math.safeAdd(
                    Math.safeMul(seniorWithdraw, WEIGHT_SENIOR_WITHDRAW),
                    Math.safeMul(juniorWithdraw, WEIGHT_JUNIOR_WITHDRAW)
                )
            );
    }

    function _saveNewOptimum(
        address pool,
        uint256 seniorInvest,
        uint256 juniorInvest,
        uint256 seniorWithdraw,
        uint256 juniorWithdraw,
        uint256 score
    ) internal {
        epochInfor[pool].bestSubmission.sotInvest = seniorInvest;
        epochInfor[pool].bestSubmission.jotInvest = juniorInvest;
        epochInfor[pool].bestSubmission.sotWithdraw = seniorWithdraw;
        epochInfor[pool].bestSubmission.jotWithdraw = juniorWithdraw;
        epochInfor[pool].bestSubScore = score;
    }

    function _executeEpoch(
        address pool,
        uint256 sotWithdraw,
        uint256 jotWithdraw,
        uint256 sotInvest,
        uint256 jotInvest
    ) internal {
        uint256 epochID = epochInfor[pool].currentEpoch;
        epochInfor[pool].submitPeriod = false;

        {
            address tempPool = pool;
            sotManager.epochUpdate(
                tempPool,
                epochID,
                _calcFulfillment(sotInvest, epochInfor[tempPool].order.sotInvest),
                _calcFulfillment(sotWithdraw, epochInfor[tempPool].order.sotWithdraw),
                epochInfor[tempPool].sotPrice,
                epochInfor[tempPool].order.sotInvest,
                epochInfor[tempPool].order.sotWithdraw
            );
            jotManager.epochUpdate(
                tempPool,
                epochID,
                _calcFulfillment(jotInvest, epochInfor[tempPool].order.jotInvest),
                _calcFulfillment(jotWithdraw, epochInfor[tempPool].order.jotWithdraw),
                epochInfor[tempPool].jotPrice,
                epochInfor[tempPool].order.jotInvest,
                epochInfor[tempPool].order.jotWithdraw
            );
            IPool(tempPool).changeSeniorAsset(0, 0);
        }

        uint256 totalCapitalWithdraw = sotWithdraw + jotWithdraw;
        uint256 totalInvest = Math.safeAdd(sotInvest, jotInvest);

        if (totalCapitalWithdraw < totalInvest) {
            IPool(pool).increaseCapitalReserve(Math.safeSub(totalInvest, totalCapitalWithdraw));
        }

        if (totalCapitalWithdraw > totalInvest) {
            IPool(pool).decreaseCapitalReserve(Math.safeSub(totalCapitalWithdraw, totalInvest));
        }

        IPool(pool).changeSeniorAsset(sotInvest, sotWithdraw);
        epochInfor[pool].currentEpoch += 1;
        epochInfor[pool].lastEpochExecuted = epochID;
        epochInfor[pool].minChallengePeriodEnd = 0;
        epochInfor[pool].bestSubScore = 0;
        epochInfor[pool].gotFullValidation = false;
    }

    function executeEpoch(address pool) public {
        require(
            block.timestamp >= epochInfor[pool].minChallengePeriodEnd && epochInfor[pool].minChallengePeriodEnd != 0
        );
        _executeEpoch(
            pool,
            epochInfor[pool].bestSubmission.sotWithdraw,
            epochInfor[pool].bestSubmission.jotWithdraw,
            epochInfor[pool].bestSubmission.sotInvest,
            epochInfor[pool].bestSubmission.jotInvest
        );
    }

    function _calcFulfillment(uint256 amount, uint256 totalOrder) public pure returns (uint256 percent) {
        if (amount == 0 || totalOrder == 0) {
            return 0;
        }
        return (amount * ONE_HUNDRED_PERCENT) / totalOrder;
    }

    function calcNewReserve(
        address pool,
        uint256 sotWithdraw,
        uint256 jotWithdraw,
        uint256 sotInvest,
        uint256 jotInvest
    ) public view returns (uint256) {
        return
            Math.safeSub(
                Math.safeAdd(Math.safeAdd(epochInfor[pool].epochReserve, sotInvest), jotInvest),
                Math.safeAdd(sotWithdraw, jotWithdraw)
            );
    }

    function currentEpoch(address pool) public view returns (uint256) {
        return epochInfor[pool].currentEpoch;
    }

    function lastEpochExecuted(address pool) public view returns (uint256) {
        return epochInfor[pool].lastEpochExecuted;
    }

    function getNoteTokenAddress(address pool) public view returns (address, address) {
        require(sotManager.getTokenAddress(pool) != address(0), 'EpochExecutor: no SeniorToken found');
        require(jotManager.getTokenAddress(pool) != address(0), 'EpochExecutor: no JuniorToken found');
        return (sotManager.getTokenAddress(pool), jotManager.getTokenAddress(pool));
    }
}
