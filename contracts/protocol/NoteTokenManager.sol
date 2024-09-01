pragma solidity 0.8.19;
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts/interfaces/IERC20.sol';

import '../interfaces/INoteTokenManager.sol';
import '../interfaces/IPool.sol';
import '../interfaces/INoteToken.sol';
import '../interfaces/IEpochExecutor.sol';
import '../libraries/ConfigHelper.sol';

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
    // pool => totalWithdraw
    mapping(address => uint256) public totalWithdraw;
    // pool => totalInvest
    mapping(address => uint256) public totalInvest;
    // pool => totalValueRaised
    mapping(address => uint256) public totalValueRaised;
    // pool => noteTokenInfor
    mapping(address => NoteTokenInfor) public tokenInfor;
    // pool => epochId => epoch
    mapping(address => mapping(uint256 => Epoch)) public epochs;
    // pool => user => orders
    mapping(address => mapping(address => UserOrder)) orders;

    mapping(address => bool) public waitingForUpdate;

    uint256[] allowedUIDTypes;

    IEpochExecutor public epochExecutor;

    modifier onlyEpochExecutor() {
        _onlyEpochExecutor();
        _;
    }

    function _onlyEpochExecutor() internal view {
        require(msg.sender == address(epochExecutor), 'only epoch executor');
    }

    function initialize(Registry registry_, uint256[] memory allowedUIDs) public initializer {
        __Pausable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __AccessControlEnumerable_init_unchained();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        registry = registry_;
        allowedUIDTypes = allowedUIDs;
    }

    function getAllowedUIDTypes() public view returns (uint256[] memory) {
        return allowedUIDTypes;
    }

    function setAllowedUIDTypes(uint256[] memory newAllowedUIDs) public onlyRole(DEFAULT_ADMIN_ROLE) {
        allowedUIDTypes = newAllowedUIDs;
    }

    function hasValidUID(address sender) public view returns (bool) {
        return registry.getGo().goOnlyIdTypes(sender, allowedUIDTypes);
    }

    function setUpEpochExecutor() public {
        require(address(registry.getEpochExecutor()) != address(0), 'no epoch executor found');
        epochExecutor = registry.getEpochExecutor();
    }

    function setupNewToken(address pool, address tokenAddress, uint256 minBidAmount) external {
        tokenInfor[pool].tokenAddress = tokenAddress;
        tokenInfor[pool].minBidAmount = minBidAmount;
        emit NewTokenAdded(pool, tokenAddress, block.timestamp);
    }

    // only KYCed users
    function investOrder(address pool, uint256 investAmount) public {
        require(hasValidUID(msg.sender), 'NoteTokenManager: invalid UID');
        require(tokenInfor[pool].tokenAddress != address(0), 'NoteTokenManager: No note token found');
        require(investAmount >= tokenInfor[pool].minBidAmount, 'NoteTokenManager: invest amount is too low');
        orders[pool][msg.sender].orderedInEpoch = epochExecutor.currentEpoch(pool);
        uint256 currentInvestAmount = orders[pool][msg.sender].investAmount;
        orders[pool][msg.sender].investAmount = investAmount;
        totalInvest[pool] = totalInvest[pool] - currentInvestAmount + investAmount;
        if (investAmount > currentInvestAmount) {
            require(
                IERC20(IPool(pool).underlyingCurrency()).transferFrom(
                    msg.sender,
                    IPool(pool).pot(),
                    investAmount - currentInvestAmount
                ),
                'NoteTokenManager: currency transfer failed'
            );
            return;
        } else if (investAmount < currentInvestAmount) {
            IPool(pool).disburse(msg.sender, currentInvestAmount - investAmount);
        }
        emit InvestOrder(pool, msg.sender, investAmount);
    }

    // only KYCed users
    function withdrawOrder(address pool, uint256 withdrawAmount) public {
        require(withdrawAmount >= 0, 'NoteTokenManager: invalid withdraw amount');
        address tokenAddress = tokenInfor[pool].tokenAddress;
        require(tokenAddress != address(0), 'NoteTokenManager: No note token found');
        require(
            INoteToken(tokenAddress).balanceOf(msg.sender) >= withdrawAmount,
            'NoteTokenManager: Insufficient balance'
        );
        orders[pool][msg.sender].orderedInEpoch = epochExecutor.currentEpoch(pool);
        totalWithdraw[pool] = totalWithdraw[pool] + withdrawAmount - orders[pool][msg.sender].withdrawAmount;
        orders[pool][msg.sender].withdrawAmount = withdrawAmount;
        emit WithdrawOrder(pool, msg.sender, withdrawAmount);
    }

    function claimIncome(address pool) public {
        address noteTokenAddress = tokenInfor[pool].tokenAddress;
        uint256 amount = INoteToken(noteTokenAddress).calcUserIncome(msg.sender);
        INoteToken(noteTokenAddress).claimIncome(msg.sender);
        IPool(pool).disburse(msg.sender, amount);
    }

    function calcDisburse(
        address pool,
        address user
    )
        public
        view
        returns (uint256 fulfilledInvest, uint256 fulfilledWithdraw, uint256 remainingInvest, uint256 remainingWithdraw)
    {
        uint256 endEpoch = epochExecutor.lastEpochExecuted(pool);
        // no disburse possible in epoch
        if (orders[pool][user].orderedInEpoch == epochExecutor.currentEpoch(pool)) {
            return (
                fulfilledInvest,
                fulfilledWithdraw,
                orders[pool][user].investAmount,
                orders[pool][user].withdrawAmount
            );
        }

        uint256 epochIdx = orders[pool][user].orderedInEpoch;

        remainingInvest = orders[pool][user].investAmount;
        remainingWithdraw = orders[pool][user].withdrawAmount;
        uint256 amount = 0;

        while (epochIdx <= endEpoch && (remainingInvest > 0 || remainingWithdraw > 0)) {
            if (remainingInvest != 0) {
                amount = (remainingInvest * epochs[pool][epochIdx].investFulfillment) / ONE_HUNDRED_PERCENT;
                fulfilledInvest += amount;
                remainingInvest -= amount;
            }
            if (remainingWithdraw != 0) {
                amount = (remainingWithdraw * epochs[pool][epochIdx].withdrawFulfillment) / ONE_HUNDRED_PERCENT;
                fulfilledWithdraw += amount;
                remainingWithdraw -= amount;
            }
            epochIdx = epochIdx + 1;
        }
        return (fulfilledInvest, fulfilledWithdraw, remainingInvest, remainingWithdraw);
    }

    function disburse(
        address pool,
        address user
    )
        public
        returns (uint256 fulfilledInvest, uint256 fulfilledWithdraw, uint256 remainingInvest, uint256 remainingWithdraw)
    {
        require(
            orders[pool][user].orderedInEpoch >= epochExecutor.lastEpochExecuted(pool),
            'NoteTokenManager: epoch not executed yet'
        );
        uint256 lastEpochExecuted = epochExecutor.lastEpochExecuted(pool);

        (fulfilledInvest, fulfilledWithdraw, remainingInvest, remainingWithdraw) = calcDisburse(pool, user);
        orders[pool][user].investAmount = remainingInvest;
        orders[pool][user].withdrawAmount = remainingWithdraw;

        orders[pool][user].orderedInEpoch = lastEpochExecuted + 1;

        if (fulfilledWithdraw > 0) {
            (uint256 feePercentage, uint256 exitTimestamp) = IPool(pool).getEarlyExitInfor();
            address beneficiary = IPool(pool).getBeneficiary();
            uint256 feeAmount;
            if (block.timestamp <= exitTimestamp) {
                feeAmount = (fulfilledWithdraw * feePercentage) / ONE_HUNDRED_PERCENT;
            }
            if (feeAmount > 0) {
                IPool(pool).disburse(beneficiary, feeAmount);
            }
            IPool(pool).disburse(user, fulfilledWithdraw - feeAmount);
            INoteToken(tokenInfor[pool].tokenAddress).redeem(user, fulfilledWithdraw);
        }

        if (fulfilledInvest > 0) {
            INoteToken(tokenInfor[pool].tokenAddress).mint(user, fulfilledInvest);
        }

        return (fulfilledInvest, fulfilledWithdraw, remainingInvest, remainingWithdraw);
    }

    function closeEpoch(address pool) public onlyEpochExecutor returns (uint256 totalInvest_, uint256 totalWithdraw_) {
        require(waitingForUpdate[pool] == false, 'NoteTokenManager: pool is closed');
        waitingForUpdate[pool] = true;
        return (totalInvest[pool], totalWithdraw[pool]);
    }

    // only EpochExecutor
    function epochUpdate(
        address pool,
        uint256 epochID,
        uint256 investFulfillment_,
        uint256 withdrawFulfillment_,
        uint256 tokenPrice_,
        uint256 epochTotalInvest,
        uint256 epochTotalWithdraw
    ) public onlyEpochExecutor {
        require(waitingForUpdate[pool] == true, 'NoteTokenManager: epoch is not closed yet.');
        waitingForUpdate[pool] = false;
        epochs[pool][epochID].investFulfillment = investFulfillment_;
        epochs[pool][epochID].withdrawFulfillment = withdrawFulfillment_;
        epochs[pool][epochID].price = tokenPrice_;

        uint256 epochFulfilledInvest = (epochTotalInvest * investFulfillment_) / ONE_HUNDRED_PERCENT;
        uint256 epochFulfilledWithdraw = (epochTotalWithdraw * withdrawFulfillment_) / ONE_HUNDRED_PERCENT;

        if (epochFulfilledInvest > epochFulfilledWithdraw) {
            totalValueRaised[pool] += epochFulfilledInvest - epochFulfilledWithdraw;
        }

        if (epochFulfilledInvest < epochFulfilledWithdraw) {
            totalValueRaised[pool] -= epochFulfilledWithdraw - epochFulfilledInvest;
        }

        totalInvest[pool] -= epochFulfilledInvest;
        totalWithdraw[pool] -= epochFulfilledWithdraw;
    }

    function getTokenAddress(address pool) public view returns (address) {
        return tokenInfor[pool].tokenAddress;
    }

    function getTotalValueRaised(address pool) public view returns (uint256) {
        return totalValueRaised[pool];
    }

    function getOrder(address pool, address user) public view returns (UserOrder memory) {
        return orders[pool][user];
    }

    function getInvestAmount(address pool, address user) public view returns (uint256) {
        return orders[pool][user].investAmount;
    }

    function getWithdrawAmount(address pool, address user) public view returns (uint256) {
        return orders[pool][user].withdrawAmount;
    }
}
