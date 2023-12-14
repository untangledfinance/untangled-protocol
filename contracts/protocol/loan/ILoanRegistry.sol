// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '../../storage/Registry.sol';

import { LoanOrder } from './types.sol';

abstract contract ILoanRegistry {
    Registry public registry;

    // loan -> debtors
    struct LoanEntry {
        address loanTermContract;
        address debtor;
        address principalTokenAddress;
        bytes32 termsParam; // actually inside this param was already included P token address
        uint256 salt;
        uint256 issuanceBlockTimestamp;
        uint256 lastRepayTimestamp;
        uint256 expirationTimestamp;
        uint8 riskScore;
        Configuration.ASSET_PURPOSE assetPurpose;
    }

    event UpdateLoanEntry(bytes32 indexed tokenId, LoanEntry entry);
    event UpdateCompleteLoan(bytes32 indexed tokenId, bool status);

    mapping(bytes32 => LoanEntry) public entries;

    mapping(bytes32 => bool) public manualInterestLoan;
    mapping(bytes32 => uint256) public manualInterestAmountLoan;

    mapping(bytes32 => bool) public completedLoans;

    function initialize(Registry _registry) public virtual;

    // /**
    //  * Record new External Loan to blockchain
    //  */
    // function insert(
    //     bytes32 tokenId,
    //     address termContract,
    //     address debtor,
    //     bytes32 termsContractParameter,
    //     address pTokenAddress,
    //     uint256 _salt,
    //     uint256 expirationTimestampInSecs,
    //     uint8[] calldata assetPurposeAndRiskScore
    // ) external virtual returns (bool);

    function insert(
        uint256[] calldata tokenIds,
        address termContract,
        LoanOrder calldata debtOrder,
        bytes32[] calldata termsParam
    )
        external
        virtual
        returns (
            // address[] calldata debtors,
            // bytes32[] calldata termsParam,
            // address principalTokenAddress,
            // uint256[] calldata salts,
            // uint256[] calldata expirationTimestampInSecs,
            // uint8[][] calldata assetPurposeAndRiskScore
            bool
        );

    // /**
    //  * Record new External Loan to blockchain
    //  */
    // function insert(
    //     bytes32 tokenId,
    //     address termContract,
    //     address debtor,
    //     bytes32 termsContractParameter,
    //     address pTokenAddress,
    //     uint256 _salt,
    //     uint256 expirationTimestampInSecs,
    //     uint8[] calldata assetPurposeAndRiskScore
    // ) external virtual;

    /// @notice retrieves loan information
    function getEntry(bytes32 agreementId) public view virtual returns (LoanEntry memory);

    /// @notice retrieves the debtor's address for a given loan
    function getLoanDebtor(bytes32 tokenId) public view virtual returns (address);

    /// @notice retrieves the term contract parameters for a given loan
    function getLoanTermParams(bytes32 tokenId) public view virtual returns (bytes32);

    /// @notice retrieves the principal token address for a given loan agreement ID
    function getPrincipalTokenAddress(bytes32 agreementId) public view virtual returns (address);

    /// @notice retrieves the debtor's address for a given loan agreement ID
    function getDebtor(bytes32 agreementId) public view virtual returns (address);

    /// @notice retrieves the term contract address for a given loan agreement ID
    function getTermContract(bytes32 agreementId) public view virtual returns (address);

    /// @notice retrieves the risk score for a given loan agreement ID
    function getRiskScore(bytes32 agreementId) public view virtual returns (uint8);

    /// @notice retrieves the asset purpose for a given loan agreement ID
    function getAssetPurpose(bytes32 agreementId) public view virtual returns (Configuration.ASSET_PURPOSE);

    /// @notice retrieves the timestamp of the block at which a debt agreement was issued
    function getIssuanceBlockTimestamp(bytes32 agreementId) public view virtual returns (uint256 timestamp);

    /// @notice retrieves the timestamp of the last repayment made for a given loan agreement ID
    function getLastRepaymentTimestamp(bytes32 agreementId) public view virtual returns (uint256 timestamp);

    /// @notice retrieves the terms contract parameters for a given loan agreement ID
    function getTermsContractParameters(bytes32 agreementId) public view virtual returns (bytes32);

    /// @notice retrieves the expiration timestamp for a given loan agreement ID
    function getExpirationTimestamp(bytes32 agreementId) public view virtual returns (uint256);

    /// @notice updates the timestamp of the last repayment made for a given loan agreement ID
    function updateLastRepaymentTimestamp(bytes32 agreementId, uint256 newTimestamp) public virtual;

    /// @notice retrieves information about the principal payment for a given loan agreement ID
    /// @dev Get principal payment info before start doing repayment
    function principalPaymentInfo(
        bytes32 agreementId
    ) public view virtual returns (address pTokenAddress, uint256 pAmount);

    /// @notice marks a loan agreement as completed by setting the completedLoans mapping entry to true for a given agreement ID
    function setCompletedLoan(bytes32 agreementId) public virtual;
}
