// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IInterestRate {
    function pickedInterest() external view returns (uint32);
}
