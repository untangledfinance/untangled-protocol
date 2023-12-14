// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Registry} from '../../storage/Registry.sol';
import {UntangledBase} from '../../base/UntangledBase.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {ILoanRegistry} from './ILoanRegistry.sol';
import {Configuration} from '../../libraries/Configuration.sol';

import {LoanOrder} from './types.sol';

/// @title LoanRegistry
/// @author Untangled Team
/// @dev Store LoanAssetToken information
contract LoanRegistry is UntangledBase, ILoanRegistry {
    using ConfigHelper for Registry;

    /** CONSTRUCTOR */
    function initialize(Registry _registry) public override initializer {
        __UntangledBase__init(_msgSender());
        registry = _registry;
    }

    modifier onlyLoanKernel() {
        require(_msgSender() == address(registry.getLoanKernel()), 'LoanRegistry: Only LoanKernel');
        _;
    }

    modifier onlyLoanInterestTermsContract() {
        require(
            _msgSender() == address(registry.getLoanInterestTermsContract()),
            'Invoice Debt Registry: Only LoanInterestTermsContract'
        );
        _;
    }

    /**
    //  * Record new Loan to blockchain
    //  */
    // /// @dev Records a new loan entry by inserting loan details into the entries mapping
    // function insert(
    //     bytes32 tokenId,
    //     address termContract,
    //     address debtor,
    //     bytes32 termsContractParameter,
    //     address pTokenAddress,
    //     uint256 _salt,
    //     uint256 expirationTimestampInSecs,
    //     uint8[] calldata assetPurposeAndRiskScore
    // ) external override whenNotPaused onlyLoanKernel returns (bool) {
    //     require(termContract != address(0x0), 'LoanRegistry: Invalid term contract');
    //     LoanEntry memory newEntry = LoanEntry({
    //         loanTermContract: termContract,
    //         debtor: debtor,
    //         principalTokenAddress: pTokenAddress,
    //         termsParam: termsContractParameter,
    //         salt: _salt, //solium-disable-next-line security
    //         issuanceBlockTimestamp: block.timestamp,
    //         lastRepayTimestamp: 0,
    //         expirationTimestamp: expirationTimestampInSecs,
    //         assetPurpose: Configuration.ASSET_PURPOSE(assetPurposeAndRiskScore[0]),
    //         riskScore: assetPurposeAndRiskScore[1]
    //     });
    //     entries[tokenId] = newEntry;

    //     emit UpdateLoanEntry(tokenId, newEntry);
    //     return true;
    // }

    function insert(
        uint256[] calldata tokenIds,
        address termContract,
        LoanOrder calldata loanOrder,
        bytes32[] calldata termsParams
    )
        external
        override
        // address[] calldata debtors,
        // bytes32[] calldata termsParams,
        // address principalTokenAddress,
        // uint256[] calldata salts,
        // uint256[] calldata expirationTimestampInSecs,
        // uint8[][] calldata assetPurposeAndRiskScore
        whenNotPaused
        onlyLoanKernel
        returns (bool)
    {
        require(termContract != address(0x0), 'LoanRegistry: Invalid term contract');
        for (uint256 i = 0; i < tokenIds.length; i++) {
            {
                _insert(
                    bytes32(tokenIds[i]),
                    termContract,
                    loanOrder.issuance.debtors[i],
                    termsParams[i],
                    loanOrder.principalTokenAddress,
                    loanOrder.issuance.salts[i],
                    loanOrder.expirationTimestampInSecs[i],
                    loanOrder.assetPurpose,
                    loanOrder.riskScores[i]
                    // expirationTimestampInSecs[i],
                    // assetPurposeAndRiskScore[i]
                );
            }
        }
        return true;
    }

    function _insert(
        bytes32 tokenId,
        address termContract,
        address debtor,
        bytes32 termsContractParameter,
        address pTokenAddress,
        uint256 _salt,
        uint256 expirationTimestampInSecs,
        uint8 assetPurpose,
        uint8 riskScore
    )
        internal
        returns (
            // uint8[] calldata assetPurposeAndRiskScore
            bool
        )
    {
        require(termContract != address(0x0), 'LoanRegistry: Invalid term contract');
        LoanEntry memory newEntry = LoanEntry({
            loanTermContract: termContract,
            debtor: debtor,
            principalTokenAddress: pTokenAddress,
            termsParam: termsContractParameter,
            salt: _salt, //solium-disable-next-line security
            issuanceBlockTimestamp: block.timestamp,
            lastRepayTimestamp: 0,
            expirationTimestamp: expirationTimestampInSecs,
            assetPurpose: Configuration.ASSET_PURPOSE(assetPurpose), // Configuration.ASSET_PURPOSE(assetPurposeAndRiskScore[0]),
            riskScore: riskScore // assetPurposeAndRiskScore[1]
        });
        entries[tokenId] = newEntry;

        emit UpdateLoanEntry(tokenId, newEntry);
        return true;
    }

    // function insert(
    //     bytes32[] calldata tokenIds,
    //     address termContract,
    //     address debtor,
    //     bytes32 termsContractParameter,
    //     address pTokenAddress,
    //     uint256 _salt,
    //     uint256 expirationTimestampInSecs,
    //     uint8[] calldata assetPurposeAndRiskScore
    // ) external override whenNotPaused onlyLoanKernel {
    //     require(termContract != address(0x0), 'LoanRegistry: Invalid term contract');
    //     LoanEntry memory newEntry = LoanEntry({
    //         loanTermContract: termContract,
    //         debtor: debtor,
    //         principalTokenAddress: pTokenAddress,
    //         termsParam: termsContractParameter,
    //         salt: _salt, //solium-disable-next-line security
    //         issuanceBlockTimestamp: block.timestamp,
    //         lastRepayTimestamp: 0,
    //         expirationTimestamp: expirationTimestampInSecs,
    //         assetPurpose: Configuration.ASSET_PURPOSE(assetPurposeAndRiskScore[0]),
    //         riskScore: assetPurposeAndRiskScore[1]
    //     });

    //     for (uint i = 0; i < tokenIds.length; i++) {
    //         entries[tokenIds[i]] = newEntry;
    //         emit UpdateLoanEntry(tokenIds[i], newEntry);
    //     }
    // }

    /// @inheritdoc ILoanRegistry
    function getLoanDebtor(bytes32 tokenId) public view override returns (address) {
        return entries[tokenId].debtor;
    }

    /// @inheritdoc ILoanRegistry
    function getLoanTermParams(bytes32 tokenId) public view override returns (bytes32) {
        LoanEntry memory entry = entries[tokenId];
        return entry.termsParam;
    }

    /// @inheritdoc ILoanRegistry
    function getPrincipalTokenAddress(bytes32 agreementId) public view override returns (address) {
        return entries[agreementId].principalTokenAddress;
    }

    /// @inheritdoc ILoanRegistry
    function getDebtor(bytes32 agreementId) public view override returns (address) {
        return entries[agreementId].debtor;
    }

    /// @inheritdoc ILoanRegistry
    function getTermContract(bytes32 agreementId) public view override returns (address) {
        return entries[agreementId].loanTermContract;
    }

    /// @inheritdoc ILoanRegistry
    function getRiskScore(bytes32 agreementId) public view override returns (uint8) {
        return entries[agreementId].riskScore;
    }

    /// @inheritdoc ILoanRegistry
    function getAssetPurpose(bytes32 agreementId) public view override returns (Configuration.ASSET_PURPOSE) {
        return entries[agreementId].assetPurpose;
    }

    /// @inheritdoc ILoanRegistry
    function getEntry(bytes32 agreementId) public view override returns (LoanEntry memory) {
        return entries[agreementId];
    }

    /**
     * Returns the timestamp of the block at which a debt agreement was issued.
     */
    /// @inheritdoc ILoanRegistry
    function getIssuanceBlockTimestamp(bytes32 agreementId) public view override returns (uint256 timestamp) {
        return entries[agreementId].issuanceBlockTimestamp;
    }

    /// @inheritdoc ILoanRegistry
    function getLastRepaymentTimestamp(bytes32 agreementId) public view override returns (uint256 timestamp) {
        return entries[agreementId].lastRepayTimestamp;
    }

    /**
     * Returns the terms contract parameters of a given issuance
     */
    /// @inheritdoc ILoanRegistry
    function getTermsContractParameters(bytes32 agreementId) public view override returns (bytes32) {
        return entries[agreementId].termsParam;
    }

    /// @inheritdoc ILoanRegistry
    function getExpirationTimestamp(bytes32 agreementId) public view override returns (uint256) {
        // solhint-disable-next-line not-rely-on-time
        return entries[agreementId].expirationTimestamp;
    }

    // Update timestamp of the last repayment from Debtor
    /// @inheritdoc ILoanRegistry
    function updateLastRepaymentTimestamp(
        bytes32 agreementId,
        uint256 newTimestamp
    ) public override onlyLoanInterestTermsContract {
        entries[agreementId].lastRepayTimestamp = newTimestamp;
        emit UpdateLoanEntry(agreementId, entries[agreementId]);
    }

    /// @dev Get principal payment info before start doing repayment
    function principalPaymentInfo(
        bytes32 agreementId
    ) public view override returns (address pTokenAddress, uint256 pAmount) {
        LoanEntry memory entry = entries[agreementId];
        pTokenAddress = entry.principalTokenAddress;
        pAmount = 0; // @TODO
    }

    /// @inheritdoc ILoanRegistry
    function setCompletedLoan(bytes32 agreementId) public override whenNotPaused onlyLoanInterestTermsContract {
        completedLoans[agreementId] = true;
    }

    uint256[50] private __gap;
}
