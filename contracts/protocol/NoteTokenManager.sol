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
    mapping(address => address[]) withdrawers;
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
    function investOrder(address pool, uint256 investAmount) public {
        require(tokenInfor[pool].tokenAddress != address(0), 'NoteTokenManager: No note token found');
        require(investAmount >= tokenInfor[pool].minBidAmount, 'NoteTokenManager: invest amount is too low');
        orders[pool][msg.sender].orderedInEpoch = epochExecutor.currentEpoch(pool);
        uint256 currentInvestAmount = orders[pool][msg.sender].investCurrencyAmount;
        orders[pool][msg.sender].investCurrencyAmount = investAmount;
        totalInvest[pool] = totalInvest[pool] - currentInvestAmount + investAmount;
        if (investAmount > currentInvestAmount) {
            require(
                currency.transferFrom(msg.sender, IPool(pool).pot(), Math.safeSub(investAmount, currentInvestAmount)),
                'NoteTokenManager: currency transfer failed'
            );
            return;
        } else if (investAmount < currentInvestAmount) {
            currency.transferFrom(IPool(pool).pot(), msg.sender, Math.safeSub(currentInvestAmount, investAmount));
        }
        emit InvestOrder(pool, msg.sender, investAmount);
    }

    // only KYCed users
    function withdrawOrder(address pool, uint256 withdrawAmount) public {
        require(withdrawAmount >= 0, 'NoteTokenManager: invalid withdraw amount');
        address tokenAddress = tokenInfor[pool].tokenAddress;
        require(tokenAddress != address(0), 'NoteTokenManager: No note token found');
        orders[pool][msg.sender].orderedInEpoch = epochExecutor.currentEpoch(pool);
        if (withdrawAmount != 0 && !_isWithdrawerExisted(pool, msg.sender)) {
            withdrawers[pool].push(msg.sender);
        }
        if (withdrawAmount == 0 && orders[pool][msg.sender].withdrawCurrencyAmount != 0) {
            _removeWithdrawer(pool, msg.sender);
        }
        totalWithdraw[pool] = totalWithdraw[pool] + withdrawAmount - orders[pool][msg.sender].withdrawCurrencyAmount;
        orders[pool][msg.sender].withdrawCurrencyAmount = withdrawAmount;

        emit WithdrawOrder(pool, msg.sender, withdrawAmount);
    }

    function _removeWithdrawer(address pool, address removedWithdrawer) internal {
        uint256 length = withdrawers[pool].length;
        for (uint256 i = 0; i < length; i++) {
            if (withdrawers[pool][i] == removedWithdrawer) {
                withdrawers[pool][i] = withdrawers[pool][length - 1];
                withdrawers[pool].pop();
                return;
            }
        }
    }

    function _isWithdrawerExisted(address pool, address user) internal view returns (bool) {
        uint256 length = withdrawers[pool].length;
        for (uint256 i = 0; i < length; i++) {
            if (withdrawers[pool][i] == user) {
                return true;
            }
        }
        return false;
    }

    function _updateIncomeWithdraw(address pool) internal {
        address[] memory users = withdrawers[pool];
        uint256 length = users.length;
        address tokenAddress = tokenInfor[pool].tokenAddress;
        for (uint256 i = 0; i < length; i++) {
            if (orders[pool][users[i]].withdrawCurrencyAmount != 0) {
                uint256 userIncomeBalance = INoteToken(tokenAddress).getUserIncome(users[i]);
                orders[pool][users[i]].withdrawIncomeCurrencyAmount += userIncomeBalance;
                totalIncomeWithdraw[pool] += userIncomeBalance;
            }
        }
        delete withdrawers[pool];
    }

    function calcDisburse(
        address pool,
        address user
    )
        public
        view
        returns (
            uint256 payoutCurrencyAmount,
            uint256 burnAmount,
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
            uint256 burnAmount,
            uint256 payoutTokenAmount,
            uint256 remainingInvestCurrency,
            uint256 remainingWithdrawCurrency,
            uint256 remainingIncomeWithdrawCurrency
        )
    {
        // no disburse possible in epoch
        if (orders[pool][user].orderedInEpoch == epochExecutor.currentEpoch(pool)) {
            return (
                payoutCurrencyAmount,
                0,
                payoutTokenAmount,
                orders[pool][user].investCurrencyAmount,
                orders[pool][user].withdrawCurrencyAmount,
                orders[pool][user].withdrawIncomeCurrencyAmount
            );
        }

        if (endEpoch > epochExecutor.lastEpochExecuted(pool)) {
            endEpoch = epochExecutor.lastEpochExecuted(pool);
        }
        uint256 epochIdx = orders[pool][user].orderedInEpoch;

        remainingInvestCurrency = orders[pool][user].investCurrencyAmount;
        remainingWithdrawCurrency = orders[pool][user].withdrawCurrencyAmount;
        remainingIncomeWithdrawCurrency = orders[pool][user].withdrawIncomeCurrencyAmount;
        uint256 amount = 0;

        while (epochIdx <= endEpoch && (remainingInvestCurrency != 0 || remainingWithdrawCurrency != 0)) {
            if (remainingInvestCurrency != 0) {
                amount = (remainingInvestCurrency * epochs[pool][epochIdx].investFulfillment) / ONE_HUNDRED_PERCENT;
                if (amount != 0) {
                    payoutTokenAmount = payoutTokenAmount + (amount * 10 ** 18) / epochs[pool][epochIdx].price;
                    remainingInvestCurrency -= amount;
                }
            }
            if (remainingWithdrawCurrency != 0) {
                // user have income withdrawal and have withdrawal fulfillment < 100%
                if (
                    remainingIncomeWithdrawCurrency != 0 &&
                    epochs[pool][epochIdx].withdrawIncomeFulfillment != ONE_HUNDRED_PERCENT
                ) {
                    amount =
                        (remainingIncomeWithdrawCurrency * epochs[pool][epochIdx].withdrawIncomeFulfillment) /
                        ONE_HUNDRED_PERCENT;
                    if (epochs[pool][epochIdx].price != 0) {
                        burnAmount += (amount * 10 ** 18) / epochs[pool][epochIdx].price;
                    }

                    if (amount != 0) {
                        payoutCurrencyAmount += amount;
                        remainingIncomeWithdrawCurrency -= amount;
                        remainingWithdrawCurrency -= amount;
                    }
                } else {
                    // all income can be withdraw or user don't have income withdrawal
                    // total withdrawal = totalIncomeWithdrawal + capitalFulfillment * totalCapitalWithdrawal
                    amount =
                        ((remainingWithdrawCurrency - remainingIncomeWithdrawCurrency) *
                            epochs[pool][epochIdx].withdrawCapitalFulfillment) / // calculate remaining capital withdrawal
                        ONE_HUNDRED_PERCENT +
                        remainingIncomeWithdrawCurrency;
                    if (epochs[pool][epochIdx].price != 0) {
                        burnAmount += (amount * 10 ** 18) / epochs[pool][epochIdx].price;
                    }
                    if (amount != 0) {
                        payoutCurrencyAmount += amount;
                        remainingIncomeWithdrawCurrency = 0;
                        remainingWithdrawCurrency -= amount;
                    }
                }
            }
            epochIdx = Math.safeAdd(epochIdx, 1);
        }
        return (
            payoutCurrencyAmount,
            burnAmount,
            payoutTokenAmount,
            remainingInvestCurrency,
            remainingWithdrawCurrency,
            remainingIncomeWithdrawCurrency
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
            uint256 burnAmount,
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
            uint256 burnAmount,
            uint256 remainingInvestCurrency,
            uint256 remainingWithdrawCurrency,
            uint256 remainingIncomeWithdrawCurrency
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
            burnAmount,
            payoutTokenAmount,
            remainingInvestCurrency,
            remainingWithdrawCurrency,
            remainingIncomeWithdrawCurrency
        ) = calcDisburse(pool, user);
        uint256 withdrawTokenAmount = orders[pool][user].withdrawCurrencyAmount - remainingWithdrawCurrency;
        uint256 withdrawIncomeTokenAmount = orders[pool][user].withdrawIncomeCurrencyAmount -
            remainingIncomeWithdrawCurrency;
        orders[pool][user].investCurrencyAmount = remainingInvestCurrency;
        orders[pool][user].withdrawCurrencyAmount = remainingWithdrawCurrency;
        orders[pool][user].withdrawIncomeCurrencyAmount = remainingIncomeWithdrawCurrency;

        orders[pool][user].orderedInEpoch = endEpoch + 1;

        if (payoutCurrencyAmount > 0) {
            IPool(pool).disburse(user, payoutCurrencyAmount);
            INoteToken(tokenInfor[pool].tokenAddress).transferFrom(user, address(this), burnAmount);
            INoteToken(tokenInfor[pool].tokenAddress).burn(burnAmount);
            INoteToken(tokenInfor[pool].tokenAddress).decreaseUserIncome(user, withdrawIncomeTokenAmount);
            INoteToken(tokenInfor[pool].tokenAddress).decreaseUserPrinciple(user, withdrawTokenAmount);
        }

        if (payoutTokenAmount > 0) {
            INoteToken(tokenInfor[pool].tokenAddress).mint(user, payoutTokenAmount);
        }

        return (
            payoutCurrencyAmount,
            burnAmount,
            payoutTokenAmount,
            remainingInvestCurrency,
            remainingWithdrawCurrency,
            remainingIncomeWithdrawCurrency
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
        _updateIncomeWithdraw(pool);
        return (totalInvest[pool], totalWithdraw[pool], totalIncomeWithdraw[pool]);
    }
    // only EpochExecutor
    function epochUpdate(
        address pool,
        uint256 epochID,
        uint256 investFulfillment_,
        uint256 withdrawFulfillment_,
        uint256 tokenPrice_,
        uint256 epochInvestCurrency,
        uint256 epochWithdrawCurrency
    ) public onlyEpochExecutor returns (uint256 capitalWithdraw, uint256 incomeWithdraw) {
        require(waitingForUpdate[pool] == true, 'NoteTokenManager: epoch is not closed yet.');
        waitingForUpdate[pool] = false;
        epochs[pool][epochID].investFulfillment = investFulfillment_;
        epochs[pool][epochID].price = tokenPrice_;

        uint256 epochWithdrawableCurrency = (epochWithdrawCurrency * withdrawFulfillment_) / ONE_HUNDRED_PERCENT;
        uint256 epochInvestableCurrency = (epochInvestCurrency * investFulfillment_) / ONE_HUNDRED_PERCENT;

        if (epochInvestableCurrency > epochWithdrawableCurrency) {
            totalValueRaised[pool] += epochInvestableCurrency - epochWithdrawableCurrency;
        }
        if (epochInvestableCurrency < epochWithdrawableCurrency) {
            totalValueRaised[pool] -= epochWithdrawableCurrency - epochInvestableCurrency;
        }
        (incomeWithdraw, capitalWithdraw) = _updateWithdrawFulfillment(pool, epochID, epochWithdrawableCurrency);

        totalInvest[pool] -= epochInvestableCurrency;
        totalWithdraw[pool] -= epochWithdrawableCurrency;
    }

    function _updateWithdrawFulfillment(
        address pool,
        uint256 epochID,
        uint256 epochWithdrawCurrency
    ) internal returns (uint256 incomeWithdraw, uint256 capitalWithdraw) {
        if (totalWithdraw[pool] == 0) {
            epochs[pool][epochID].withdrawIncomeFulfillment = ONE_HUNDRED_PERCENT;
            epochs[pool][epochID].withdrawCapitalFulfillment = ONE_HUNDRED_PERCENT;
            return (0, 0);
        }

        uint256 totalCapitalWithdraw = totalWithdraw[pool] - totalIncomeWithdraw[pool];

        if (totalIncomeWithdraw[pool] == 0) {
            epochs[pool][epochID].withdrawIncomeFulfillment = ONE_HUNDRED_PERCENT;
            epochs[pool][epochID].withdrawCapitalFulfillment =
                (epochWithdrawCurrency * ONE_HUNDRED_PERCENT) /
                totalWithdraw[pool];
            return (0, epochWithdrawCurrency);
        }

        if (totalCapitalWithdraw == 0) {
            epochs[pool][epochID].withdrawIncomeFulfillment =
                (epochWithdrawCurrency * ONE_HUNDRED_PERCENT) /
                totalIncomeWithdraw[pool];
            epochs[pool][epochID].withdrawCapitalFulfillment = ONE_HUNDRED_PERCENT;
            totalIncomeWithdraw[pool] -= epochWithdrawCurrency;
            return (epochWithdrawCurrency, 0);
        }

        if (epochWithdrawCurrency >= totalIncomeWithdraw[pool]) {
            epochs[pool][epochID].withdrawIncomeFulfillment = ONE_HUNDRED_PERCENT;
            epochs[pool][epochID].withdrawCapitalFulfillment =
                ((epochWithdrawCurrency - totalIncomeWithdraw[pool]) * ONE_HUNDRED_PERCENT) /
                totalCapitalWithdraw;
            incomeWithdraw = totalIncomeWithdraw[pool];
            capitalWithdraw = epochWithdrawCurrency - totalIncomeWithdraw[pool];
            totalIncomeWithdraw[pool] = 0;
            return (incomeWithdraw, capitalWithdraw);
        }

        if (epochWithdrawCurrency < totalIncomeWithdraw[pool]) {
            epochs[pool][epochID].withdrawIncomeFulfillment =
                (epochWithdrawCurrency * ONE_HUNDRED_PERCENT) /
                totalIncomeWithdraw[pool];
            epochs[pool][epochID].withdrawCapitalFulfillment = 0;
            totalIncomeWithdraw[pool] -= epochWithdrawCurrency;
            return (epochWithdrawCurrency, 0);
        }
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
    function getWithdrawers(address pool) public view returns (address[] memory) {
        return withdrawers[pool];
    }

    function getOrder(address pool, address user) public view returns (UserOrder memory) {
        return orders[pool][user];
    }
}
