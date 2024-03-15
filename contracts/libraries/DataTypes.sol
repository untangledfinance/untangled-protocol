// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// import '../storage/Registry.sol';
import './Configuration.sol';
import './UnpackLoanParamtersLib.sol';

uint256 constant RATE_SCALING_FACTOR = 10 ** 4;

uint256 constant ONE_HUNDRED_PERCENT = 100 * RATE_SCALING_FACTOR;

uint256 constant ONE = 10 ** 27;
uint256 constant WRITEOFF_RATE_GROUP_START = 1000 * ONE;

bytes32 constant OWNER_ROLE = keccak256('OWNER_ROLE');
bytes32 constant ORIGINATOR_ROLE = keccak256('ORIGINATOR_ROLE');
bytes32 constant BACKEND_ADMIN_ROLE = keccak256('BACKEND_ADMIN');
bytes32 constant SIGNER_ROLE = keccak256('SIGNER_ROLE');
bytes32 constant SUPER_ADMIN_ROLE = keccak256('SUPER_ADMIN');
bytes32 constant POOL_ADMIN_ROLE = keccak256('POOL_CREATOR');

// In PoolNAV we use this
bytes32 constant POOL = keccak256('POOL');

uint256 constant PRICE_DECIMAL = 10 ** 18;

bytes32 constant VALIDATOR_ROLE = keccak256('VALIDATOR_ROLE');

bytes32 constant MINTER_ROLE = keccak256('MINTER_ROLE');

// In Go
bytes32 constant ZAPPER_ROLE = keccak256('ZAPPER_ROLE');

// in ERC1155PresetPauserUpgradeable
bytes32 constant PAUSER_ROLE = keccak256('PAUSER_ROLE');

library DataTypes {
    struct NoteToken {
        address poolAddress;
        address noteTokenAddress;
        uint256 balance;
        uint256 apy;
    }
    struct RiskScore {
        uint32 daysPastDue;
        uint32 advanceRate;
        uint32 penaltyRate;
        uint32 interestRate;
        uint32 probabilityOfDefault;
        uint32 lossGivenDefault;
        uint32 writeOffAfterGracePeriod;
        uint32 gracePeriod;
        uint32 collectionPeriod;
        uint32 writeOffAfterCollectionPeriod;
        uint32 discountRate;
    }

    struct LoanEntry {
        address debtor;
        address principalTokenAddress;
        bytes32 termsParam; // actually inside this param was already included P token address
        uint256 salt;
        uint256 issuanceBlockTimestamp;
        uint256 expirationTimestamp;
        uint8 riskScore;
        Configuration.ASSET_PURPOSE assetPurpose;
    }
    struct NFTAsset {
        address tokenAddress;
        uint256 tokenId;
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
        uint256 incomeReserve;
        uint256 capitalReserve;
        uint32 minFirstLossCushion;
        uint64 openingBlockTimestamp;
        // by default it is address(this)
        address pot;
        // for base (sell-loan) operation
        uint256 paidPrincipalAmountSOT;
        uint256 interestRateSOT; // Annually, support 4 decimals num
        uint256 totalAssetRepaidCurrency;
        uint256 debtCeiling;
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
        // value to view
        uint256 totalPrincipalRepaid;
        uint256 totalInterestRepaid;
        // value to calculate rebase
        uint256 seniorDebt;
        uint256 seniorBalance;
        uint64 lastUpdateSeniorInterest;
    }

    struct LoanAssetInfo {
        uint256[] tokenIds;
        uint256[] nonces;
        address validator;
        bytes validateSignature;
    }
}
