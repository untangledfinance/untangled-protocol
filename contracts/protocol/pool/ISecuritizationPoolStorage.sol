// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import '../../storage/Registry.sol';

import {RiskScore} from './base/types.sol';
import 'contracts/libraries/UnpackLoanParamtersLib.sol';

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

    /// @notice details of the underlying collateral
    struct NFTDetails {
        uint128 futureValue;
        uint128 maturityDate;
        uint128 risk;
        address debtor;
        address principalTokenAddress;
        uint256 salt;
        uint256 issuanceBlockTimestamp;
        uint256 expirationTimestamp;
        Configuration.ASSET_PURPOSE assetPurpose;
        bytes32 termsParam;
        uint256 principalAmount;
        uint256 termStartUnixTimestamp;
        uint256 termEndUnixTimestamp;
        UnpackLoanParamtersLib.AmortizationUnitType amortizationUnitType;
        uint256 termLengthInAmortizationUnits;
        uint256 interestRate;
    }

    /// @notice stores all needed information of an interest rate group
    struct Rate {
        // total debt of all loans with this rate
        uint256 pie;
        // accumlated rate index over time
        uint256 chi;
        // interest rate per second
        uint256 ratePerSecond;
        // penalty rate per second
        uint256 penaltyRatePerSecond;
        // accumlated penalty rate index over time
        uint256 penaltyChi;
        // last time the rate was accumulated
        uint48 lastUpdated;
        // time start to penalty
        uint48 timeStartPenalty;
    }

    /// @notice details of the loan
    struct LoanDetails {
        uint128 borrowed;
        // only auth calls can move loan into different writeOff group
        bool authWriteOff;
    }

    /// @notice details of the write off group
    struct WriteOffGroup {
        // denominated in (10^27)
        uint128 percentage;
        // amount of days after the maturity days that the writeoff group can be applied by default
        uint128 overdueDays;
        uint128 riskIndex;
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
        // by default it is address(this)
        address pot;
        // for base (sell-loan) operation
        uint256 paidPrincipalAmountSOT;
        uint32 interestRateSOT; // Annually, support 4 decimals num
        uint256 totalAssetRepaidCurrency;
        mapping(address => uint256) paidPrincipalAmountSOTByInvestor;
        uint256 debtCeiling;
        CycleState state;
        // lock distribution
        mapping(address => mapping(address => uint256)) lockedDistributeBalances;
        uint256 totalLockedDistributeBalance;
        mapping(address => mapping(address => uint256)) lockedRedeemBalances;
        // token address -> total locked
        mapping(address => uint256) totalLockedRedeemBalances;
        uint256 totalRedeemedCurrency; // Total $ (cUSD) has been redeemed
        /// @notice Interest Rate Groups are identified by a `uint` and stored in a mapping
        mapping(uint256 => Rate) rates;
        mapping(uint256 => uint256) pie;
        /// @notice mapping from loan => rate
        mapping(uint256 => uint256) loanRates;
        /// @notice mapping from loan => grace time

        uint256 loanCount;
        mapping(uint256 => uint256) balances;
        uint256 balance;
        // nft => details
        mapping(bytes32 => NFTDetails) details;
        // loan => details
        mapping(uint256 => LoanDetails) loanDetails;
        // timestamp => bucket
        mapping(uint256 => uint256) buckets;
        WriteOffGroup[] writeOffGroups;
        // Write-off groups will be added as rate groups to the pile with their index
        // in the writeOffGroups array + this number
        //        uint256 constant WRITEOFF_RATE_GROUP_START = 1000 * ONE;
        //        uint256 constant INTEREST_RATE_SCALING_FACTOR_PERCENT = 10 ** 4;

        // Discount rate applied on every asset's fv depending on its maturityDate.
        // The discount decreases with the maturityDate approaching.
        // denominated in (10^27)
        uint256 discountRate;
        // latestNAV is calculated in case of borrows & repayments between epoch executions.
        // It decreases/increases the NAV by the repaid/borrowed amount without running the NAV calculation routine.
        // This is required for more accurate Senior & JuniorAssetValue estimations between epochs
        uint256 latestNAV;
        uint256 latestDiscount;
        uint256 lastNAVUpdate;
        // overdue loans are loans which passed the maturity date but are not written-off
        uint256 overdueLoans;
        // tokenId => latestDiscount
        mapping(bytes32 => uint256) latestDiscountOfNavAssets;
        mapping(bytes32 => uint256) overdueLoansOfNavAssets;
        mapping(uint256 => bytes32) loanToNFT;
    }

    function tgeAddress() external view returns (address);

    function secondTGEAddress() external view returns (address);

    function state() external view returns (CycleState);

    /// @notice checks if the contract is in a closed state
    function isClosedState() external view returns (bool);

    function pot() external view returns (address);

    function validatorRequired() external view returns (bool);

    function openingBlockTimestamp() external view returns (uint64);
}
