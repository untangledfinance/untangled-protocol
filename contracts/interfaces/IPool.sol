//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import {DataTypes} from '../libraries/DataTypes.sol';

interface IPool {
    function BACKEND_ADMIN() external view returns (bytes32);
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function ORIGINATOR_ROLE() external view returns (bytes32);
    function OWNER_ROLE() external view returns (bytes32);
    function POOL_ADMIN_ROLE() external view returns (bytes32);
    function SIGNER_ROLE() external view returns (bytes32);
    function SUPER_ADMIN() external view returns (bytes32);
    function claimCashRemain(address recipientWallet) external;
    function collectAssets(
        uint256[] memory tokenIds,
        DataTypes.LoanEntry[] memory loanEntries
    ) external returns (uint256);
    function collectERC20Asset(address tokenAddresss) external;
    function currentNAV() external view returns (uint256 nav_);
    function currentNAVAsset(bytes32 tokenId) external view returns (uint256);
    function debt(uint256 loan) external view returns (uint256 loanDebt);
    function debtCeiling() external view returns (uint256);
    function decreaseReserve(uint256 currencyAmount) external;
    function disburse(address usr, uint256 currencyAmount) external;
    function discountRate() external view returns (uint256);
    function exportAssets(address tokenAddress, address toPoolAddress, uint256[] memory tokenIds) external;
    function futureValue(bytes32 nft_) external view returns (uint256);
    function getAsset(bytes32 agreementId) external view returns (DataTypes.NFTDetails memory);
    function getInitializedVersion() external view returns (uint256);
    function getNFTAssetsLength() external view returns (uint256);
    function getRiskScoresLength() external view returns (uint256);
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
    function getRoleMemberCount(bytes32 role) external view returns (uint256);
    function getTokenAssetAddresses() external view returns (address[] memory);
    function getTokenAssetAddressesLength() external view returns (uint256);
    function grantRole(bytes32 role, address account) external;
    function hasFinishedRedemption() external view returns (bool);
    function hasRole(bytes32 role, address account) external view returns (bool);
    function increaseReserve(uint256 currencyAmount) external;
    function increaseTotalAssetRepaidCurrency(uint256 amount) external;
    function initialize(address _registryAddress, bytes memory params) external;
    function injectTGEAddress(address _tgeAddress, uint8 _noteToken) external;
    function interestRateSOT() external view returns (uint32);
    function isAdmin() external view returns (bool);
    function isDebtCeilingValid() external view returns (bool);
    function jotToken() external view returns (address);
    function maturityDate(bytes32 nft_) external view returns (uint256);
    function minFirstLossCushion() external view returns (uint32);
    function nftAssets(uint256 idx) external view returns (DataTypes.NFTAsset memory);
    function onERC721Received(address, address, uint256 tokenId, bytes memory) external returns (bytes4);
    function openingBlockTimestamp() external view returns (uint64);
    function paidPrincipalAmountSOT() external view returns (uint256);
    function paidPrincipalAmountSOTByInvestor(address user) external view returns (uint256);
    function pause() external;
    function paused() external view returns (bool);
    function pot() external view returns (address);
    function registry() external view returns (address);
    function renounceRole(bytes32 role, address account) external;
    function repayLoan(uint256[] calldata loans, uint256[] calldata amounts) external returns (uint256[] memory, uint256[] memory);
    function reserve() external view returns (uint256);
    function revokeRole(bytes32 role, address account) external;
    function risk(bytes32 nft_) external view returns (uint256 risk_);
    function riskScores(uint256 index) external view returns (DataTypes.RiskScore memory);
    function secondTGEAddress() external view returns (address);
    function setDebtCeiling(uint256 _debtCeiling) external;
    function setMinFirstLossCushion(uint32 _minFirstLossCushion) external;
    function setPot(address _pot) external;
    function setRoleAdmin(bytes32 role, bytes32 adminRole) external;
    function setUpOpeningBlockTimestamp() external;
    function setupRiskScores(
        uint32[] memory _daysPastDues,
        uint32[] memory _ratesAndDefaults,
        uint32[] memory _periodsAndWriteOffs
    ) external;
    function sotToken() external view returns (address);
    function state() external view returns (uint8);
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function tgeAddress() external view returns (address);
    function tokenAssetAddresses(uint256 idx) external view returns (address);
    function totalAssetRepaidCurrency() external view returns (uint256);
    function underlyingCurrency() external view returns (address);
    function unpause() external;
    function updateAssetRiskScore(bytes32 nftID_, uint256 risk_) external;
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
    function writeOff(uint256 loan) external;
    function chiAndPenaltyChi(uint256 loan) external returns (uint256, uint256);
    function debtWithChi(uint256 loan, uint256 chi, uint256 penaltyChi) external returns (uint256);
    function increaseRepayAmount(uint256 principalRepay, uint256 interestRepay) external;
    function getRepaidAmount() external view returns (uint256 principalAmount, uint256 interestAmount);
    function setInterestRateSOT(uint32 _newRate) external;
}
