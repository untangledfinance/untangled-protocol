// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface ISecuritizationTranche {
    event RedeemSOTOrder(address usr, uint256 newRedeemAmount);
    event RedeemJOTOrder(address usr, uint256 newRedeemAmount);
    /// @notice redeemJOTOrder function can be used to place or revoke a redeem
    /// @param newRedeemAmount new amount of tokens to be redeemed
    function redeemJOTOrder(uint256 newRedeemAmount) external;

    /// @notice redeemSOTOrder function can be used to place or revoke a redeem
    /// @param newRedeemAmount new amount of tokens to be redeemed
    function redeemSOTOrder(uint256 newRedeemAmount) external;

    /// @notice Pause redeem request
    function setRedeemDisabled(bool _redeemDisabled) external;

    /// @notice Total amount of SOT redeem order
    function totalSOTRedeem() external view returns (uint256);
    /// @notice Total amount of JOT redeem order
    function totalJOTRedeem() external view returns (uint256);
    /// @dev Retrieves the amount of JOT tokens that can be redeemed for the specified user.
    /// @param usr The address of the user for which to retrieve the redeemable JOT amount.
    /// @return The amount of JOT tokens that can be redeemed by the user.
    function userRedeemJOTOrder(address usr) external view returns (uint256);
    function userRedeemSOTOrder(address usr) external view returns (uint256);
}
