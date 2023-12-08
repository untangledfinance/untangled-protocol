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

    function setRedeemDisabled(bool _redeemDisabled) external;

    function totalSOTRedeem() external view returns (uint256);
    function totalJOTRedeem() external view returns (uint256);
    function userRedeemJOTOrder(address usr) external view returns (uint256);
    function userRedeemSOTOrder(address usr) external view returns (uint256);
}
