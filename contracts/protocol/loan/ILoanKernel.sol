// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Registry} from '../../storage/Registry.sol';
import '../../tokens/ERC721/types.sol';

import {LoanOrder} from './types.sol';

abstract contract ILoanKernel {
    Registry public registry;

    /****************** */
    // CONSTANTS
    /****************** */
    enum Errors {
        // Debt has been already been issued
        DEBT_ISSUED, // 0
        // Order has already expired
        ORDER_EXPIRED, // 1
        // Debt issuance associated with order has been cancelled
        ISSUANCE_CANCELLED, // 2
        // Order has been cancelled
        ORDER_CANCELLED, // 3
        // Order parameters specify amount of creditor / debtor fees
        // that is not equivalent to the amount of underwriter / relayer fees
        ORDER_INVALID_INSUFFICIENT_OR_EXCESSIVE_FEES, // 4
        // Order parameters specify insufficient principal amount for
        // debtor to at least be able to meet his fees
        ORDER_INVALID_INSUFFICIENT_PRINCIPAL, // 5
        // Order parameters specify non zero fee for an unspecified recipient
        ORDER_INVALID_UNSPECIFIED_FEE_RECIPIENT, // 6
        // Order signatures are mismatched / malformed
        ORDER_INVALID_NON_CONSENSUAL, // 7
        // Insufficient balance or allowance for principal token transfer
        CREDITOR_BALANCE_OR_ALLOWANCE_INSUFFICIENT, // 8
        // Debt doesn't exists
        DEBT_NOT_EXISTS, // 9
        // Debtor it not completed repayment yet
        NOT_COMPLETED_REPAYMENT // 10
    }

    enum FillingAddressesIndex {
        SECURITIZATION_POOL,
        PRINCIPAL_TOKEN_ADDRESS,
        REPAYMENT_ROUTER,
        TERM_CONTRACT,
        RELAYER
    }

    enum FillingNumbersIndex {
        CREDITOR_FEE,
        ASSET_PURPOSE
    }

    bytes32 public constant NULL_ISSUANCE_HASH = bytes32(0);
    bytes16 public constant NULL_COLLATERAL_INFO_HASH = bytes16(0);
    address public constant NULL_ADDRESS = address(0x0);
    //********************************************************* */

    //****** */
    // EVENTS
    //****** */
    event LogDebtKernelError(uint8 indexed _errorId, bytes32 indexed _orderHash, string desc);

    event LogFeeTransfer(address indexed payer, address token, uint256 amount, address indexed beneficiary);

    event IssuedNewInputLoans(address[] debtor, uint256[] loanTokenIds);

    event LogDebtOrderFilled(bytes32 _agreementId, uint256 _principal, address _principalToken, address _relayer);

    event LogDebtOrderFilledBatch(LoanOrder _debtOrder);

    //********************************************************* */

    /*********** */
    // STRUCTURES
    /*********** */

    struct FillDebtOrderParam {
        address[] orderAddresses; // 0-pool, 1-principal token address, 2-repayment router, 3-term contract, 4-relayer,...
        uint256[] orderValues; //  0-creditorFee, 1-asset purpose,..., [x] principalAmounts, [x] expirationTimestampInSecs, [x] - salts, [x] - riskScores
        bytes32[] termsContractParameters; // Term contract parameters from different farmers, encoded as hash strings
        LoanAssetInfo[] latInfo;
    }

    /*********** */
    // VARIABLES
    /*********** */
    mapping(bytes32 => bool) public issuanceCancelled;
    mapping(bytes32 => bool) public debtOrderCancelled;
    mapping(bytes32 => bool) public debtOrderCompleted;

    /// @notice conclude a loan by stopping lending/loan terms or allowing the loan loss. It takes the creditor, agreement ID, and term contract as input
    function concludeLoan(address creditor, bytes32 agreementId, address termContract) public virtual;
}
