// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts/interfaces/IERC20.sol';
import {ECDSAUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol';
import {UntangledBase} from '../base/UntangledBase.sol';
import {POOL_ADMIN_ROLE, ONE} from '../libraries/DataTypes.sol';
import '../interfaces/INoteTokenManager.sol';
import '../interfaces/INoteToken.sol';
import '../interfaces/IPool.sol';
import '../interfaces/IEpochExecutor.sol';
import '../libraries/Math.sol';
import '../libraries/ConfigHelper.sol';
import '../libraries/Configuration.sol';
import 'hardhat/console.sol';

contract NoteTokenManager is
    INoteTokenManager,
    Initializable,
    PausableUpgradeable,
    AccessControlEnumerableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using ConfigHelper for Registry;
    Registry public registry;

    event InvestOrder(address pool, address from, uint256 amount);
    event WithdrawOrder(address pool, address from, uint256 amount);
    uint256 constant RATE_SCALING_FACTOR = 10 ** 4;
    uint256 constant ONE_HUNDRED_PERCENT = 100 * RATE_SCALING_FACTOR;
    mapping(address => uint256) public totalWithdraw;
    mapping(address => uint256) public totalInvest;
    mapping(address => uint256) public totalIncomeWithdraw;
    mapping(address => uint256) public totalValueRaised;

    mapping(address => NoteTokenInfor) public tokenInfor;

    mapping(address => mapping(uint256 => Epoch)) public epochs;

    mapping(address => address) public poolAdmin;

    mapping(address => mapping(address => UserOrder)) orders;
    mapping(address => bool) public waitingForUpdate;

    mapping(address => uint256) public nonces;

    IEpochExecutor public epochExecutor;
    IERC20 public currency;

    modifier onlyPoolAdmin(address pool) {
        _onlyPoolAdmin(pool);
        _;
    }

    modifier onlyEpochExecutor() {
        _onlyEpochExecutor();
        _;
    }

    function _onlyEpochExecutor() internal view {
        require(msg.sender == address(epochExecutor), 'only epoch executor');
    }

    function _onlyPoolAdmin(address pool) internal view {
        require(msg.sender == poolAdmin[pool], 'only pool admin');
    }

    function _incrementNonce(address account) internal {
        nonces[account] += 1;
    }

    function initialize(Registry registry_, address currency_) public initializer {
        __Pausable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __AccessControlEnumerable_init_unchained();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        registry = registry_;
        currency = IERC20(currency_);
    }

    function setUpEpochExecutor() public {
        require(address(registry.getEpochExecutor()) != address(0), 'no epoch executor found');
        epochExecutor = registry.getEpochExecutor();
    }

    function setUpPoolAdmin(address admin) external {
        poolAdmin[msg.sender] = admin;
    }

    function setupNewToken(address pool, address tokenAddress, uint256 minBidAmount) external {
        tokenInfor[pool].tokenAddress = tokenAddress;
        tokenInfor[pool].correspondingPool = pool;
        tokenInfor[pool].minBidAmount = minBidAmount;
        emit NewTokenAdded(pool, tokenAddress, block.timestamp);
    }

    // only KYCed users
    function investOrder(address pool, uint256 newInvestAmount) public {
        require(tokenInfor[pool].tokenAddress != address(0), 'NoteTokenManager: No note token found');
        require(newInvestAmount >= tokenInfor[pool].minBidAmount, 'NoteTokenManager: invest amount is too low');
        orders[pool][msg.sender].orderedInEpoch = epochExecutor.currentEpoch(pool);
        uint256 currentInvestAmount = orders[pool][msg.sender].investCurrencyAmount;
        orders[pool][msg.sender].investCurrencyAmount = newInvestAmount;
        totalInvest[pool] = Math.safeAdd(Math.safeSub(totalInvest[pool], currentInvestAmount), newInvestAmount);
        if (newInvestAmount > currentInvestAmount) {
            require(
                currency.transferFrom(
                    msg.sender,
                    IPool(pool).pot(),
                    Math.safeSub(newInvestAmount, currentInvestAmount)
                ),
                'NoteTokenManager: currency transfer failed'
            );
            return;
        } else if (newInvestAmount < currentInvestAmount) {
            currency.transferFrom(IPool(pool).pot(), msg.sender, Math.safeSub(currentInvestAmount, newInvestAmount));
        }
        emit InvestOrder(pool, msg.sender, newInvestAmount);
    }

    // only KYCed users
    function withdrawOrder(address pool, uint256 newWithdrawAmount) public {
        address tokenAddress = tokenInfor[pool].tokenAddress;
        require(tokenAddress != address(0), 'NoteTokenManager: No note token found');
        orders[pool][msg.sender].orderedInEpoch = epochExecutor.currentEpoch(pool);
        uint256 userIncomeBalance = INoteToken(tokenAddress).getUserIncome(msg.sender);
        uint256 currentWithdrawAmount = orders[pool][msg.sender].withdrawTokenAmount;
        uint256 currentIncomeWithdraw = orders[pool][msg.sender].withdrawIncomeTokenAmount;
        if (newWithdrawAmount > userIncomeBalance) {
            totalIncomeWithdraw[pool] = Math.safeAdd(
                Math.safeSub(totalIncomeWithdraw[pool], currentIncomeWithdraw),
                userIncomeBalance
            );
            orders[pool][msg.sender].withdrawIncomeTokenAmount = userIncomeBalance;
        } else {
            totalIncomeWithdraw[pool] = Math.safeAdd(
                Math.safeSub(totalIncomeWithdraw[pool], currentIncomeWithdraw),
                newWithdrawAmount
            );
            orders[pool][msg.sender].withdrawIncomeTokenAmount = newWithdrawAmount;
        }
        orders[pool][msg.sender].withdrawTokenAmount = newWithdrawAmount;

        totalWithdraw[pool] = Math.safeAdd(Math.safeSub(totalWithdraw[pool], currentWithdrawAmount), newWithdrawAmount);
        if (newWithdrawAmount > currentWithdrawAmount) {
            INoteToken(tokenAddress).transfer(
                IPool(pool).pot(),
                Math.safeSub(newWithdrawAmount, currentWithdrawAmount)
            );
            return;
        } else if (newWithdrawAmount < currentWithdrawAmount) {
            INoteToken(tokenAddress).transferFrom(
                IPool(pool).pot(),
                msg.sender,
                Math.safeSub(currentWithdrawAmount, newWithdrawAmount)
            );
        }
        emit WithdrawOrder(pool, msg.sender, newWithdrawAmount);
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
            uint256 remainingWithdrawToken,
            uint256 remainingIncomeWithdrawToken
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
            uint256 remainingWithdrawToken,
            uint256 remainingIncomeWithdrawToken
        )
    {
        uint256 epochIdx = orders[pool][user].orderedInEpoch;
        // no disburse possible in epoch
        if (epochIdx == epochExecutor.currentEpoch(pool)) {
            return (
                payoutCurrencyAmount,
                payoutTokenAmount,
                orders[pool][user].investCurrencyAmount,
                orders[pool][user].withdrawTokenAmount,
                orders[pool][user].withdrawIncomeTokenAmount
            );
        }

        if (endEpoch > epochExecutor.lastEpochExecuted(pool)) {
            endEpoch = epochExecutor.lastEpochExecuted(pool);
        }

        remainingInvestCurrency = orders[pool][user].investCurrencyAmount;
        remainingWithdrawToken = orders[pool][user].withdrawTokenAmount;
        remainingIncomeWithdrawToken = orders[pool][user].withdrawIncomeTokenAmount;
        uint256 amount = 0;

        while (epochIdx <= endEpoch && (remainingInvestCurrency != 0 || remainingWithdrawToken != 0)) {
            if (remainingInvestCurrency != 0) {
                amount = (remainingInvestCurrency * epochs[pool][epochIdx].investFulfillment) / ONE_HUNDRED_PERCENT;
                if (amount != 0) {
                    payoutTokenAmount = payoutTokenAmount + (amount * 10 ** 18) / epochs[pool][epochIdx].price;
                    remainingInvestCurrency -= amount;
                }
            }
            if (remainingWithdrawToken != 0) {
                // user have income withdrawal and have withdrawal fulfillment < 100%
                if (
                    remainingIncomeWithdrawToken != 0 &&
                    epochs[pool][epochIdx].withdrawIncomeFulfillment != ONE_HUNDRED_PERCENT
                ) {
                    amount =
                        (remainingIncomeWithdrawToken * epochs[pool][epochIdx].withdrawIncomeFulfillment) /
                        ONE_HUNDRED_PERCENT;
                    if (amount != 0) {
                        payoutCurrencyAmount =
                            payoutCurrencyAmount +
                            (amount * epochs[pool][epochIdx].price) /
                            10 ** 18;
                        remainingIncomeWithdrawToken = remainingIncomeWithdrawToken - amount;
                        remainingWithdrawToken = remainingWithdrawToken - amount;
                    }
                } else {
                    // all income can be withdraw or user don't have income withdrawal
                    // total withdrawal = totalIncomeWithdrawal + capitalFulfillment * totalCapitalWithdrawal
                    amount =
                        ((remainingWithdrawToken - remainingIncomeWithdrawToken) *
                            epochs[pool][epochIdx].withdrawCapitalFulfillment) / // calculate remaining capital withdrawal
                        ONE_HUNDRED_PERCENT +
                        remainingIncomeWithdrawToken;
                    if (amount != 0) {
                        payoutCurrencyAmount =
                            payoutCurrencyAmount +
                            (amount * epochs[pool][epochIdx].price) /
                            10 ** 18;
                        remainingIncomeWithdrawToken = 0;
                        remainingWithdrawToken = remainingWithdrawToken - amount;
                    }
                }
            }
            epochIdx = Math.safeAdd(epochIdx, 1);
        }
        return (
            payoutCurrencyAmount,
            payoutTokenAmount,
            remainingInvestCurrency,
            remainingWithdrawToken,
            remainingIncomeWithdrawToken
        );
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
            uint256 remainingWithdrawToken,
            uint256 remainingIncomeWithdrawToken
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
            uint256 remainingWithdrawToken,
            uint256 remainingIncomeWithdrawToken
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
        (
            payoutCurrencyAmount,
            payoutTokenAmount,
            remainingInvestCurrency,
            remainingWithdrawToken,
            remainingIncomeWithdrawToken
        ) = calcDisburse(pool, user);
        uint256 withdrawTokenAmount = orders[pool][user].withdrawTokenAmount - remainingWithdrawToken;
        uint256 withdrawIncomeTokenAmount = orders[pool][user].withdrawIncomeTokenAmount - remainingIncomeWithdrawToken;
        orders[pool][user].investCurrencyAmount = remainingInvestCurrency;
        orders[pool][user].withdrawTokenAmount = remainingWithdrawToken;
        orders[pool][user].withdrawIncomeTokenAmount = remainingIncomeWithdrawToken;

        orders[pool][user].orderedInEpoch = Math.safeAdd(endEpoch, 1);

        if (payoutCurrencyAmount > 0) {
            currency.transferFrom(IPool(pool).pot(), user, payoutCurrencyAmount);
            INoteToken(tokenInfor[pool].tokenAddress).decreaseUserIncome(user, withdrawIncomeTokenAmount);
            INoteToken(tokenInfor[pool].tokenAddress).decreaseUserPrinciple(user, withdrawTokenAmount);
        }

        if (payoutTokenAmount > 0) {
            INoteToken(tokenInfor[pool].tokenAddress).mint(user, payoutTokenAmount);
            INoteToken(tokenInfor[pool].tokenAddress).increaseUserPrinciple(user, payoutTokenAmount);
        }

        return (
            payoutCurrencyAmount,
            payoutTokenAmount,
            remainingInvestCurrency,
            remainingWithdrawToken,
            remainingIncomeWithdrawToken
        );
    }

    function closeEpoch(
        address pool
    )
        public
        onlyEpochExecutor
        returns (uint256 totalInvestCurrency_, uint256 totalWithdrawToken_, uint256 totalIncomeWithdrawToken_)
    {
        require(waitingForUpdate[pool] == false, 'NoteTokenManager: pool is closed');
        waitingForUpdate[pool] = true;
        return (totalInvest[pool], totalWithdraw[pool], totalIncomeWithdraw[pool]);
    }
    // only EpochExecutor
    function epochUpdate(
        address pool,
        uint256 epochID,
        uint256 investFulfillment_,
        uint256 withdrawFulfillment_,
        uint256 tokenPrice_,
        uint256 epochInvestOrderCurrency,
        uint256 epochWithdrawOrderCurrency
    ) public onlyEpochExecutor returns (uint256 finalCapitalWithdrawCurrency, uint256 finalIncomeWithdrawCurrency) {
        require(waitingForUpdate[pool] == true, 'NoteTokenManager: epoch is not closed yet.');
        waitingForUpdate[pool] = false;
        epochs[pool][epochID].investFulfillment = investFulfillment_;
        epochs[pool][epochID].withdrawIncomeFulfillment = ONE_HUNDRED_PERCENT;
        epochs[pool][epochID].price = tokenPrice_;

        uint256 withdrawInToken = 0;
        uint256 investInToken = 0;
        if (tokenPrice_ > 0) {
            investInToken = (epochInvestOrderCurrency * tokenPrice_) / 10 ** 18;
            withdrawInToken = (epochWithdrawOrderCurrency * 10 ** 18) / tokenPrice_;
        }

        totalInvest[pool] = Math.safeAdd(
            Math.safeSub(totalInvest[pool], epochInvestOrderCurrency),
            Math.rmul(epochInvestOrderCurrency, Math.safeSub(ONE_HUNDRED_PERCENT, investFulfillment_))
        );

        uint256 withdrawAmount = (withdrawInToken * withdrawFulfillment_) / ONE_HUNDRED_PERCENT;
        _adjustTokenBalance(pool, (investInToken * investFulfillment_) / ONE_HUNDRED_PERCENT, withdrawAmount);
        if (withdrawAmount == 0) {
            return (0, 0);
        }

        if (withdrawAmount < totalIncomeWithdraw[pool]) {
            epochs[pool][epochID].withdrawIncomeFulfillment =
                (withdrawInToken * ONE_HUNDRED_PERCENT) /
                totalIncomeWithdraw[pool];
            epochs[pool][epochID].withdrawCapitalFulfillment = 0;
            totalIncomeWithdraw[pool] = totalIncomeWithdraw[pool] - withdrawInToken;
            return (0, epochWithdrawOrderCurrency);
        }

        address tempPool = pool;
        epochs[tempPool][epochID].withdrawCapitalFulfillment =
            ((withdrawAmount - totalIncomeWithdraw[tempPool]) * ONE_HUNDRED_PERCENT) / // withdrawCapital = withdrawAmount - incomeWithdraw
            totalWithdraw[tempPool] -
            totalIncomeWithdraw[tempPool];

        finalIncomeWithdrawCurrency = totalIncomeWithdraw[tempPool];
        finalCapitalWithdrawCurrency = epochWithdrawOrderCurrency - finalIncomeWithdrawCurrency;
        totalIncomeWithdraw[tempPool] = 0;
        totalWithdraw[tempPool] = totalWithdraw[tempPool] - withdrawAmount;
    }

    function mint(address pool, address receiver, uint256 amount) public returns (uint256) {
        INoteToken(tokenInfor[pool].tokenAddress).mint(receiver, amount);
        emit TokenMinted(pool, receiver, amount);
        return amount;
    }

    function getTokenAddress(address pool) public view returns (address) {
        return tokenInfor[pool].tokenAddress;
    }

    function getTotalValueRaised(address pool) public view returns (uint256) {
        return totalValueRaised[pool];
    }

    function _adjustTokenBalance(address pool, uint256 epochInvestInToken, uint256 epochWithdrawInToken) internal {
        uint256 delta;
        if (epochWithdrawInToken > epochInvestInToken) {
            delta = Math.safeSub(epochWithdrawInToken, epochWithdrawInToken);
            INoteToken(tokenInfor[pool].tokenAddress).transferFrom(IPool(pool).pot(), address(this), delta);
            INoteToken(tokenInfor[pool].tokenAddress).burn(delta);
            return;
        }

        // if (epochWithdrawInToken < epochInvestInToken) {
        //     delta = Math.safeSub(epochInvestInToken, epochWithdrawInToken);
        //     INoteToken(tokenInfor[pool].tokenAddress).mint(IPool(pool).pot(), delta);
        // }
    }
}
