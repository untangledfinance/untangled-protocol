// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// https://eips.ethereum.org/EIPS/eip-5008
/// @dev the ERC-165 identifier for this interface is 0xce03fdab.
/* is IERC165 */ interface IERC5008 {
    /// @notice Emitted when the `nonce` of an NFT is changed
    event NonceChanged(uint256 tokenId, uint256 nonce);

    /// @notice Get the nonce of an NFT
    /// Throws if `tokenId` is not a valid NFT
    /// @param tokenId The id of the NFT
    /// @return The nonce of the NFT
    function nonce(uint256 tokenId) external view returns (uint256);
}
