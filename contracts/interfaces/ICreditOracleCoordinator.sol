// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.19;

interface ICreditOracleCoordinator {
    function fulfillProof(uint256 batchSize,bytes calldata proof, uint256[] calldata pubInputs, bytes calldata data) external;
    function registerPool(bytes32 _modelerKey) external;
    function forCaseExcessCLLimitation(uint256 batchSize, bytes calldata proof, uint256[] calldata pubInputs, bytes calldata data) external;
}


