// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

struct LoanAssetInfo {
    uint256[] tokenIds;
    uint256[] nonces;
    address validator;
    bytes validateSignature;
}

bytes32 constant VALIDATOR_ROLE = keccak256('VALIDATOR_ROLE');
bytes32 constant VALIDATOR_ADMIN_ROLE = keccak256('VALIDATOR_ADMIN_ROLE');
