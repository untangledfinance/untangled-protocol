pragma solidity 0.8.19;

import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import {INoteToken} from '../../interfaces/INoteToken.sol';
import {IPool} from '../../interfaces/IPool.sol';
import {ONE_HUNDRED_PERCENT, BACKEND_ADMIN_ROLE} from '../../libraries/DataTypes.sol';

contract NoteTokenVault is
    Initializable,
    PausableUpgradeable,
    AccessControlEnumerableUpgradeable,
    ReentrancyGuardUpgradeable
{
    struct Order {
        uint256 sotCurrencyAmount;
        uint256 jotCurrencyAmount;
        bool allSOTIncomeOnly;
        bool allJOTIncomeOnly;
    }

    struct ExecutionOrder {
        address user;
        uint256 sotIncomeClaimAmount;
        uint256 jotIncomeClaimAmount;
        uint256 sotCapitalClaimAmount;
        uint256 jotCapitalClaimAmount;
    }

    struct EpochInfor {
        uint256 sotPrice;
        uint256 jotPrice;
        uint256 timestamp;
        bool redeemDisabled;
        bool epochClosed;
    }

    struct FeeInfor {
        uint256 feePercentage;
        uint256 freeTimestamp;
    }
    // pool => user => order
    mapping(address => mapping(address => Order)) orders;
    // pool => epochInfor
    mapping(address => EpochInfor) epochInfor;
    // pool => fee
    mapping(address => FeeInfor) fees;

    event OrderCreated(address pool, address user);

    function initialize() public initializer {
        __Pausable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __AccessControlEnumerable_init_unchained();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function getEpochInfor(address pool) public view returns (EpochInfor memory) {
        return epochInfor[pool];
    }

    function redeemDisabled(address pool) public view returns (bool) {
        return epochInfor[pool].redeemDisabled;
    }

    function getOrder(address pool, address user) public view returns (Order memory) {
        return orders[pool][user];
    }
    /**
     * Set the parameter for fee calculation of a pool
     * @param pool pool address
     * @param _feePercentage the fee percentage that will be charge if user withdraw their capital before commitment period end
     * @param _freeTimestamp the timestamp where commitment period end
     */
    function setFeeInfor(
        address pool,
        uint256 _feePercentage,
        uint256 _freeTimestamp
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        fees[pool].feePercentage = _feePercentage;
        fees[pool].freeTimestamp = _freeTimestamp;
    }
    /**
     * Set pool's availability to redeem
     * @param pool pool address
     * @param _redeemDisabled pool's redeemability
     */
    function setPoolRedeemDisabled(address pool, bool _redeemDisabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        epochInfor[pool].redeemDisabled = _redeemDisabled;
    }

    /**
     * Create an order in currency amount
     * @param pool address of the pool
     * @param order the information of the withdraw order
     */
    function createOrder(address pool, Order calldata order) external {
        orders[pool][msg.sender] = order;
        emit OrderCreated(pool, msg.sender);
    }

    /**
     * Close the epoch and snapshot the NoteToken prices at that moment
     * @param pool address of corresponding pool
     */
    function closeEpoch(address pool) external onlyRole(BACKEND_ADMIN_ROLE) {
        require(epochInfor[pool].epochClosed == false, 'epoch already closed');
        (uint256 jotPrice, uint256 sotPrice) = IPool(pool).calcTokenPrices();
        epochInfor[pool].jotPrice = jotPrice;
        epochInfor[pool].sotPrice = sotPrice;
        epochInfor[pool].timestamp = block.timestamp;
        epochInfor[pool].epochClosed = true;
    }

    /**
     * Receive the information and execution the epoch
     * @param pool address of the target pool
     * @param executionOrders batch of execution orders
     */
    function executeOrders(
        address pool,
        ExecutionOrder[] calldata executionOrders
    ) external onlyRole(BACKEND_ADMIN_ROLE) {
        require(epochInfor[pool].epochClosed == true, "epoch haven't closed");
        address sotAddress = IPool(pool).sotToken();
        address jotAddress = IPool(pool).jotToken();
        uint256 totalIncomeWithdraw;
        uint256 totalCapitalWithdraw;
        uint256 totalSeniorWithdraw;
        for (uint256 i = 0; i < executionOrders.length; i++) {
            // validate the order and burn the required amount note token
            _validateAndBurn(
                pool,
                executionOrders[i].user,
                executionOrders[i].sotIncomeClaimAmount + executionOrders[i].sotCapitalClaimAmount, // total sot claimed
                executionOrders[i].jotIncomeClaimAmount + executionOrders[i].jotCapitalClaimAmount, // total jot claimed
                sotAddress,
                jotAddress
            );
            // update the state of the order
            _updateOrder(
                pool,
                executionOrders[i].user,
                executionOrders[i].sotIncomeClaimAmount + executionOrders[i].sotCapitalClaimAmount, // total sot claimed
                executionOrders[i].jotIncomeClaimAmount + executionOrders[i].jotCapitalClaimAmount // total jot claimed
            );

            uint256 capitalWithdraw = executionOrders[i].sotCapitalClaimAmount +
                executionOrders[i].jotCapitalClaimAmount;
            uint256 incomeWithdraw = executionOrders[i].sotIncomeClaimAmount + executionOrders[i].jotIncomeClaimAmount;
            uint256 seniorWithdraw = executionOrders[i].sotCapitalClaimAmount + executionOrders[i].sotIncomeClaimAmount;

            totalSeniorWithdraw += seniorWithdraw;
            totalIncomeWithdraw += incomeWithdraw;
            totalCapitalWithdraw += capitalWithdraw;
            // disburse currency token to user
            _disburse(pool, executionOrders[i].user, capitalWithdraw, incomeWithdraw);
        }
        // update reserve and senior asset
        IPool(pool).decreaseIncomeReserve(totalIncomeWithdraw);
        IPool(pool).decreaseCapitalReserve(totalCapitalWithdraw);
        IPool(pool).changeSeniorAsset(0, totalSeniorWithdraw);
        // check minFirstLoss
        require(IPool(pool).isMinFirstLossValid(), 'exceed minFirstLoss');

        // open epoch
        epochInfor[pool].epochClosed = false;
    }

    function _updateOrder(address pool, address user, uint256 sotCurrencyClaimed, uint256 jotCurrencyClaimed) internal {
        if (orders[pool][user].sotCurrencyAmount >= sotCurrencyClaimed) {
            orders[pool][user].sotCurrencyAmount -= sotCurrencyClaimed;
        }
        if (orders[pool][user].jotCurrencyAmount >= jotCurrencyClaimed) {
            orders[pool][user].jotCurrencyAmount -= jotCurrencyClaimed;
        }
    }

    function _validateAndBurn(
        address pool,
        address user,
        uint256 sotCurrencyClaimed,
        uint256 jotCurrencyClaimed,
        address sotAddress,
        address jotAddress
    ) internal {
        require(
            orders[pool][user].sotCurrencyAmount >= sotCurrencyClaimed || orders[pool][user].allSOTIncomeOnly,
            'sot claim amount bigger than ordered'
        );

        require(
            orders[pool][user].jotCurrencyAmount >= jotCurrencyClaimed || orders[pool][user].allJOTIncomeOnly,
            'jot claim amount bigger than ordered'
        );

        // burn note token
        uint256 sotBurn = sotCurrencyClaimed / epochInfor[pool].sotPrice;
        uint256 jotBurn = jotCurrencyClaimed / epochInfor[pool].jotPrice;

        require(
            INoteToken(sotAddress).allowance(user, address(this)) >= sotBurn &&
                INoteToken(jotAddress).allowance(user, address(this)) >= jotBurn,
            'not enough note token allowance'
        );

        if (sotBurn > 0) {
            INoteToken(sotAddress).transferFrom(user, address(this), sotBurn * (10 ** 18));
            INoteToken(sotAddress).burn(sotBurn);
        }
        if (jotBurn > 0) {
            INoteToken(jotAddress).transferFrom(user, address(this), jotBurn * (10 ** 18));
            INoteToken(jotAddress).burn(jotBurn);
        }
    }

    function _disburse(address pool, address receiver, uint256 capitalWithdraw, uint256 incomeWithdraw) internal {
        uint256 fee;
        if (block.timestamp < fees[pool].freeTimestamp) {
            fee = (capitalWithdraw * fees[pool].feePercentage) / ONE_HUNDRED_PERCENT;
        }

        IPool(pool).disburse(receiver, (capitalWithdraw + incomeWithdraw - fee));
    }
}
