// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

abstract contract CreditOracleConsumerBase {
    error OnlyCoordinatorCanFulfill(address have, address want);

    address internal coordinator;

    function _fulfillCredit(uint256[] memory pubInputs, uint256 loan) internal virtual;

    function rawFulfillCredit(uint256[] memory pubInputs, uint256 loan) external {
        if (msg.sender != coordinator) {
            revert OnlyCoordinatorCanFulfill(msg.sender, coordinator);
        }
        _fulfillCredit(pubInputs, loan);
    }
}
