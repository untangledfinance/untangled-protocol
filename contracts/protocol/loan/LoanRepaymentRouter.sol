// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol';
import {ISecuritizationPool} from '../pool/ISecuritizationPool.sol';

import {ILoanRepaymentRouter} from './ILoanRepaymentRouter.sol';
import {ILoanAssetToken} from '../../interfaces/ILoanAssetToken.sol';
import {Registry} from '../../storage/Registry.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {ISecuritizationTGE} from '../pool/ISecuritizationTGE.sol';
import {ISecuritizationPoolStorage} from '../pool/ISecuritizationPoolStorage.sol';
import {ISecuritizationPoolNAV} from '../pool/ISecuritizationPoolNAV.sol';

/// @title LoanRepaymentRouter
/// @author Untangled Team
/// @dev Repay for loan
contract LoanRepaymentRouter is ILoanRepaymentRouter {
    using ConfigHelper for Registry;

    function initialize(Registry _registry) public override initializer {
        __UntangledBase__init(_msgSender());
        registry = _registry;
    }

    /// @dev performs various checks to validate the repayment request, including ensuring that the token address is not null,
    /// the amount is greater than zero, and the debt agreement exists
    function _assertRepaymentRequest(bytes32 _agreementId, address _tokenAddress) private view returns (bool) {
        require(_tokenAddress != address(0), 'Token address must different with NULL.');

        // Ensure agreement exists.
        if (registry.getLoanAssetToken().ownerOf(uint256(_agreementId)) == address(0)) {
            return false;
        }

        return true;
    }

    /// @dev executes the loan repayment by notifying the terms contract about the repayment,
    /// transferring the repayment amount to the creditor, and handling additional logic related to securitization pools
    /// and completed repayments
    function _doRepay(
        bytes32 _agreementId,
        address _payer,
        uint256 _amount,
        address _tokenAddress
    ) private returns (bool) {
        address beneficiary = registry.getLoanAssetToken().ownerOf(uint256(_agreementId));

        ISecuritizationPoolStorage poolInstance = ISecuritizationPoolStorage(beneficiary);
        ISecuritizationPoolNAV poolNAV = ISecuritizationPoolNAV(beneficiary);
        uint256 repayAmount = poolNAV.repayLoan(uint256(_agreementId), _amount);
        uint256 outstandingAmount = poolNAV.debt(uint256(_agreementId));
        ISecuritizationTGE poolTGE = ISecuritizationTGE(beneficiary);

        require(poolTGE.underlyingCurrency() == _tokenAddress, 'LoanRepaymentRouter: currency mismatch');

        if (registry.getSecuritizationManager().isExistingPools(beneficiary)) beneficiary = poolInstance.pot();
        require(
            IERC20Upgradeable(_tokenAddress).transferFrom(_payer, beneficiary, repayAmount),
            'Unsuccessfully transferred repayment amount to Creditor.'
        );
        poolTGE.increaseTotalAssetRepaidCurrency(repayAmount);

        if (outstandingAmount == 0) {
            // Burn LAT token when repay completely
            registry.getLoanKernel().concludeLoan(beneficiary, _agreementId);
        }

        // Log event for repayment
        emit AssetRepay(_agreementId, _payer, beneficiary, _amount, _tokenAddress);
        return true;
    }

    /// @inheritdoc ILoanRepaymentRouter
    function repayInBatch(
        bytes32[] calldata agreementIds,
        uint256[] calldata amounts,
        address tokenAddress
    ) external override whenNotPaused nonReentrant returns (bool) {
        uint256 agreementIdsLength = agreementIds.length;
        for (uint256 i = 0; i < agreementIdsLength; i++) {
            require(
                _assertRepaymentRequest(agreementIds[i], tokenAddress),
                'LoanRepaymentRouter: Invalid repayment request'
            );
            require(
                _doRepay(agreementIds[i], _msgSender(), amounts[i], tokenAddress),
                'LoanRepaymentRouter: Repayment has failed'
            );
        }
        emit BatchAssetRepay(agreementIds, _msgSender(), amounts, tokenAddress);
        return true;
    }

    uint256[50] private __gap;
}
