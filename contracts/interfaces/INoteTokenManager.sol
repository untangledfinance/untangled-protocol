// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;
interface INoteTokenManager {
    struct Epoch {
        uint256 withdrawCapitalFulfillment;
        uint256 withdrawIncomeFulfillment;
        uint256 investFulfillment;
        uint256 price;
    }

    struct UserOrder {
        uint256 orderedInEpoch;
        uint256 investCurrencyAmount;
        uint256 withdrawCurrencyAmount;
        uint256 withdrawIncomeCurrencyAmount;
    }

    struct NoteTokenInfor {
        address tokenAddress;
        address correspondingPool;
        uint256 minBidAmount;
    }

    event TokenMinted(address pool, address receiver, uint256 amount);
    event NewTokenAdded(address pool, address tokenAddress, uint256 timestamp);

    function setupNewToken(address pool, address tokenAddress, uint256 minBidAmount) external;

    function investOrder(address pool, uint256 newInvestAmount) external;

    function withdrawOrder(address pool, uint256 newWithdrawAmount) external;

    function calcDisburse(
        address pool,
        address user
    )
        external
        view
        returns (
            uint256 payoutCurrencyAmount,
            uint256 burnAmount,
            uint256 payoutTokenAmount,
            uint256 remainingInvestCurrency,
            uint256 remainingCapitalWithdrawToken,
            uint256 remainingIncomeWithdrawToken
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
            uint256 burnAmount,
            uint256 payoutTokenAmount,
            uint256 remainingInvestCurrency,
            uint256 remainingCapitalWithdrawToken,
            uint256 remainingIncomeWithdrawToken
        );

    function disburse(
        address pool,
        address user
    )
        external
        returns (
            uint256 payoutCurrencyAmount,
            uint256 burnAmount,
            uint256 payoutTokenAmount,
            uint256 remainingInvestCurrency,
            uint256 remainingCapitalWithdrawToken,
            uint256 remainingIncomeWithdrawToken
        );

    function disburse(
        address pool,
        address user,
        uint256 endEpoch
    )
        external
        returns (
            uint256 payoutCurrencyAmount,
            uint256 burnAmount,
            uint256 payoutTokenAmount,
            uint256 remainingInvestCurrency,
            uint256 remainingCapitalWithdrawToken,
            uint256 remainingIncomeWithdrawToken
        );

    function epochUpdate(
        address pool,
        uint256 epochID,
        uint256 investFulfillment_,
        uint256 withdrawFulfillment_,
        uint256 tokenPrice_,
        uint256 epochInvestOrderCurrency,
        uint256 epochWithdrawOrderCurrency
    ) external returns (uint256 capitalWithdraw, uint256 incomeWithdraw);

    function closeEpoch(
        address pool
    ) external returns (uint256 totalInvestCurrency_, uint256 totalWithdrawToken_, uint256 totalIncomeWithdrawToken_);
    function getTokenAddress(address pool) external view returns (address);

    function getTotalValueRaised(address pool) external view returns (uint256);
}
