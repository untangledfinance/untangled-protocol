// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface INoteTokenVault {
    event RedeemOrder(
        address pool,
        address noteTokenAddress,
        address usr,
        uint256 noteTokenRedeemAmount,
        uint256 noteTokenPrice
    );
    event CancelOrder(address pool, address noteTokenAddress, address usr, uint256 noteTokenRedeemAmount);
    event PreDistribute(
        address pool,
        uint256 totalCurrencyAmount,
        address[] noteTokenAddresses,
        uint256[] totalRedeemedNoteAmounts
    );
    event DisburseOrder(
        address pool,
        address noteTokenAddress,
        address[] toAddresses,
        uint256[] amounts,
        uint256[] redeemedAmount
    );
    event SetRedeemDisabled(address pool, bool _redeemDisabled);

    /// @title UserOrder
    /// @dev Represents a user's order containing the amount of SOT and JOT to redeem.
    struct UserOrder {
        uint256 redeemSOTAmount;
        uint256 redeemJOTAmount;
    }

    struct RedeemOrderParam {
        address pool;
        address noteTokenAddress;
        uint256 noteTokenRedeemAmount;
    }

    struct CancelOrderParam {
        address pool;
        address noteTokenAddress;
        uint256 maxTimestamp;
    }

    /// @notice redeemJOTOrder function can be used to place or revoke a redeem
    function redeemOrder(RedeemOrderParam calldata redeemParam, bytes calldata signature) external;

    /// @dev Disburses funds and handles JOT redemptions for a pool.
    /// @param pool The address of the pool contract.
    /// @param toAddresses An array of recipient addresses.
    /// @param currencyAmounts An array of amounts to disburse to each recipient.
    /// @param redeemedNoteAmounts An array of JOT amounts redeemed by each recipient.
    /// @notice Only accessible by BACKEND_ADMIN role.
    function disburseAll(
        address pool,
        address noteTokenAddress,
        address[] memory toAddresses,
        uint256[] memory currencyAmounts,
        uint256[] memory redeemedNoteAmounts
    ) external;

    function cancelOrder(CancelOrderParam memory cancelParam, bytes calldata signature) external;

    /// @notice Pause redeem request
    function setRedeemDisabled(address pool, bool _redeemDisabled) external;

    /// @notice Total amount of SOT redeem order
    function totalSOTRedeem(address pool) external view returns (uint256);

    /// @notice Get redeem disabled
    function redeemDisabled(address pool) external view returns (bool);

    /// @notice Total amount of JOT redeem order
    function totalJOTRedeem(address pool) external view returns (uint256);

    /// @dev Retrieves the amount of JOT tokens that can be redeemed for the specified user.
    /// @param usr The address of the user for which to retrieve the redeemable JOT amount.
    /// @return The amount of JOT tokens that can be redeemed by the user.
    function userRedeemJOTOrder(address pool, address usr) external view returns (uint256);

    function userRedeemSOTOrder(address pool, address usr) external view returns (uint256);
}
