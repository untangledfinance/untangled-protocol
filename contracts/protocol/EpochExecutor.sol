// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;
import '../interfaces/INoteTokenVault.sol';
import '../interfaces/IEpochExecutor.sol';
import '../interfaces/INoteTokenManager.sol';
import '../interfaces/IPool.sol';
import '../libraries/Math.sol';

contract EpochExecutor is IEpochExecutor {
    uint256 constant ONE = 10 ** 27;
    int256 public constant SUCCESS = 0;
    int256 public constant NEW_BEST = 0;
    int256 public constant ERR_CURRENCY_AVAILABLE = -1;
    int256 public constant ERR_MAX_ORDER = -2;
    int256 public constant ERR_MAX_RESERVE = -3;
    int256 public constant ERR_MIN_SENIOR_RATIO = -4;
    int256 public constant ERR_MAX_SENIOR_RATIO = -5;
    int256 public constant ERR_NOT_NEW_BEST = -6;
    int256 public constant ERR_POOL_CLOSING = -7;
    uint256 public constant BIG_NUMBER = ONE * ONE;
    uint256 public constant WEIGHT_SENIOR_WITHDRAW = 1000000;
    uint256 public constant WEIGHT_JUNIOR_WITHDRAW = 100000;
    uint256 public constant WEIGHT_SENIOR_INVEST = 10000;
    uint256 public constant WEIGHT_JUNIOR_INVEST = 1000;

    modifier isNewEpoch(address pool) {
        require(Math.safeSub(block.timestamp, epochInfor[pool].lastEpochClosed) >= epochInfor[pool].minimumEpochTime);
        _;
    }

    INoteTokenManager public sotManager;
    INoteTokenManager public jotManager;

    mapping(address => EpochInformation) public epochInfor;
    mapping(address => uint256) public debtCeiling;

    constructor(address sotManager_, address jotManager_) {
        sotManager = INoteTokenManager(sotManager_);
        jotManager = INoteTokenManager(jotManager_);
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

    function closeEpoch(address pool) external isNewEpoch(pool) returns (bool epochExecuted) {
        require(epochInfor[pool].submitPeriod == false);
        IPool _pool = IPool(pool);
        epochInfor[pool].lastEpochClosed = block.timestamp;
        epochInfor[pool].currentEpoch += 1;

        (uint256 orderJuniorInvest, uint256 orderJuniorWithdraw) = jotManager.closeEpoch(pool);
        (uint256 orderSeniorInvest, uint256 orderSeniorWithdraw) = sotManager.closeEpoch(pool);
        (uint256 seniorDebt, uint256 seniorBalance) = _pool.seniorDebtAndBalance();
        epochInfor[pool].epochSeniorAsset = Math.safeAdd(seniorDebt, seniorBalance);

        epochInfor[pool].epochNAV = _pool.currentNAV();
        epochInfor[pool].epochCapitalReserve = _pool.capitalReserve();
        epochInfor[pool].epochIncomeReserve = _pool.incomeReserve();

        if (orderSeniorWithdraw == 0 && orderJuniorWithdraw == 0 && orderJuniorInvest == 0 && orderSeniorInvest == 0) {
            jotManager.epochUpdate(pool, epochInfor[pool].currentEpoch, 0, 0, 0, 0, 0);
            sotManager.epochUpdate(pool, epochInfor[pool].currentEpoch, 0, 0, 0, 0, 0);
        }

        (uint256 sotPrice, uint256 jotPrice) = _pool.calcTokenPrices();
        epochInfor[pool].sotPrice = sotPrice;
        epochInfor[pool].jotPrice = jotPrice;

        if (jotPrice == 0) {
            epochInfor[pool].poolClosing = true;
        }

        epochInfor[pool].order.sotWithdraw = Math.rmul(orderSeniorWithdraw, sotPrice);
        epochInfor[pool].order.jotWithdraw = Math.rmul(orderJuniorWithdraw, jotPrice);
        epochInfor[pool].order.sotInvest = orderSeniorInvest;
        epochInfor[pool].order.jotInvest = orderJuniorInvest;

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
                epochInfor[pool].epochCapitalReserve,
                epochInfor[pool].epochNAV,
                epochInfor[pool].epochSeniorAsset,
                seniorWithdraw,
                juniorWithdraw,
                seniorInvest,
                juniorInvest
            );
    }

    function validate(
        address pool,
        uint256 capitalReserve_,
        uint256 nav_,
        uint256 seniorAsset_,
        uint256 seniorInvest,
        uint256 seniorWithdraw,
        uint256 juniorInvest,
        uint256 juniorWithdraw
    ) public view returns (int256) {
        uint256 currencyAvailable = Math.safeAdd(Math.safeAdd(capitalReserve_, seniorInvest), juniorInvest);
        // TO DO: calculate the withdrawal after subtract the income part
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
        if (epochInfor[pool].poolClosing == true) {
            if (seniorInvest == 0 && juniorInvest == 0) {
                return SUCCESS;
            }
            return ERR_POOL_CLOSING;
        }
        return validatePoolConstraints(pool, newReserve, seniorAsset_, nav_);
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
        return SUCCESS;
    }

    function validatePoolConstraints(
        address pool,
        uint256 reserve_,
        uint256 seniorAsset,
        uint256 nav_
    ) public view returns (int256 err) {
        // constraint 3: max capital reserve
        if (reserve_ > debtCeiling[pool]) {
            return ERR_MAX_RESERVE;
        }
        uint256 assets = Math.safeAdd(nav_, reserve_);
        // constraint 4: min first loss
        return validateMinFirstLoss(assets, seniorAsset);
    }

    function validateMinFirstLoss(uint256 assets, uint256 seniorAsset) public view returns (int256) {
        // TO DO: validate minFirstLoss
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
        uint256 epochID = Math.safeAdd(epochInfor[pool].lastEpochExecuted, 1);
        epochInfor[pool].submitPeriod = false;

        sotManager.epochUpdate(
            pool,
            epochID,
            _calcFullfillment(sotInvest, epochInfor[pool].order.sotInvest),
            _calcFullfillment(sotWithdraw, epochInfor[pool].order.sotWithdraw),
            epochInfor[pool].sotPrice,
            epochInfor[pool].order.sotInvest,
            epochInfor[pool].order.sotWithdraw
        );

        IPool(pool).changeSeniorAsset(sotInvest, sotWithdraw);

        jotManager.epochUpdate(
            pool,
            epochID,
            _calcFullfillment(jotInvest, epochInfor[pool].order.jotInvest),
            _calcFullfillment(jotWithdraw, epochInfor[pool].order.jotWithdraw),
            epochInfor[pool].jotPrice,
            epochInfor[pool].order.jotInvest,
            epochInfor[pool].order.jotWithdraw
        );

        uint256 newReserve = calcNewReserve(pool, sotWithdraw, jotWithdraw, sotInvest, jotInvest);
        IPool(pool).changeSeniorAsset(0, 0);

        // TO DO: change capital reserve

        epochInfor[pool].lastEpochExecuted = epochID;
        epochInfor[pool].minChallengePeriodEnd = 0;
        epochInfor[pool].bestSubScore = 0;
        epochInfor[pool].gotFullValidation = false;
    }

    function _calcFullfillment(uint256 amount, uint256 totalOrder) public pure returns (uint256 percent) {
        if (amount == 0 || totalOrder == 0) {
            return 0;
        }
        return Math.rdiv(amount, totalOrder);
    }

    function calcNewReserve(
        address pool,
        uint256 sotWithdraw,
        uint256 jotWithdraw,
        uint256 sotInvest,
        uint256 jotInvest
    ) public view returns (uint256) {
        // TO DO: calculate the withdrawal after subtract income

        // TO DO: calculate new income reserve
        return
            Math.safeSub(
                Math.safeAdd(Math.safeAdd(epochInfor[pool].epochCapitalReserve, sotInvest), jotInvest),
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
