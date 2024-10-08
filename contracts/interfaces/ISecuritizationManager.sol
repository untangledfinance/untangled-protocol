// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import '../storage/Registry.sol';
import './IPool.sol';
import {DataTypes} from '../libraries/DataTypes.sol';

interface ISecuritizationManager {
    event NewPoolCreated(address indexed instanceAddress);
    event NewPoolDeployed(address indexed instanceAddress, address poolOwner, DataTypes.NewPoolParams newPoolParams);
    event UpdatePotToPool(address indexed pot, address indexed pool);
    event SotDeployed(address indexed sotAddress, address tgeAddress, address poolAddress);
    event JotDeployed(address indexed jotAddress, address tgeAddress, address poolAddress);

    event SetupSot(address indexed sotAddress, address tgeAddress, TGEParam tgeParam, uint256 interestRate);
    event SetupJot(address indexed jotAddress, address tgeAddress, TGEParam tgeParam, uint256 initialJOTAmount);

    event UpdateAllowedUIDTypes(uint256[] uids);
    event TokensPurchased(address indexed investor, address indexed tgeAddress, uint256 amount, uint256 tokenAmount);
    event NoteTokenPurchased(
        address indexed investor,
        address indexed tgeAddress,
        address poolAddress,
        uint256 amount,
        uint256 tokenAmount
    );

    event UpdateTGEInfo(TGEInfoParam[] tgeInfos);

    struct TGEParam {
        address issuerTokenController;
        address pool;
        uint256 minBidAmount;
        uint256 totalCap;
        uint256 openingTime;
        string ticker;
        uint8 saleType;
    }

    struct TGEInfoParam {
        address tgeAddress;
        uint256 totalCap;
        uint256 minBidAmount;
    }

    function registry() external view returns (Registry);

    function isExistingPools(address pool) external view returns (bool);

    function pools(uint256 idx) external view returns (address);

    function potToPool(address pot) external view returns (address);

    function isExistingTGEs(address tge) external view returns (bool);

    function hasAllowedUID(address sender) external view returns (bool);

    /// @dev Register pot to pool instance
    /// @param pot Pool linked wallet
    function registerPot(address pot) external;
}
