// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface ISecuritizationPoolLike {
    function original() external view returns (address);
}

/**
 * @title Untangled's ISecuritizationPoolExtension interface
 * @notice Interface for the securitization pool extension contract
 * @author Untangled Team
 */
interface ISecuritizationPoolExtension {
    function installExtension(bytes memory params) external;

    function getFunctionSignatures() external view returns (bytes4[] memory);
}

abstract contract SecuritizationPoolExtension is ISecuritizationPoolExtension {
    modifier onlyCallInTargetPool() {
        ISecuritizationPoolLike current = ISecuritizationPoolLike(address(this));
        // current contract is not poolImpl, => delegate call
        require(current.original() != address(this), 'Only call in target pool');
        _;
    }
}
