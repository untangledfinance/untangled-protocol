// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Registry} from '../../storage/Registry.sol';
import '../../tokens/ERC721/types.sol';

abstract contract ILoanKernel {
    Registry public registry;

    /****************** */
    // CONSTANTS
    /****************** */

    enum FillingAddressesIndex {
        SECURITIZATION_POOL,
        PRINCIPAL_TOKEN_ADDRESS,
        REPAYMENT_ROUTER
    }

    enum FillingNumbersIndex {
        CREDITOR_FEE,
        ASSET_PURPOSE
    }

    //********************************************************* */

    //****** */
    // EVENTS
    //****** */

    //********************************************************* */

    /*********** */
    // STRUCTURES
    /*********** */

    struct LoanIssuance {
        address version;
        address[] debtors;
        bytes32[] termsContractParameters; // for different loans
        bytes32[] agreementIds;
        uint256[] salts;
    }

    struct LoanOrder {
        LoanIssuance issuance;
        address principalTokenAddress;
        uint256[] principalAmounts;
        uint256 creditorFee;
        uint256[] expirationTimestampInSecs;
        bytes32[] debtOrderHashes;
        uint8[] riskScores;
        uint8 assetPurpose;
    }

    struct FillDebtOrderParam {
        address[] orderAddresses; // 0-pool, 1-principal token address, 2-repayment router,...
        uint256[] orderValues; //  0-creditorFee, 1-asset purpose,..., [x] principalAmounts, [x] expirationTimestampInSecs, [x] - salts, [x] - riskScores
        bytes32[] termsContractParameters; // Term contract parameters from different farmers, encoded as hash strings
        LoanAssetInfo[] latInfo;
    }

    /*********** */
    // VARIABLES
    /*********** */

    /// @notice conclude a loan by stopping lending/loan terms or allowing the loan loss. It takes the creditor, agreement ID, and term contract as input
    function concludeLoan(address creditor, bytes32 agreementId) public virtual;
}
