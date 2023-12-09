// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '../../storage/Registry.sol';
import './ISecuritizationPool.sol';

interface ISecuritizationManager {
    event NewTGECreated(address indexed instanceAddress);
    event NewNotesTokenCreated(address indexed instanceAddress);
    event NewPoolCreated(address indexed instanceAddress);
    event UpdatePotToPool(address indexed pot, address indexed pool);
    event SotDeployed(address indexed sotAddress, address tgeAddress, address poolAddress);
    event JotDeployed(address indexed jotAddress, address tgeAddress, address poolAddress);

    function registry() external view returns (Registry);

    function isExistingPools(address pool) external view returns (bool);

    function pools(uint256 idx) external view returns (address);

    function potToPool(address pot) external view returns (address);

    function isExistingTGEs(address tge) external view returns (bool);

    /// @dev Register pot to pool instance
    /// @param pot Pool linked wallet
    function registerPot(address pot) external;
}
