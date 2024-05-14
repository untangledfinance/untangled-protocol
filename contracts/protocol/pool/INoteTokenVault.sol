pragma solidity 0.8.19;

contract INoteTokenVault {
    struct Order {
        uint256 sotCurrencyAmount;
        uint256 jotCurrencyAmount;
        bool allSOTIncomeOnly;
        bool allJOTIncomeOnly;
    }

    struct OrderExecution {
        address user;
        uint256 sotIncomeClaimAmount;
        uint256 jotIncomeClaimAmount;
        uint256 sotCapitalClaimAmount;
        uint256 jotCapitalClaimAmount;
    }

    struct EpochInfor {
        uint256 sotPrices;
        uint256 jotPrices;
        uint256 timestamp;
        bool redeemDisable;
        bool epochClosed;
    }
    // pool => user => order
    mapping(address => mapping(address => Order)) orders;
    // pool => epochInfor
    mapping(address => EpochInfor) epochInfor;

    /**
     * Create an order in currency amount
     * @param pool address of the pool
     * @param order the information of the withdraw order
     */
    function createOrders(address pool, Order calldata order) public {}

    /**
     * Close the epoch and snapshot the NoteToken prices at that moment
     * @param pool address of corresponding pool
     */
    function closeEpoch(address pool) public {}

    /**
     * Update the amount of currency that a user will receive in this epoch
     * @param pool address of the pool
     * @param orderExecution the result of the income and capital withdraw of a user
     */
    function executeOrders(address pool, OrderExecution calldata orderExecution) public {}

    function batchExecuteOrders(OrderExecution[] calldata executionBatch) public {}

    function batchClaim(address[] calldata users) public {}
}
