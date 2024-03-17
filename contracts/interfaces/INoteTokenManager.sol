// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;
interface INoteTokenManager {
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
}
