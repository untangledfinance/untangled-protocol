// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;
interface INoteTokenManager {
    struct Epoch {
        uint256 withdrawFulfillment;
        uint256 investFullfillment;
        uint256 price;
    }

    struct UserOrder {
        uint256 orderedInEpoch;
        uint256 investCurrencyAmount;
        uint256 withdrawTokenAmount;
    }

    struct NoteTokenInfor {
        address tokenAddress;
        address correspondingPool;
        uint256 minBidAmount;
    }

    event TokenMinted(address pool, address receiver, uint256 amount);
    event NewTokenAdded(address pool, address tokenAddress, uint256 timestamp);

    function setupNewToken(address pool, address tokenAddress, uint256 minBidAmount) external;

    function investOrder(address pool, address user, uint256 newInvestAmount) external;

    function withdrawOrder(address pool, address user, uint256 newWithdrawAmount) external;

    function calcDisburse(
        address pool,
        address user
    )
        external
        view
        returns (
            uint256 payoutCurrencyAmount,
            uint256 payoutTokenAmount,
            uint256 remainingInvestCurrency,
            uint256 remainingWithdrawToken
        );

    function calcDisburse(
        address pool,
        address user,
        uint256 endEpoch
    )
        external
        view
        returns (
            uint256 payoutCurrencyAmount,
            uint256 payoutTokenAmount,
            uint256 remainingInvestCurrency,
            uint256 remainingWithdrawToken
        );

    function disburse(
        address pool,
        address user
    )
        external
        returns (
            uint256 payoutCurrencyAmount,
            uint256 payoutTokenAmount,
            uint256 remainingInvestCurrency,
            uint256 remainingWithdrawToken
        );

    function disburse(
        address pool,
        address user,
        uint256 endEpoch
    )
        external
        returns (
            uint256 payoutCurrencyAmount,
            uint256 payoutTokenAmount,
            uint256 remainingInvestCurrency,
            uint256 remainingWithdrawToken
        );

    function epochUpdate(
        address pool,
        uint256 epochID,
        uint256 investFulfillment_,
        uint256 withdrawFulfillment_,
        uint256 tokenPrice_,
        uint256 epochInvestOrderCurrency,
        uint256 epochWithdrawOrderCurrency
    ) external;

    function closeEpoch(address pool) external returns (uint256 totalInvestCurrency_, uint256 totalWithdrawToken_);
    function getTokenAddress(address pool) external view returns (address);
}
