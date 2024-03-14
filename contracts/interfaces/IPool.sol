//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import {DataTypes} from '../libraries/DataTypes.sol';
import {Configuration} from '../libraries/Configuration.sol';

interface IPool {
    function calcJuniorRatio() external view returns (uint256 juniorRatio);

    function calcTokenPrices() external view returns (uint256 juniorTokenPrice, uint256 seniorTokenPrice);

    function changeSeniorAsset(uint256 _seniorSupply, uint256 _seniorRedeem) external;

    function getLoansValue(
        uint256[] memory tokenIds,
        DataTypes.LoanEntry[] memory loanEntries
    ) external view returns (uint256 expectedAssetsValue, uint256[] memory expectedAssetValues);

    function collectAssets(
        uint256[] memory tokenIds,
        DataTypes.LoanEntry[] memory loanEntries
    ) external returns (uint256);

    function collectERC20Asset(address tokenAddresss) external;

    function currentNAV() external view returns (uint256 nav_);

    function currentNAVAsset(bytes32 tokenId) external view returns (uint256);

    function debt(uint256 loan) external view returns (uint256 loanDebt);

    function debtCeiling() external view returns (uint256);

    function disburse(address usr, uint256 currencyAmount) external;

    function getAsset(bytes32 agreementId) external view returns (DataTypes.NFTDetails memory);

    function getTokenAssetAddresses() external view returns (address[] memory);

    function getTokenAssetAddressesLength() external view returns (uint256);

    function increaseCapitalReserve(uint256 currencyAmount) external;

    function injectTGEAddress(address _tgeAddress, Configuration.NOTE_TOKEN_TYPE) external;

    function interestRateSOT() external view returns (uint256);

    function isDebtCeilingValid() external view returns (bool);

    function isMinFirstLossValid() external view returns (bool);

    function jotToken() external view returns (address);

    function minFirstLossCushion() external view returns (uint32);

    function openingBlockTimestamp() external view returns (uint64);

    function pot() external view returns (address);

    function rebase() external;

    function repayLoan(
        uint256[] calldata loans,
        uint256[] calldata amounts
    ) external returns (uint256[] memory, uint256[] memory);

    function reserve() external view returns (uint256);

    function risk(bytes32 nft_) external view returns (uint256 risk_);

    function riskScores(uint256 index) external view returns (DataTypes.RiskScore memory);

    function secondTGEAddress() external view returns (address);

    function seniorDebtAndBalance() external view returns (uint256, uint256);

    function setDebtCeiling(uint256 _debtCeiling) external;

    function setInterestRateSOT(uint32 _newRate) external;

    function setMinFirstLossCushion(uint32 _minFirstLossCushion) external;

    function setUpOpeningBlockTimestamp() external;

    function sotToken() external view returns (address);

    function tgeAddress() external view returns (address);

    function tokenAssetAddresses(uint256 idx) external view returns (address);

    function totalAssetRepaidCurrency() external view returns (uint256);

    function underlyingCurrency() external view returns (address);

    function validatorRequired() external view returns (bool);

    function withdraw(address to, uint256 amount) external;

    function withdrawAssets(
        address[] memory tokenAddresses,
        uint256[] memory tokenIds,
        address[] memory recipients
    ) external;

    function withdrawERC20Assets(
        address[] memory tokenAddresses,
        address[] memory recipients,
        uint256[] memory amounts
    ) external;
}
