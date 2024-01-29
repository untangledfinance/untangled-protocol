const { keccak256 } = require('@ethersproject/keccak256');
const { pack } = require('@ethersproject/solidity');
const { arrayify, BytesLike } = require('@ethersproject/bytes');
const presignedUidMessage = (fromAddress, extraTypes, extraValues, uniqueIdentityAddress, nonce, chainId) => {
    if (extraTypes.length !== extraValues.length) {
        throw new Error('Length of extraTypes and extraValues must match');
    }

    const types = ['address', ...extraTypes, 'address', 'uint256', 'uint256'];
    const values = [fromAddress, ...extraValues, uniqueIdentityAddress, nonce, chainId];

    const encoded = pack(types, values);
    const hash = keccak256(encoded);
    // Cf. https://github.com/ethers-io/ethers.js/blob/ce8f1e4015c0f27bf178238770b1325136e3351a/docs/v5/api/signer/README.md#note
    return arrayify(hash);
};
/**
 * @param fromAddress - The address of the msgSender for a mint or the tokenHolder for a burn
 * @param tokenId - ID of the UID to be operated on
 * @param expiresAt - Timestamp for signature expiry
 * @param nonce  - The uint256 nonce associated with the approved msg.sender for the mint, or the token holder for a burn.
 * @param chainId - The ID of the chain the UID will be burned/minted on
 * @description - Generates the arrayified hash of the parameters for a mint/burn signature - should be signed by an address with the UNIQUE_IDENTITY_SIGNER role to be valid. Equivalent functionality to presignedBurnMessage.
 * @returns {BytesLike} - The arrayified hash of the signature input elements
 */
module.exports.presignedMintMessage = (fromAddress, tokenId, expiresAt, uniqueIdentityAddress, nonce, chainId) => {
    const extraTypes = ['uint256', 'uint256'];
    const extraValues = [tokenId, expiresAt];
    return presignedUidMessage(fromAddress, extraTypes, extraValues, uniqueIdentityAddress, nonce, chainId);
};

module.exports.presignedCancelRedeemOrderMessage = (
    fromAddress,
    poolAddress,
    noteTokenAddress,
    maxTimestamp,
    nonce,
    chainId
) => {
    const types = ['address', 'address', 'address', 'uint256', 'uint256', 'uint256'];
    const values = [fromAddress, poolAddress, noteTokenAddress, maxTimestamp, nonce, chainId];

    const encoded = pack(types, values);
    const hash = keccak256(encoded);
    // Cf. https://github.com/ethers-io/ethers.js/blob/ce8f1e4015c0f27bf178238770b1325136e3351a/docs/v5/api/signer/README.md#note
    return arrayify(hash);
};

module.exports.presignedRedeemOrderMessage = (
    fromAddress,
    poolAddress,
    noteTokenAddress,
    noteTokenRedeemAmount,
    chainId
) => {
    const types = ['address', 'address', 'address', 'uint256', 'uint256'];
    const values = [fromAddress, poolAddress, noteTokenAddress, noteTokenRedeemAmount, chainId];

    const encoded = pack(types, values);
    const hash = keccak256(encoded);
    return arrayify(hash);
};
