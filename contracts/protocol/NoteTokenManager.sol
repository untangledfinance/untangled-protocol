// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts/interfaces/IERC20.sol';
import {ECDSAUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol';
import {UntangledBase} from '../base/UntangledBase.sol';
import {POOL_ADMIN_ROLE} from '../libraries/DataTypes.sol';
import '../interfaces/INoteTokenManager.sol';
import '../interfaces/INoteToken.sol';
import '../interfaces/IPool.sol';
import '../interfaces/IEpochExecutor.sol';
import '../libraries/Math.sol';
import '../libraries/logic/GenericLogic.sol';
import '../libraries/ConfigHelper.sol';
import '../libraries/Configuration.sol';

contract NoteTokenManager is
    INoteTokenManager,
    Initializable,
    PausableUpgradeable,
    AccessControlEnumerableUpgradeable,
    ReentrancyGuardUpgradeable
{
    struct Epoch {
        uint256 withdrawFulfillment;
        uint256 investFullfillment;
        uint256 price;
    }

    struct UserOrder {
        uint256 orderedInEpoch;
        uint256 investCurrencyAmount;
        uint256 withdrawTokenAmount;
    }

    event TokenMinted(address pool, address receiver, uint256 amount);
    using ConfigHelper for Registry;
    Registry public registry;

    mapping(address => uint256) public totalWithdraw;
    mapping(address => uint256) public totalInvest;

    mapping(address => address) public noteToken;
    mapping(address => address) public issuers;

    mapping(address => mapping(uint256 => Epoch)) public epochs;

    mapping(address => uint256) public requestedCurrency;
    mapping(address => address) public poolAdmin;

    mapping(address => mapping(address => UserOrder)) orders;
    mapping(address => bool) public waitingForUpdate;

    mapping(address => uint256) public nonces;

    IEpochExecutor public epochExecutor;
    IERC20 public currency;

    modifier onlyPoolAdmin(address pool) {
        require(msg.sender == poolAdmin[pool], 'only pool admin');
        _;
    }

    function _incrementNonce(address account) internal {
        nonces[account] += 1;
    }

    function initialize(Registry registry_, address epochExecutor_, address currency_) public initializer {
        __Pausable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __AccessControlEnumerable_init_unchained();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        registry = registry_;
        epochExecutor = IEpochExecutor(epochExecutor_);
        currency = IERC20(currency_);
    }

    function setUpPoolAdmin(address admin) external {
        poolAdmin[msg.sender] = admin;
    }

    function investOrder(address pool, address user, uint256 newInvestAmount) public {
        orders[pool][user].orderedInEpoch = epochExecutor.currentEpoch(pool);
        uint256 currentInvestAmount = orders[pool][user].investCurrencyAmount;
        orders[pool][user].investCurrencyAmount = newInvestAmount;
        totalInvest[pool] = Math.safeAdd(Math.safeSub(totalInvest[pool], currentInvestAmount), newInvestAmount);
        if (newInvestAmount > currentInvestAmount) {
            require(
                currency.transferFrom(user, issuers[pool], Math.safeSub(newInvestAmount, currentInvestAmount)),
                'NoteTokenManager: currency transfer failed'
            );
            return;
        } else if (newInvestAmount < currentInvestAmount) {
            currency.transferFrom(issuers[pool], user, Math.safeSub(currentInvestAmount, newInvestAmount));
        }
    }

    function withdrawOrder(address pool, address user, uint256 newWithdrawAmount) public {
        orders[pool][user].orderedInEpoch = epochExecutor.currentEpoch(pool);
        uint256 currentWithdrawAmount = orders[pool][user].withdrawTokenAmount;
        orders[pool][user].withdrawTokenAmount = newWithdrawAmount;
        totalWithdraw[pool] = Math.safeAdd(Math.safeSub(totalWithdraw[pool], currentWithdrawAmount), newWithdrawAmount);
        if (newWithdrawAmount > currentWithdrawAmount) {
            INoteToken(noteToken[pool]).transfer(issuers[pool], Math.safeSub(newWithdrawAmount, currentWithdrawAmount));
            return;
        } else if (newWithdrawAmount < currentWithdrawAmount) {
            INoteToken(noteToken[pool]).transferFrom(
                issuers[pool],
                user,
                Math.safeSub(currentWithdrawAmount, newWithdrawAmount)
            );
        }
    }

    function calcDisburse(
        address pool,
        address user
    )
        public
        view
        returns (
            uint256 payoutCurrencyAmount,
            uint256 payoutTokenAmount,
            uint256 remainingInvestCurrency,
            uint256 remainingWithdrawToken
        )
    {
        return calcDisburse(pool, user, epochExecutor.lastEpochExecuted(pool));
    }

    function calcDisburse(
        address pool,
        address user,
        uint256 endEpoch
    )
        public
        view
        returns (
            uint256 payoutCurrencyAmount,
            uint256 payoutTokenAmount,
            uint256 remainingInvestCurrency,
            uint256 remainingWithdrawToken
        )
    {
        uint256 epochIdx = orders[pool][user].orderedInEpoch;
        uint256 lastEpochExecuted = epochExecutor.lastEpochExecuted(pool);
        // no disburse possible in epoch
        if (epochIdx == lastEpochExecuted) {
            return (
                payoutCurrencyAmount,
                payoutTokenAmount,
                orders[pool][user].investCurrencyAmount,
                orders[pool][user].withdrawTokenAmount
            );
        }

        if (endEpoch > lastEpochExecuted) {
            endEpoch = lastEpochExecuted;
        }

        remainingInvestCurrency = orders[pool][user].investCurrencyAmount;
        remainingWithdrawToken = orders[pool][user].withdrawTokenAmount;

        uint256 amount = 0;

        while (epochIdx <= endEpoch && (remainingInvestCurrency != 0 || remainingWithdrawToken != 0)) {
            if (remainingInvestCurrency != 0) {
                amount = Math.rmul(remainingInvestCurrency, epochs[pool][epochIdx].investFullfillment);
                if (amount != 0) {
                    payoutTokenAmount = Math.safeAdd(
                        payoutTokenAmount,
                        Math.safeDiv(Math.safeMul(amount, ONE), epochs[pool][epochIdx].price)
                    );
                    remainingInvestCurrency = Math.safeSub(remainingInvestCurrency, amount);
                }
            }
            if (remainingWithdrawToken != 0) {
                amount = Math.rmul(remainingWithdrawToken, epochs[pool][epochIdx].withdrawFulfillment);
                if (amount != 0) {
                    payoutCurrencyAmount = Math.safeAdd(
                        payoutCurrencyAmount,
                        Math.rmul(amount, epochs[pool][epochIdx].price)
                    );
                    remainingWithdrawToken = Math.safeSub(remainingWithdrawToken, amount);
                }
            }
            epochIdx = Math.safeAdd(epochIdx, 1);
        }
        return (payoutCurrencyAmount, payoutTokenAmount, remainingInvestCurrency, remainingWithdrawToken);
    }

    function disburse(
        address pool,
        address user
    )
        public
        returns (
            uint256 payoutCurrencyAmount,
            uint256 payoutTokenAmount,
            uint256 remainingInvestCurrency,
            uint256 remainingWithdrawToken
        )
    {
        return disburse(pool, user, epochExecutor.lastEpochExecuted(pool));
    }

    function disburse(
        address pool,
        address user,
        uint256 endEpoch
    )
        public
        returns (
            uint256 payoutCurrencyAmount,
            uint256 payoutTokenAmount,
            uint256 remainingInvestCurrency,
            uint256 remainingWithdrawToken
        )
    {
        require(
            orders[pool][user].orderedInEpoch >= epochExecutor.lastEpochExecuted(pool),
            'NoteTokenManager: epoch not executed yet'
        );
        uint256 lastEpochExecuted = epochExecutor.lastEpochExecuted(pool);
        if (endEpoch > lastEpochExecuted) {
            endEpoch = lastEpochExecuted;
        }
        (payoutCurrencyAmount, payoutTokenAmount, remainingInvestCurrency, remainingWithdrawToken) = calcDisburse(
            pool,
            user
        );

        orders[pool][user].investCurrencyAmount = remainingInvestCurrency;
        orders[pool][user].withdrawTokenAmount = remainingWithdrawToken;

        orders[pool][user].orderedInEpoch = Math.safeAdd(endEpoch, 1);

        if (payoutCurrencyAmount > 0) {
            currency.transferFrom(issuers[pool], user, payoutCurrencyAmount);
        }

        if (payoutTokenAmount > 0) {
            mint(pool, user, payoutTokenAmount);
        }

        return (payoutCurrencyAmount, payoutTokenAmount, remainingInvestCurrency, remainingWithdrawToken);
    }

    function closeEpoch(address pool) public returns (uint256 totalInvestCurrency_, uint256 totalWithdrawToken_) {
        require(waitingForUpdate[pool] == false, 'NoteTokenManager: pool is closed');
        waitingForUpdate[pool] = true;
        return (totalInvest[pool], totalWithdraw[pool]);
    }

    function epochUpdate(
        address pool,
        uint256 epochID,
        uint256 investFulfillment_,
        uint256 withdrawFulfillment_,
        uint256 tokenPrice_,
        uint256 epochInvestOrderCurrency,
        uint256 epochWithdrawOrderCurrency
    ) public {
        require(waitingForUpdate[pool] == true, 'NoteTokenManager: epoch is not closed yet.');
        waitingForUpdate[pool] = false;
        epochs[pool][epochID].investFullfillment = investFulfillment_;
        epochs[pool][epochID].withdrawFulfillment = withdrawFulfillment_;
        epochs[pool][epochID].price = tokenPrice_;

        uint256 withdrawInToken = 0;
        uint256 investInToken = 0;
        if (tokenPrice_ > 0) {
            investInToken = Math.rdiv(epochInvestOrderCurrency, tokenPrice_);
            withdrawInToken = Math.safeDiv(Math.safeMul(epochWithdrawOrderCurrency, ONE), tokenPrice_);
        }

        totalInvest[pool] = Math.safeAdd(
            Math.safeSub(totalInvest[pool], epochInvestOrderCurrency),
            Math.rmul(epochInvestOrderCurrency, Math.safeSub(ONE, epochs[pool][epochID].investFullfillment))
        );

        totalWithdraw[pool] = Math.safeAdd(
            Math.safeSub(totalWithdraw[pool], withdrawInToken),
            Math.rmul(withdrawInToken, Math.safeSub(ONE, epochs[pool][epochID].withdrawFulfillment))
        );
    }

    function mint(address pool, address receiver, uint256 amount) public returns (uint256) {
        INoteToken(noteToken[pool]).mint(receiver, amount);
        emit TokenMinted(pool, receiver, amount);
        return amount;
    }
}
