// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import './auth.sol';
import {Discounting} from './discounting.sol';

interface IPoolNAV {
    event Rely(address indexed usr);
    function addLoan(uint256 loan) external returns (uint256);

    function repayLoan(uint256 loan, uint256 amount) external returns (uint256);

    function file(bytes32 name, uint256 value) external;

    function file(
        bytes32 name,
        uint256 rate_,
        uint256 writeOffPercentage_,
        uint256 overdueDays_,
        uint256 penaltyRate_,
        uint256 riskIndex
    ) external;

    function debt(uint256 loan) external view returns (uint256 loanDebt);

    /// @notice calculates and returns the current NAV
    /// @return nav_ current NAV
    function currentNAV() external view returns (uint256 nav_);

    function currentNAVAsset(bytes32 tokenId) external view returns (uint256);

    function futureValue(bytes32 nft_) external view returns (uint256);

    function maturityDate(bytes32 nft_) external view returns (uint256);

    function discountRate() external view returns (uint256);
}
