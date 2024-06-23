// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface INoteTokenManager {
    struct Epoch {
        uint256 withdrawFulfillment;
        uint256 investFulfillment;
        uint256 price;
    }

    struct UserOrder {
        uint256 orderedInEpoch;
        uint256 investAmount;
        uint256 withdrawAmount;
    }

    struct NoteTokenInfor {
        address tokenAddress;
        address correspondingPool;
        uint256 minBidAmount;
    }

    event TokenMinted(address pool, address receiver, uint256 amount);
    event NewTokenAdded(address pool, address tokenAddress, uint256 timestamp);

    function setupNewToken(address pool, address tokenAddress, uint256 minBidAmount) external;

    function hasValidUID(address sender) external view returns (bool);

    function investOrder(address pool, uint256 investAmount) external;

    function withdrawOrder(address pool, uint256 withdrawAmount) external;

    function calcDisburse(
        address pool,
        address user
    )
        external
        view
        returns (
            uint256 fulfilledInvest,
            uint256 fulfilledWithdraw,
            uint256 remainingInvest,
            uint256 remainingWithdraw
        );

    function disburse(
        address pool,
        address user
    )
        external
        returns (
            uint256 fulfilledInvest,
            uint256 fulfilledWithdraw,
            uint256 remainingInvest,
            uint256 remainingWithdraw
        );

    function closeEpoch(address pool) external returns (uint256 totalInvest_, uint256 totalWithdraw_);

    function epochUpdate(
        address pool,
        uint256 epochID,
        uint256 investFulfillment_,
        uint256 withdrawFulfillment_,
        uint256 tokenPrice_,
        uint256 epochTotalInvest,
        uint256 epochTotalWithdraw
    ) external;

    function getTotalValueRaised(address pool) external view returns (uint256);

    function getTokenAddress(address pool) external view returns (address);
}
