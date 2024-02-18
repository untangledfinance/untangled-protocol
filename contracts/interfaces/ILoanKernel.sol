// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import '../libraries/DataTypes.sol';

interface ILoanKernel {
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

    event LogOutputSubmit(bytes32 indexed _agreementId, uint256 indexed _tokenIndex, uint256 _totalAmount);

    event AssetRepay(
        bytes32 indexed _agreementId,
        address indexed _payer,
        address indexed _beneficiary,
        uint256 _amount,
        address _token
    );

    event BatchAssetRepay(bytes32[] _agreementIds, address _payer, uint256[] _amounts, address _token);

    event LogError(uint8 indexed _errorId, bytes32 indexed _agreementId);

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
        DataTypes.LoanAssetInfo[] latInfo;
    }

    /*********** */
    // VARIABLES
    /*********** */

    /// @notice allows batch repayment of multiple loans by iterating over the given agreement IDs and amounts
    /// @dev calls _assertRepaymentRequest and _doRepay for each repayment, and emits the LogRepayments event to indicate the successful batch repayment
    function repayInBatch(
        bytes32[] calldata agreementIds,
        uint256[] calldata amounts,
        address tokenAddress
    ) external returns (bool);
}
