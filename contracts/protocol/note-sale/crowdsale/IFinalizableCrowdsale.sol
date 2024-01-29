// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IFinalizableCrowdsale {
    event CrowdsaleFinalized();

    function finalized() external view returns (bool);

    function finalize(bool claimRemainToken, address remainTokenRecipient) external;
}
