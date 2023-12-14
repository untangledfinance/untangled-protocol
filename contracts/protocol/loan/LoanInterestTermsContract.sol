// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '../../base/UntangledBase.sol';
import '../../interfaces/ILoanInterestTermsContract.sol';
import '../../libraries/UnpackLoanParamtersLib.sol';
import '../../libraries/UntangledMath.sol';
import '../../libraries/ConfigHelper.sol';

/// @title LoanKernel
/// @author Untangled Team
/// @dev Upload loan and conclude loan
contract LoanInterestTermsContract is UntangledBase, ILoanInterestTermsContract {
    using ConfigHelper for Registry;

    uint256 public constant NUM_AMORTIZATION_UNIT_TYPES = 6;

    /// @dev Represents the number of days in a year
    uint256 public constant YEAR_LENGTH_IN_DAYS = 365;
    // All time units in seconds
    /// @dev Represents the number of seconds in a minute
    uint256 public constant MINUTE_LENGTH_IN_SECONDS = 60;
    uint256 public constant HOUR_LENGTH_IN_SECONDS = MINUTE_LENGTH_IN_SECONDS * 60;
    uint256 public constant DAY_LENGTH_IN_SECONDS = HOUR_LENGTH_IN_SECONDS * 24;
    uint256 public constant WEEK_LENGTH_IN_SECONDS = DAY_LENGTH_IN_SECONDS * 7;
    uint256 public constant MONTH_LENGTH_IN_SECONDS = DAY_LENGTH_IN_SECONDS * 30;
    uint256 public constant YEAR_LENGTH_IN_SECONDS = DAY_LENGTH_IN_SECONDS * YEAR_LENGTH_IN_DAYS;

    // To convert an encoded interest rate into its equivalent in percents,
    // divide it by INTEREST_RATE_SCALING_FACTOR_PERCENT -- e.g.
    //     10,000 => 1% interest rate
    uint256 public constant INTEREST_RATE_SCALING_FACTOR_PERCENT = 10 ** 4;

    // To convert an encoded interest rate into its equivalent multiplier
    // (for purposes of calculating total interest), divide it by INTEREST_RATE_SCALING_FACTOR_PERCENT -- e.g.
    //     10,000 => 0.01 interest multiplier
    uint256 public constant INTEREST_RATE_SCALING_FACTOR_MULTIPLIER = INTEREST_RATE_SCALING_FACTOR_PERCENT * 100;

    function initialize(Registry _registry) public initializer {
        __UntangledBase__init_unchained(_msgSender());

        registry = _registry;
    }

    //////////////////////////////
    // EVENTS                 ///
    ////////////////////////////
    event LogInterestTermStart(
        bytes32 indexed agreementId,
        address indexed principalToken,
        uint256 principalAmount,
        uint256 interestRate,
        uint256 indexed amortizationUnitType,
        uint256 termLengthInAmortizationUnits
    );

    event LogRegisterRepayment(
        bytes32 agreementId,
        address payer,
        address beneficiary,
        uint256 unitsOfRepayment,
        address tokenAddress
    );

    event LogRegisterCompleteTerm(bytes32 agreementId);

    //////////////////////////////
    // MODIFIERS              ///
    ////////////////////////////
    modifier onlyKernel() {
        require(_msgSender() == address(registry.getLoanKernel()), 'LoanInterestTermsContract: Only for LoanKernel.');
        _;
    }

    modifier onlyRouter() {
        require(
            _msgSender() == address(registry.getLoanRepaymentRouter()),
            'LoanInterestTermsContract: Only for Repayment Router.'
        );
        _;
    }

    // modifier onlyHaventStartedLoan(bytes32 agreementId) {
    //     require(!startedLoan[agreementId], 'LoanInterestTermsContract: Loan has started!');
    //     _;
    // }

    function _addRepaidPrincipalAmount(bytes32 agreementId, uint256 repaidAmount) private {
        repaidPrincipalAmounts[agreementId] += repaidAmount;
    }

    function _addRepaidInterestAmount(bytes32 agreementId, uint256 repaidAmount) private {
        repaidInterestAmounts[agreementId] += repaidAmount;
    }

    function _setCompletedRepayment(bytes32 agreementId) private {
        completedRepayment[agreementId] = true;
    }

    // Register to start Loan term for batch of agreement Ids
    /// @inheritdoc ILoanInterestTermsContract
    function registerTermStart(
        uint256[] calldata agreementIds
    ) public override whenNotPaused onlyKernel returns (bool) {
        for (uint i = 0; i < agreementIds.length; i = UntangledMath.uncheckedInc(i)) {
            require(!startedLoan[bytes32(agreementIds[i])], 'LoanInterestTermsContract: Loan has started!');
            startedLoan[bytes32(agreementIds[i])] = true;
        }

        return true;
    }

    /// @inheritdoc ILoanInterestTermsContract
    function registerConcludeLoan(bytes32 agreementId) external override whenNotPaused nonReentrant returns (bool) {
        registry.requireLoanKernel(_msgSender());
        registry.getLoanRegistry().setCompletedLoan(agreementId);

        emit LogRegisterCompleteTerm(agreementId);
        return true;
    }

    /// When called, the registerRepayment function records the debtor's
    ///  repayment, as well as any auxiliary metadata needed by the contract
    ///  to determine ex post facto the value repaid (e.g. current USD
    ///  exchange rate)
    /// @param  agreementId bytes32. The agreement id (issuance hash) of the debt agreement to which this pertains.
    /// @param  payer address. The address of the payer.
    /// @param  beneficiary address. The address of the payment's beneficiary.
    /// @param  unitsOfRepayment uint. The units-of-value repaid in the transaction.
    /// @param  tokenAddress address. The address of the token with which the repayment transaction was executed.
    /// @inheritdoc ILoanInterestTermsContract
    function registerRepayment(
        bytes32 agreementId,
        address payer,
        address beneficiary,
        uint256 unitsOfRepayment,
        address tokenAddress
    ) public override onlyRouter returns (uint256 remains) {
        ILoanRegistry loanRegistry = registry.getLoanRegistry();
        require(
            tokenAddress == loanRegistry.getPrincipalTokenAddress(agreementId),
            'LoanTermsContract: Invalid token for repayment.'
        );
        require(!loanRegistry.completedLoans(agreementId), 'LoanTermsContract: Completed Loan.');
        require(startedLoan[agreementId], 'LoanTermsContract: Loan has not started yet.');

        uint256 currentTimestamp = block.timestamp;

        uint256 expectedPrincipal;
        uint256 expectedInterest;
        // query total outstanding amounts
        (expectedPrincipal, expectedInterest) = getExpectedRepaymentValues(agreementId, currentTimestamp);
        // TODO: Currently only allow Debtor to repay with amount >= expectedInterest of that time
        // Because, we haven't made any mechanism to manage outstanding interest amounts in the case when Debtor
        // repaid with amount < expectedInterest (at that moment)
        require(unitsOfRepayment >= expectedInterest, 'LoanTermsContract: Expected interest amount is minimum.');

        // exceed expectation, Debtor can pay all at once
        if (unitsOfRepayment >= expectedPrincipal + expectedInterest) {
            _setCompletedRepayment(agreementId);
            _addRepaidInterestAmount(agreementId, expectedInterest);
            _addRepaidPrincipalAmount(agreementId, expectedPrincipal);
            // put the remain to interest
            remains = unitsOfRepayment - (expectedPrincipal + expectedInterest);
        } else {
            // if currently Debtor no need to repay for interest
            if (expectedInterest == 0) {
                _addRepaidPrincipalAmount(agreementId, unitsOfRepayment);
            } else {
                // if expectedInterest > 0 ( & unitsOfRepayment >= expectedInterest)
                _addRepaidInterestAmount(agreementId, expectedInterest);
                if (unitsOfRepayment - expectedInterest > 0) {
                    // Debtor is not able to fulfill the expectedPrincipal as we already validated from first IF statement
                    // -> there is no remains for adding to repaidInterestAmount
                    _addRepaidPrincipalAmount(agreementId, unitsOfRepayment - expectedInterest);
                }
            }
        }

        // Update Debt registry record
        loanRegistry.updateLastRepaymentTimestamp(agreementId, currentTimestamp);
        // loanRegistry.selfEvaluateCollateralRatio(agreementId);

        // Emit new event
        emit LogRegisterRepayment(agreementId, payer, beneficiary, unitsOfRepayment, tokenAddress);

        return remains;
    }

    /// @inheritdoc ILoanInterestTermsContract
    function getValueRepaidToDate(bytes32 agreementId) public view override returns (uint256, uint256) {
        return (repaidPrincipalAmounts[agreementId], repaidInterestAmounts[agreementId]);
    }

    /// @inheritdoc ILoanInterestTermsContract
    function isCompletedRepayments(bytes32[] memory agreementIds) public view override returns (bool[] memory) {
        bool[] memory result = new bool[](agreementIds.length);
        uint256 aagreementIdsLength = agreementIds.length;
        for (uint256 i = 0; i < aagreementIdsLength; i = UntangledMath.uncheckedInc(i)) {
            result[i] = completedRepayment[agreementIds[i]];
        }
        return result;
    }

    /**
     * Expected repayment value with Amortization of Interest and Principal
     * (AMORTIZATION) - will be used for repayment from Debtor
     */
    /// @inheritdoc ILoanInterestTermsContract
    function getExpectedRepaymentValues(
        bytes32 agreementId,
        uint256 timestamp
    ) public view override returns (uint256 expectedPrincipal, uint256 expectedInterest) {
        UnpackLoanParamtersLib.InterestParams memory params = unpackParamsForAgreementID(agreementId);

        ILoanRegistry loanRegistry = registry.getLoanRegistry();

        uint256 repaidPrincipalAmount = repaidPrincipalAmounts[agreementId];
        uint256 repaidInterestAmount = repaidInterestAmounts[agreementId];
        uint256 lastRepaymentTimestamp = loanRegistry.getLastRepaymentTimestamp(agreementId);

        bool isManualInterestLoan = loanRegistry.manualInterestLoan(agreementId);
        uint256 manualInterestAmountLoan = 0;
        if (isManualInterestLoan) {
            manualInterestAmountLoan = loanRegistry.manualInterestAmountLoan(agreementId);
        }

        (expectedPrincipal, expectedInterest) = _getExpectedRepaymentValuesToTimestamp(
            params,
            lastRepaymentTimestamp,
            timestamp,
            repaidPrincipalAmount,
            repaidInterestAmount,
            isManualInterestLoan,
            manualInterestAmountLoan
        );
    }

    /// @inheritdoc ILoanInterestTermsContract
    function getMultiExpectedRepaymentValues(
        bytes32[] memory agreementIds,
        uint256 timestamp
    ) public view override returns (uint256[] memory, uint256[] memory) {
        uint256[] memory expectedPrincipals = new uint256[](agreementIds.length);
        uint256[] memory expectedInterests = new uint256[](agreementIds.length);
        uint256 agreementIdsLength = agreementIds.length;
        for (uint256 i = 0; i < agreementIdsLength; i = UntangledMath.uncheckedInc(i)) {
            (uint256 expectedPrincipal, uint256 expectedInterest) = getExpectedRepaymentValues(
                agreementIds[i],
                timestamp
            );
            expectedPrincipals[i] = expectedPrincipal;
            expectedInterests[i] = expectedInterest;
        }
        return (expectedPrincipals, expectedInterests);
    }

    /// @inheritdoc ILoanInterestTermsContract
    function getInterestRate(bytes32 agreementId) public view override returns (uint256) {
        return unpackParamsForAgreementID(agreementId).interestRate;
    }

    /// @param amortizationUnitType AmortizationUnitType enum
    /// @return the corresponding length of the unit in seconds
    function _getAmortizationUnitLengthInSeconds(
        UnpackLoanParamtersLib.AmortizationUnitType amortizationUnitType
    ) private pure returns (uint256) {
        if (amortizationUnitType == UnpackLoanParamtersLib.AmortizationUnitType.MINUTES) {
            return MINUTE_LENGTH_IN_SECONDS;
        } else if (amortizationUnitType == UnpackLoanParamtersLib.AmortizationUnitType.HOURS) {
            return HOUR_LENGTH_IN_SECONDS;
        } else if (amortizationUnitType == UnpackLoanParamtersLib.AmortizationUnitType.DAYS) {
            return DAY_LENGTH_IN_SECONDS;
        } else if (amortizationUnitType == UnpackLoanParamtersLib.AmortizationUnitType.WEEKS) {
            return WEEK_LENGTH_IN_SECONDS;
        } else if (amortizationUnitType == UnpackLoanParamtersLib.AmortizationUnitType.MONTHS) {
            return MONTH_LENGTH_IN_SECONDS;
        } else if (amortizationUnitType == UnpackLoanParamtersLib.AmortizationUnitType.YEARS) {
            return YEAR_LENGTH_IN_SECONDS;
        } else {
            revert('Unknown amortization unit type.');
        }
    }

    /**
     *   Get parameters by Agreement ID (commitment hash)
     */
    function unpackParamsForAgreementID(
        bytes32 agreementId
    ) public view override returns (UnpackLoanParamtersLib.InterestParams memory params) {
        bytes32 parameters;
        uint256 issuanceBlockTimestamp = 0;
        ILoanRegistry loanRegistry = registry.getLoanRegistry();
        issuanceBlockTimestamp = loanRegistry.getIssuanceBlockTimestamp(agreementId);
        parameters = loanRegistry.getTermsContractParameters(agreementId);
        // The principal amount denominated in the aforementioned token.
        uint256 principalAmount;
        // The interest rate accrued per amortization unit.
        uint256 interestRate;
        // The amortization unit in which the repayments installments schedule is defined.
        uint256 rawAmortizationUnitType;
        // The debt's entire term's length, denominated in the aforementioned amortization units
        uint256 termLengthInAmortizationUnits;
        uint256 gracePeriodInDays;

        (
            principalAmount,
            interestRate,
            rawAmortizationUnitType,
            termLengthInAmortizationUnits,
            gracePeriodInDays
        ) = UnpackLoanParamtersLib.unpackParametersFromBytes(parameters);

        UnpackLoanParamtersLib.AmortizationUnitType amortizationUnitType = UnpackLoanParamtersLib.AmortizationUnitType(
            rawAmortizationUnitType
        );

        // Calculate term length base on Amortization Unit and number
        uint256 termLengthInSeconds = termLengthInAmortizationUnits *
            _getAmortizationUnitLengthInSeconds(amortizationUnitType);

        return
            UnpackLoanParamtersLib.InterestParams({
                principalAmount: principalAmount,
                interestRate: interestRate,
                termStartUnixTimestamp: issuanceBlockTimestamp,
                termEndUnixTimestamp: termLengthInSeconds + issuanceBlockTimestamp,
                amortizationUnitType: amortizationUnitType,
                termLengthInAmortizationUnits: termLengthInAmortizationUnits
            });
    }

    // Calculate interest amount for a duration with specific Principal amount
    function _calculateInterestForDuration(
        uint256 _principalAmount,
        uint256 _interestRate,
        uint256 _durationLengthInSec
    ) private pure returns (uint256) {
        // x = 10 ** 27 + IR * (10 ** 27 / 10 ** 4 / 100) / YLIR
        uint256 x = UntangledMath.ONE +
            ((_interestRate * UntangledMath.ONE) / INTEREST_RATE_SCALING_FACTOR_PERCENT / 100) /
            YEAR_LENGTH_IN_SECONDS;

        return
            (_principalAmount * UntangledMath.rpow(x, _durationLengthInSec, UntangledMath.ONE)) /
            UntangledMath.ONE -
            _principalAmount;
    }

    /**
     * Calculate values which Debtor need to pay to conclude current Loan
     */
    /// @dev calculates the expected principal and interest amounts that the debtor needs to pay to conclude the current loan
    /// It takes into account the repayment history, timestamps, and additional parameters specific to manual interest loans
    function _getExpectedRepaymentValuesToTimestamp(
        UnpackLoanParamtersLib.InterestParams memory _params,
        uint256 _lastRepaymentTimestamp, // timestamp of last repayment from debtor
        uint256 _timestamp,
        uint256 repaidPrincipalAmount,
        uint256 repaidInterestAmount,
        bool isManualInterestLoan,
        uint256 manualInterestAmountLoan
    ) private pure returns (uint256 expectedPrinciapal, uint256 expectedInterest) {
        uint256 outstandingPrincipal = _params.principalAmount - repaidPrincipalAmount;

        expectedPrinciapal = outstandingPrincipal;

        if (isManualInterestLoan) {
            expectedInterest = manualInterestAmountLoan;
        } else {
            expectedInterest = _calculateInterestAmountToTimestamp(
                _params.principalAmount,
                outstandingPrincipal,
                repaidInterestAmount,
                _params.interestRate,
                _params.termStartUnixTimestamp,
                _params.termEndUnixTimestamp,
                _lastRepaymentTimestamp,
                _timestamp
            );
        }
    }

    // Calculate interest amount Debtor need to pay until current date
    function _calculateInterestAmountToTimestamp(
        uint256 _principalAmount,
        uint256 _currentPrincipalAmount,
        uint256 _paidInterestAmount,
        uint256 _annualInterestRate,
        uint256 _startTermTimestamp,
        uint256 _endTermTimestamp,
        uint256 _lastRepayTimestamp,
        uint256 _timestamp
    ) private pure returns (uint256) {
        if (_timestamp <= _startTermTimestamp) {
            return 0;
        }
        uint256 interest = 0;

        // dangerous-strict-equalities
        uint256 elapseTimeFromLastRepay = _timestamp < _lastRepayTimestamp ? 0 : (_timestamp - _lastRepayTimestamp);
        uint256 elapseTimeFromStart = _timestamp < _startTermTimestamp ? 0 : (_timestamp - _startTermTimestamp);

        // If still within the term length
        if (_timestamp < _endTermTimestamp) {
            // Have just made new repayment
            if (_timestamp <= _lastRepayTimestamp && _paidInterestAmount > 0) {
                interest = 0;
            } else {
                if (_paidInterestAmount > 0) {
                    // Has made at least 1 repayment
                    interest = _calculateInterestForDuration(
                        _currentPrincipalAmount,
                        _annualInterestRate,
                        elapseTimeFromLastRepay
                    );
                } else {
                    // Haven't made any repayment
                    interest = _calculateInterestForDuration(
                        _principalAmount,
                        _annualInterestRate,
                        elapseTimeFromStart
                    );
                }
            }
        } else {
            // If debtor has made at least 1 repayment
            if (_paidInterestAmount > 0) {
                interest = _calculateInterestForDuration(
                    _currentPrincipalAmount,
                    _annualInterestRate,
                    elapseTimeFromLastRepay
                );
            } else {
                interest = _calculateInterestForDuration(_principalAmount, _annualInterestRate, elapseTimeFromStart);
            }
        }

        return interest;
    }

    uint256[50] private __gap;
}
