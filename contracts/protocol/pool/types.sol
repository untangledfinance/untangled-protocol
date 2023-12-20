// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

bytes32 constant OWNER_ROLE = keccak256('OWNER_ROLE');
bytes32 constant POOL_ADMIN = keccak256('POOL_CREATOR');
bytes32 constant ORIGINATOR_ROLE = keccak256('ORIGINATOR_ROLE');

bytes32 constant BACKEND_ADMIN = keccak256('BACKEND_ADMIN');
bytes32 constant SIGNER_ROLE = keccak256('SIGNER_ROLE');

// In PoolNAV we use this
bytes32 constant POOL = keccak256('POOL');

uint256 constant RATE_SCALING_FACTOR = 10 ** 4;
