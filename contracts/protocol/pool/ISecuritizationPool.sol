// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import '../../storage/Registry.sol';
import '../../base/UntangledBase.sol';
import '../../libraries/Configuration.sol';

import {RiskScore, LoanEntry} from './base/types.sol';

import {ISecuritizationPoolStorage} from './ISecuritizationPoolStorage.sol';

interface ISecuritizationPool {
    event CollectNFTAsset(uint256[] tokenIds, uint256 expectedAssetsValue);
    // event UpdateOpeningBlockTimestamp(uint256 newTimestamp);
    event SecuritizationPoolWithdraw(address originatorAddress, uint256 amount);
    event CollectERC20Asset(address token);
    event WithdrawERC20Asset(address[] tokenAddresses, address[] recipients, uint256[] amounts);
    event InsertNFTAsset(address token, uint256 tokenId);
    event ExportNFTAsset(address tokenAddress, address toPoolAddress, uint256[] tokenIds);
    event WithdrawNFTAsset(address[] tokenAddresses, uint256[] tokenIds, address[] recipients);
    event SetRiskScore(RiskScore[] riskscores);
    event UpdateTGEAddress(address tge, address token, Configuration.NOTE_TOKEN_TYPE noteType);
    event UpdateInterestRateSOT(uint32 _interestRateSOT);
    event UpdateLockedDistributeBalance(
        address indexed tokenAddress,
        address indexed investor,
        uint256 lockedDistributeBalance,
        uint256 lockedRedeemBalances,
        uint256 totalLockedRedeemBalances,
        uint256 totalLockedDistributeBalance
    );
    event UpdateReserve(uint256 currencyAmount);
    event UpdatePaidPrincipalAmountSOTByInvestor(address indexed user, uint256 currencyAmount);

    /// @notice A view function that returns the length of the NFT (non-fungible token) assets array
    function getNFTAssetsLength() external view returns (uint256);

    /// @notice A view function that returns an array of token asset addresses
    function getTokenAssetAddresses() external view returns (address[] memory);

    /// @notice A view function that returns the length of the token asset addresses array
    function getTokenAssetAddressesLength() external view returns (uint256);

    /// @notice Riks scores length
    /// @return the length of the risk scores array
    function getRiskScoresLength() external view returns (uint256);

    function riskScores(uint256 index) external view returns (RiskScore memory);

    /// @notice sets up the risk scores for the contract for pool
    function setupRiskScores(
        uint32[] calldata _daysPastDues,
        uint32[] calldata _ratesAndDefaults,
        uint32[] calldata _periodsAndWriteOffs
    ) external;

    /// @notice exports NFT assets to another pool address
    function exportAssets(address tokenAddress, address toPoolAddress, uint256[] calldata tokenIds) external;

    /// @notice withdraws NFT assets from the contract and transfers them to recipients
    function withdrawAssets(
        address[] calldata tokenAddresses,
        uint256[] calldata tokenIds,
        address[] calldata recipients
    ) external;

    /// @notice collects NFT assets from a specified address
    function collectAssets(uint256[] calldata tokenIds, LoanEntry[] calldata loanEntries) external returns (uint256);

    /// @notice collects ERC20 assets from specified senders
    function collectERC20Asset(address tokenAddresss) external;

    /// @notice withdraws ERC20 assets from the contract and transfers them to recipients\
    function withdrawERC20Assets(
        address[] calldata tokenAddresses,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external;

    function nftAssets(uint256 idx) external view returns (ISecuritizationPoolStorage.NFTAsset memory);

    function tokenAssetAddresses(uint256 idx) external view returns (address);

    /// @dev Trigger set up opening block timestamp
    function setUpOpeningBlockTimestamp() external;

    function pause() external;

    function unpause() external;
}
