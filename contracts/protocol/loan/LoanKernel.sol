// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {ERC165CheckerUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol';
import '../../interfaces/ILoanKernel.sol';
import '../../base/UntangledBase.sol';
import '../../libraries/ConfigHelper.sol';
import '../../libraries/UntangledMath.sol';
import {DataTypes} from '../../libraries/DataTypes.sol';
import {IPool} from '../../interfaces/IPool.sol';
import '../../libraries/TransferHelper.sol';

/// @title LoanKernel
/// @author Untangled Team
/// @notice Upload loan, Repay Loan and conclude loan
contract LoanKernel is ILoanKernel, UntangledBase {
    using ConfigHelper for Registry;
    using ERC165CheckerUpgradeable for address;

    Registry public registry;

    function initialize(Registry _registry) public initializer {
        __UntangledBase__init_unchained(_msgSender());
        registry = _registry;
    }

    modifier validFillingOrderAddresses(address[] memory _orderAddresses) {
        require(
            _orderAddresses[uint8(FillingAddressesIndex.SECURITIZATION_POOL)] != address(0x0),
            'SECURITIZATION_POOL is zero address.'
        );

        require(
            _orderAddresses[uint8(FillingAddressesIndex.REPAYMENT_ROUTER)] != address(0x0),
            'REPAYMENT_ROUTER is zero address.'
        );

        require(
            _orderAddresses[uint8(FillingAddressesIndex.PRINCIPAL_TOKEN_ADDRESS)] != address(0x0),
            'PRINCIPAL_TOKEN_ADDRESS is zero address.'
        );
        _;
    }

    //******************** */
    // PRIVATE FUNCTIONS
    //******************** */

    /**
     * Helper function that constructs a issuance structs from the given
     * parameters.
     */
    function _getIssuance(
        address[] memory _orderAddresses,
        address[] memory _debtors,
        bytes32[] memory _termsContractParameters,
        uint256[] memory _salts
    ) private pure returns (LoanIssuance memory _issuance) {
        LoanIssuance memory issuance = LoanIssuance({
            version: _orderAddresses[uint8(FillingAddressesIndex.REPAYMENT_ROUTER)],
            debtors: _debtors,
            termsContractParameters: _termsContractParameters,
            salts: _salts,
            agreementIds: _genLoanAgreementIds(
                _orderAddresses[uint8(FillingAddressesIndex.REPAYMENT_ROUTER)],
                _debtors,
                _termsContractParameters,
                _salts
            )
        });

        return issuance;
    }

    function _getDebtOrderHashes(LoanOrder memory debtOrder) private view returns (bytes32[] memory) {
        uint256 _length = debtOrder.issuance.debtors.length;
        bytes32[] memory orderHashses = new bytes32[](_length);
        for (uint256 i = 0; i < _length; i = UntangledMath.uncheckedInc(i)) {
            orderHashses[i] = _getDebtOrderHash(
                debtOrder.issuance.agreementIds[i],
                debtOrder.principalAmounts[i],
                debtOrder.principalTokenAddress,
                debtOrder.expirationTimestampInSecs[i]
            );
        }
        return orderHashses;
    }

    function _getLoanOrder(
        address[] memory _debtors,
        address[] memory _orderAddresses,
        uint256[] memory _orderValues,
        bytes32[] memory _termContractParameters,
        uint256[] memory _salts
    ) private view returns (LoanOrder memory _debtOrder) {
        bytes32[] memory emptyDebtOrderHashes = new bytes32[](_debtors.length);
        LoanOrder memory debtOrder = LoanOrder({
            issuance: _getIssuance(_orderAddresses, _debtors, _termContractParameters, _salts),
            principalTokenAddress: _orderAddresses[uint8(FillingAddressesIndex.PRINCIPAL_TOKEN_ADDRESS)],
            principalAmounts: _principalAmountsFromOrderValues(_orderValues, _termContractParameters.length),
            creditorFee: _orderValues[uint8(FillingNumbersIndex.CREDITOR_FEE)],
            expirationTimestampInSecs: _expirationTimestampsFromOrderValues(
                _orderValues,
                _termContractParameters.length
            ),
            debtOrderHashes: emptyDebtOrderHashes,
            riskScores: _riskScoresFromOrderValues(_orderValues, _termContractParameters.length),
            assetPurpose: uint8(_orderValues[uint8(FillingNumbersIndex.ASSET_PURPOSE)])
        });
        debtOrder.debtOrderHashes = _getDebtOrderHashes(debtOrder);
        return debtOrder;
    }

    /**
     * 6 is fixed size of constant addresses list
     */
    function _debtorsFromOrderAddresses(
        address[] memory _orderAddresses,
        uint256 _length
    ) private pure returns (address[] memory) {
        address[] memory debtors = new address[](_length);
        for (uint256 i = 3; i < (3 + _length); i = UntangledMath.uncheckedInc(i)) {
            debtors[i - 3] = _orderAddresses[i];
        }
        return debtors;
    }

    // Dettach principal amounts from order values
    function _principalAmountsFromOrderValues(
        uint256[] memory _orderValues,
        uint256 _length
    ) private pure returns (uint256[] memory) {
        uint256[] memory principalAmounts = new uint256[](_length);
        for (uint256 i = 2; i < (2 + _length); i = UntangledMath.uncheckedInc(i)) {
            principalAmounts[i - 2] = _orderValues[i];
        }
        return principalAmounts;
    }

    function _expirationTimestampsFromOrderValues(
        uint256[] memory _orderValues,
        uint256 _length
    ) private pure returns (uint256[] memory) {
        uint256[] memory expirationTimestamps = new uint256[](_length);
        for (uint256 i = 2 + _length; i < (2 + _length * 2); i = UntangledMath.uncheckedInc(i)) {
            expirationTimestamps[i - 2 - _length] = _orderValues[i];
        }
        return expirationTimestamps;
    }

    function _saltFromOrderValues(
        uint256[] memory _orderValues,
        uint256 _length
    ) private pure returns (uint256[] memory) {
        uint256[] memory salts = new uint256[](_length);
        for (uint256 i = 2 + _length * 2; i < (2 + _length * 3); i = UntangledMath.uncheckedInc(i)) {
            salts[i - 2 - _length * 2] = _orderValues[i];
        }
        return salts;
    }

    function _riskScoresFromOrderValues(
        uint256[] memory _orderValues,
        uint256 _length
    ) private pure returns (uint8[] memory) {
        uint8[] memory riskScores = new uint8[](_length);
        for (uint256 i = 2 + _length * 3; i < (2 + _length * 4); i = UntangledMath.uncheckedInc(i)) {
            riskScores[i - 2 - _length * 3] = uint8(_orderValues[i]);
        }
        return riskScores;
    }

    function _burnLoanAssetToken(bytes32 agreementId) private {
        registry.getLoanAssetToken().burn(uint256(agreementId));
    }

    function _assertDebtExisting(bytes32 agreementId) private view returns (bool) {
        return registry.getLoanAssetToken().ownerOf(uint256(agreementId)) != address(0);
    }

    /// @dev executes the loan repayment by notifying the terms contract about the repayment,
    /// transferring the repayment amount to the creditor, and handling additional logic related to securitization pools
    /// and completed repayments
    function _doRepay(
        IPool _pool,
        uint256[] memory _nftIds,
        address _payer,
        uint256[] memory _amount,
        address _tokenAddress
    ) private returns (bool) {
        address beneficiary = address(_pool);
        if (registry.getSecuritizationManager().isExistingPools(beneficiary)) beneficiary = _pool.pot();

        uint256 totalRepayAmount;
        (uint256[] memory repayAmounts, uint256[] memory previousDebts) = _pool.repayLoan(_nftIds, _amount);

        for (uint256 i; i < repayAmounts.length; i++) {
            uint256 outstandingAmount = _pool.debt(uint256(_nftIds[i]));
            // repay all principal and interest
            // Burn LAT token when repay completely
            if (repayAmounts[i] == previousDebts[i]) {
                _concludeLoan(beneficiary, bytes32(_nftIds[i]));
            }
            totalRepayAmount += repayAmounts[i];
            // Log event for repayment
            emit AssetRepay(
                bytes32(_nftIds[i]),
                _payer,
                address(_pool),
                repayAmounts[i],
                outstandingAmount,
                _tokenAddress
            );
        }

        TransferHelper.safeTransferFrom(_tokenAddress, _payer, beneficiary, totalRepayAmount);
        _pool.increaseTotalAssetRepaidCurrency(totalRepayAmount);

        return true;
    }

    /// @dev A loan, stop lending/loan terms or allow the loan loss
    function _concludeLoan(address creditor, bytes32 agreementId) internal {
        require(creditor != address(0), 'Invalid creditor account.');
        require(agreementId != bytes32(0), 'Invalid agreement id.');

        if (!_assertDebtExisting(agreementId)) {
            revert('Debt does not exsits');
        }

        _burnLoanAssetToken(agreementId);
    }

    function _getDebtOrderHash(
        bytes32 agreementId,
        uint256 principalAmount,
        address principalTokenAddress,
        uint256 expirationTimestampInSec
    ) private view returns (bytes32 _debtorMessageHash) {
        return
            keccak256(
                abi.encodePacked(
                    address(this),
                    agreementId,
                    principalAmount,
                    principalTokenAddress,
                    expirationTimestampInSec
                )
            );
    }

    function _genLoanAgreementIds(
        address _version,
        address[] memory _debtors,
        bytes32[] memory _termsContractParameters,
        uint256[] memory _salts
    ) private pure returns (bytes32[] memory) {
        bytes32[] memory agreementIds = new bytes32[](_salts.length);
        for (uint256 i = 0; i < (0 + _salts.length); i = UntangledMath.uncheckedInc(i)) {
            agreementIds[i] = keccak256(
                abi.encodePacked(_version, _debtors[i], _termsContractParameters[i], _salts[i])
            );
        }
        return agreementIds;
    }

    /*********************** */
    // EXTERNAL FUNCTIONS
    /*********************** */

    function getLoansValue(
        FillDebtOrderParam calldata fillDebtOrderParam
    ) public view returns (uint256, uint256[][] memory) {
        address poolAddress = fillDebtOrderParam.orderAddresses[uint8(FillingAddressesIndex.SECURITIZATION_POOL)];
        IPool pool = IPool(poolAddress);
        require(fillDebtOrderParam.termsContractParameters.length > 0, 'LoanKernel: Invalid Term Contract params');

        uint256[] memory salts = _saltFromOrderValues(
            fillDebtOrderParam.orderValues,
            fillDebtOrderParam.termsContractParameters.length
        );
        LoanOrder memory debtOrder = _getLoanOrder(
            _debtorsFromOrderAddresses(
                fillDebtOrderParam.orderAddresses,
                fillDebtOrderParam.termsContractParameters.length
            ),
            fillDebtOrderParam.orderAddresses,
            fillDebtOrderParam.orderValues,
            fillDebtOrderParam.termsContractParameters,
            salts
        );

        uint x = 0;
        uint256 expectedAssetsValue = 0;
        uint256[][] memory expectedAssetValues = new uint256[][](fillDebtOrderParam.latInfo.length);

        for (uint i = 0; i < fillDebtOrderParam.latInfo.length; i = UntangledMath.uncheckedInc(i)) {
            DataTypes.LoanEntry[] memory loans = new DataTypes.LoanEntry[](
                fillDebtOrderParam.latInfo[i].tokenIds.length
            );

            for (uint j = 0; j < fillDebtOrderParam.latInfo[i].tokenIds.length; j = UntangledMath.uncheckedInc(j)) {
                require(
                    debtOrder.issuance.agreementIds[x] == bytes32(fillDebtOrderParam.latInfo[i].tokenIds[j]),
                    'LoanKernel: Invalid LAT Token Id'
                );

                DataTypes.LoanEntry memory newLoan = DataTypes.LoanEntry({
                    debtor: debtOrder.issuance.debtors[x],
                    principalTokenAddress: debtOrder.principalTokenAddress,
                    termsParam: fillDebtOrderParam.termsContractParameters[x],
                    salt: salts[x],
                    issuanceBlockTimestamp: block.timestamp,
                    expirationTimestamp: debtOrder.expirationTimestampInSecs[x],
                    assetPurpose: Configuration.ASSET_PURPOSE(debtOrder.assetPurpose),
                    riskScore: debtOrder.riskScores[x]
                });
                loans[j] = newLoan;

                x = UntangledMath.uncheckedInc(x);
            }
            (uint256 expectedLoansValue, uint256[] memory expectedLoanValues) = pool.getLoansValue(
                fillDebtOrderParam.latInfo[i].tokenIds,
                loans
            );
            expectedAssetsValue += expectedLoansValue;
            expectedAssetValues[i] = expectedLoanValues;
        }

        return (expectedAssetsValue, expectedAssetValues);
    }

    /**
     * Filling new Debt Order
     * Notice:
     * - All Debt Order must to have same:
     *   + TermContract
     *   + Creditor Fee
     *   + Debtor Fee
     */
    function fillDebtOrder(
        FillDebtOrderParam calldata fillDebtOrderParam
    ) external whenNotPaused nonReentrant validFillingOrderAddresses(fillDebtOrderParam.orderAddresses) {
        address poolAddress = fillDebtOrderParam.orderAddresses[uint8(FillingAddressesIndex.SECURITIZATION_POOL)];
        IPool pool = IPool(poolAddress);
        require(fillDebtOrderParam.termsContractParameters.length > 0, 'LoanKernel: Invalid Term Contract params');

        uint256[] memory salts = _saltFromOrderValues(
            fillDebtOrderParam.orderValues,
            fillDebtOrderParam.termsContractParameters.length
        );
        LoanOrder memory debtOrder = _getLoanOrder(
            _debtorsFromOrderAddresses(
                fillDebtOrderParam.orderAddresses,
                fillDebtOrderParam.termsContractParameters.length
            ),
            fillDebtOrderParam.orderAddresses,
            fillDebtOrderParam.orderValues,
            fillDebtOrderParam.termsContractParameters,
            salts
        );

        uint x = 0;
        uint256 expectedAssetsValue = 0;

        // Mint to pool
        for (uint i = 0; i < fillDebtOrderParam.latInfo.length; i = UntangledMath.uncheckedInc(i)) {
            registry.getLoanAssetToken().safeMint(poolAddress, fillDebtOrderParam.latInfo[i]);
            DataTypes.LoanEntry[] memory loans = new DataTypes.LoanEntry[](
                fillDebtOrderParam.latInfo[i].tokenIds.length
            );

            for (uint j = 0; j < fillDebtOrderParam.latInfo[i].tokenIds.length; j = UntangledMath.uncheckedInc(j)) {
                require(
                    debtOrder.issuance.agreementIds[x] == bytes32(fillDebtOrderParam.latInfo[i].tokenIds[j]),
                    'LoanKernel: Invalid LAT Token Id'
                );

                loans[j] = DataTypes.LoanEntry({
                    debtor: debtOrder.issuance.debtors[x],
                    principalTokenAddress: debtOrder.principalTokenAddress,
                    termsParam: fillDebtOrderParam.termsContractParameters[x],
                    salt: salts[x],
                    issuanceBlockTimestamp: block.timestamp,
                    expirationTimestamp: debtOrder.expirationTimestampInSecs[x],
                    assetPurpose: Configuration.ASSET_PURPOSE(debtOrder.assetPurpose),
                    riskScore: debtOrder.riskScores[x]
                });

                x = UntangledMath.uncheckedInc(x);
            }

            expectedAssetsValue += pool.collectAssets(fillDebtOrderParam.latInfo[i].tokenIds, loans);
        }

        // Start collect asset checkpoint and withdraw
        pool.withdraw(_msgSender(), expectedAssetsValue);

        // rebase
        pool.rebase();
        require(pool.isMinFirstLossValid(), 'LoanKernel: Exceeds MinFirstLoss');

        emit DrawdownAsset(poolAddress, expectedAssetsValue);
    }

    /// @inheritdoc ILoanKernel
    function repayInBatch(
        bytes32[] calldata agreementIds,
        uint256[] calldata amounts,
        address tokenAddress
    ) external override whenNotPaused nonReentrant returns (bool) {
        uint256 agreementIdsLength = agreementIds.length;
        require(agreementIdsLength == amounts.length, 'LoanRepaymentRouter: Invalid length');
        require(tokenAddress != address(0), 'LoanRepaymentRouter: Token address must different with NULL');

        uint256[] memory nftIds = new uint256[](agreementIdsLength);

        // check all the loans must have the same owner
        address poolAddress = registry.getLoanAssetToken().ownerOf(uint256(agreementIds[0]));
        IPool pool = IPool(poolAddress);

        require(poolAddress != address(0), 'LoanRepaymentRouter: Invalid repayment request');
        require(pool.underlyingCurrency() == tokenAddress, 'LoanRepaymentRouter: currency mismatch');

        nftIds[0] = uint256(agreementIds[0]);

        if (agreementIdsLength > 1) {
            for (uint256 i = 1; i < agreementIdsLength; i++) {
                nftIds[i] = uint256(agreementIds[i]);
                require(
                    registry.getLoanAssetToken().ownerOf(nftIds[i]) == poolAddress,
                    'LoanRepaymentRouter: Invalid repayment request'
                );
            }
        }

        require(
            _doRepay(pool, nftIds, _msgSender(), amounts, tokenAddress),
            'LoanRepaymentRouter: Repayment has failed'
        );

        // rebase
        pool.rebase();

        emit BatchAssetRepay(agreementIds, _msgSender(), amounts, tokenAddress);
        return true;
    }
}
