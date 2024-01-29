// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.10;

library UnpackLoanParamtersLib {
    struct InterestParams {
        uint256 principalAmount;
        uint256 termStartUnixTimestamp;
        uint256 termEndUnixTimestamp;
        AmortizationUnitType amortizationUnitType;
        uint256 termLengthInAmortizationUnits;
        // interest rates can, at a maximum, have 4 decimal places of precision.
        uint256 interestRate;
    }

    enum AmortizationUnitType {
        MINUTES, // 0 - since 1.0.13
        HOURS, // 1
        DAYS, // 2
        WEEKS, // 3
        MONTHS, // 4
        YEARS // 5
    }

    /**
     *
     * Notice: * uint256 (a) reinterprets a as 256-bit unsigned integer. As long as 256 bit = 32 bytes
     */
    function _bitShiftRight(bytes32 value, uint256 amount) internal pure returns (uint256) {
        return uint256(value) / 2 ** amount;
    }

    /**
     * Unpack parameters from packed bytes32 data
     */
    function _unpackLoanTermsParametersFromBytes(
        bytes32 parameters
    )
        internal
        pure
        returns (
            uint256 _principalAmount,
            uint256 _interestRate,
            uint256 _amortizationUnitType,
            uint256 _termLengthInAmortizationUnits,
            uint256 _gracePeriodInDays
        )
    {
        // The subsequent 12 bytes of the parameters encode the PRINCIPAL AMOUNT.
        bytes32 principalAmountShifted = parameters &
            0x00ffffffffffffffffffffffff00000000000000000000000000000000000000;
        // The subsequent 3 bytes of the parameters encode the INTEREST RATE.
        bytes32 interestRateShifted = parameters & 0x00000000000000000000000000ffffff00000000000000000000000000000000;
        // The subsequent 4 bits (half byte) encode the AMORTIZATION UNIT TYPE code.
        bytes32 amortizationUnitTypeShifted = parameters &
            0x00000000000000000000000000000000f0000000000000000000000000000000;
        // The subsequent 12 bytes encode the term length, as denominated in
        // the encoded amortization unit.
        bytes32 termLengthInAmortizationUnitsShifted = parameters &
            0x000000000000000000000000000000000ffffffffffffffffffffffff0000000;

        bytes32 gracePeriodInDaysShifted = parameters &
            0x000000000000000000000000000000000000000000000000000000000ff00000;

        return (
            _bitShiftRight(principalAmountShifted, 152),
            _bitShiftRight(interestRateShifted, 128),
            _bitShiftRight(amortizationUnitTypeShifted, 124),
            _bitShiftRight(termLengthInAmortizationUnitsShifted, 28),
            _bitShiftRight(gracePeriodInDaysShifted, 20)
        );
    }

    /**
     * Unpack data from hex string which including informations about Loan
     */
    function unpackParametersFromBytes(
        bytes32 parameters
    )
        internal
        pure
        returns (
            uint256 _principalAmount,
            uint256 _interestRate,
            uint256 _amortizationUnitType,
            uint256 _termLengthInAmortizationUnits,
            uint256 _gracePeriodInDays
        )
    {
        return _unpackLoanTermsParametersFromBytes(parameters);
    }
}
