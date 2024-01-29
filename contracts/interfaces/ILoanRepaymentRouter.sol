// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface ILoanRepaymentRouter {
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

    /// @notice allows batch repayment of multiple loans by iterating over the given agreement IDs and amounts
    /// @dev calls _assertRepaymentRequest and _doRepay for each repayment, and emits the LogRepayments event to indicate the successful batch repayment
    function repayInBatch(
        bytes32[] calldata agreementIds,
        uint256[] calldata amounts,
        address tokenAddress
    ) external returns (bool);
}
