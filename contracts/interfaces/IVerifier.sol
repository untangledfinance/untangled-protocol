// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IHalo2Verifier {
    function verifyProof(bytes calldata, uint256[] calldata) external view returns (bool);
}
