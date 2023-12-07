// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import '../../storage/Registry.sol';

import {RiskScore} from './base/types.sol';

interface ISecuritizationPoolStorage {
    event UpdateOpeningBlockTimestamp(uint256 newTimestamp);

    struct NFTAsset {
        address tokenAddress;
        uint256 tokenId;
    }

    enum CycleState {
        INITIATED,
        CROWDSALE,
        OPEN,
        CLOSED
    }

    struct NewPoolParams {
        address currency;
        uint32 minFirstLossCushion;
        bool validatorRequired;
        uint256 debtCeiling;
    }

    struct UserOrder {
        uint256 redeemSOTAmount;
        uint256 redeemJOTAmount;
    }


    struct Storage {
        bool validatorRequired;
        uint64 firstAssetTimestamp;
        RiskScore[] riskScores;
        NFTAsset[] nftAssets;
        address[] tokenAssetAddresses;
        mapping(address => bool) existsTokenAssetAddress;
        // TGE
        address tgeAddress;
        address secondTGEAddress;
        address sotToken;
        address jotToken;

        address underlyingCurrency;
        uint256 reserve; // Money in pool
        uint32 minFirstLossCushion;
        uint64 openingBlockTimestamp;
        uint64 termLengthInSeconds;
        // by default it is address(this)
        address pot;
        // for base (sell-loan) operation
        uint256 principalAmountSOT;
        uint256 paidPrincipalAmountSOT;
        uint32 interestRateSOT; // Annually, support 4 decimals num
        uint256 totalAssetRepaidCurrency;
        mapping(address => uint256) paidPrincipalAmountSOTByInvestor;
        uint256 amountOwedToOriginator;
        uint256 debtCeiling;
        CycleState state;
        // lock distribution
        mapping(address => mapping(address => uint256)) lockedDistributeBalances;
        uint256 totalLockedDistributeBalance;
        mapping(address => mapping(address => uint256)) lockedRedeemBalances;
        // token address -> total locked
        mapping(address => uint256) totalLockedRedeemBalances;
        uint256 totalRedeemedCurrency; // Total $ (cUSD) has been redeemed
        address poolNAV;

        // redeem
        bool redeemDisabled;
        uint256 totalSOTRedeem;
        uint256 totalJOTRedeem;
        mapping(address => UserOrder) userRedeems;
    }

    function amountOwedToOriginator() external view returns (uint256);

    function tgeAddress() external view returns (address);

    function secondTGEAddress() external view returns (address);

    function state() external view returns (CycleState);

    /// @notice checks if the contract is in a closed state
    function isClosedState() external view returns (bool);

    function pot() external view returns (address);

    function poolNAV() external view returns (address);

    function validatorRequired() external view returns (bool);

    function openingBlockTimestamp() external view returns (uint64);
}
