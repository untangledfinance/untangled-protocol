pragma solidity 0.8.19;

interface ICredioAdapter {
    function requestUpdate(bytes32 loanId) external returns (uint256);

    function requestBatchUpdate(bytes32[] memory loanIds) external returns (uint256[] memory);
}
