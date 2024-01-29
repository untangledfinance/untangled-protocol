// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

bytes32 constant OWNER_ROLE = keccak256('OWNER_ROLE');
bytes32 constant POOL_ADMIN = keccak256('POOL_CREATOR');
bytes32 constant ORIGINATOR_ROLE = keccak256('ORIGINATOR_ROLE');

bytes32 constant BACKEND_ADMIN = keccak256('BACKEND_ADMIN');
bytes32 constant SIGNER_ROLE = keccak256('SIGNER_ROLE');

// In PoolNAV we use this
bytes32 constant POOL = keccak256('POOL');

uint256 constant RATE_SCALING_FACTOR = 10 ** 4;

uint256 constant ONE_HUNDRED_PERCENT = 100 * RATE_SCALING_FACTOR;

uint256 constant ONE = 10 ** 27;
uint256 constant WRITEOFF_RATE_GROUP_START = 1000 * ONE;
