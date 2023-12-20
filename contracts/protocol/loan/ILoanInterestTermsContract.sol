// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Registry} from '../../storage/Registry.sol';
import '../../libraries/UnpackLoanParamtersLib.sol';

abstract contract ILoanInterestTermsContract {
    Registry public registry;

    mapping(bytes32 => bool) public startedLoan;

    mapping(bytes32 => uint256) public repaidPrincipalAmounts;
    mapping(bytes32 => uint256) public repaidInterestAmounts;

    mapping(bytes32 => bool) public completedRepayment;

    /// @notice register the start of a loan term
    function registerTermStart(uint256[] calldata agreementIds) public virtual returns (bool);

    /// @notice the total amount of principal and interest repaid for a given loan agreement
    function getValueRepaidToDate(bytes32 agreementId) public view virtual returns (uint256, uint256);

    /// @notice checks whether the repayments for a batch of loan agreements have been completed
    function isCompletedRepayments(bytes32[] memory agreementIds) public view virtual returns (bool[] memory);

    /**
     * Expected repayment value with Amortization of Interest and Principal
     * (AMORTIZATION) - will be used for repayment from Debtor
     */
    /// @notice calculates the expected repayment values (principal and interest) for a given loan agreement and timestamp
    /// @param agreementId loan asset token in bytes32 format
    /// @param timestamp unix timestamp
    /// @return expectedPrincipal value of loan at a specific time
    /// @return expectedInterest interest value at a specific time
    function getExpectedRepaymentValues(
        bytes32 agreementId,
        uint256 timestamp
    ) public view virtual returns (uint256 expectedPrincipal, uint256 expectedInterest);

    /// @notice calculates the expected repayment values (principal and interest) for a batch of loan agreements and a given timestamp
    function getMultiExpectedRepaymentValues(
        bytes32[] memory agreementIds,
        uint256 timestamp
    ) public view virtual returns (uint256[] memory, uint256[] memory);

    /// @dev set loan as repaid
    function registerConcludeLoan(bytes32 agreementId) external virtual returns (bool);

    /// When called, the registerRepayment function records the debtor's
    ///  repayment, as well as any auxiliary metadata needed by the contract
    ///  to determine ex post facto the value repaid (e.g. current USD
    ///  exchange rate)
    /// @notice register a loan repayment
    /// @param  agreementId bytes32. The agreement id (issuance hash) of the debt agreement to which this pertains.
    /// @param  payer address. The address of the payer.
    /// @param  beneficiary address. The address of the payment's beneficiary.
    /// @param  unitsOfRepayment uint. The units-of-value repaid in the transaction.
    /// @param  tokenAddress address. The address of the token with which the repayment transaction was executed.
    function registerRepayment(
        bytes32 agreementId,
        address payer,
        address beneficiary,
        uint256 unitsOfRepayment,
        address tokenAddress
    ) public virtual returns (uint256 remains);

    /// @notice the interest rate for a given loan agreement
    /// @param  agreementId bytes32. The agreement id (issuance hash) of the debt agreement to which this pertains.
    function getInterestRate(bytes32 agreementId) public view virtual returns (uint256);

    function unpackParamsForAgreementID(
        bytes32 agreementId
    ) public view virtual returns (UnpackLoanParamtersLib.InterestParams memory params);

    uint256[46] private __gap;
}
