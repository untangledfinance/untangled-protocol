// SPDX-License-Identifier: AGPL-3.0-or-later

// https://github.com/centrifuge/tinlake
// src/borrower/feed/navfeed.sol -- Tinlake NAV Feed

// Copyright (C) 2022 Centrifuge
// Copyright (C) 2023 Untangled.Finance
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General internal License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General internal License for more details.
//
// You should have received a copy of the GNU Affero General internal License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity 0.8.19;
import '../UnpackLoanParamtersLib.sol';
import {DataTypes, ONE_HUNDRED_PERCENT,ONE,WRITEOFF_RATE_GROUP_START} from '../DataTypes.sol';
import {Math} from '../Math.sol';
import {Discounting} from '../Discounting.sol';

/**
 * @title Untangled's SecuritizaionPoolNAV contract
 * @notice Main entry point for senior LPs (a.k.a. capital providers)
 *  Automatically invests across borrower pools using an adjustable strategy.
 * @author Untangled Team
 */
library GenericLogic {

    event SetRate(bytes32 indexed loan, uint256 rate);
    event ChangeRate(bytes32 indexed loan, uint256 newRate);

    /** GETTER */
    /// @notice getter function for the maturityDate
    /// @param nft_ the id of the nft based on the hash of registry and tokenId
    /// @return maturityDate_ the maturityDate of the nft
    function maturityDate(
        DataTypes.Storage storage _poolStorage,
        bytes32 nft_
    ) internal view returns (uint256 maturityDate_) {
        return uint256(_poolStorage.details[nft_].maturityDate);
    }

    /// @notice getter function for the risk group
    /// @param nft_ the id of the nft based on the hash of registry and tokenId
    /// @return risk_ the risk group of the nft

    function risk(DataTypes.Storage storage _poolStorage, bytes32 nft_) internal view returns (uint256 risk_) {
        return uint256(_poolStorage.details[nft_].risk);
    }

    /// @notice getter function for the nft value
    /// @param nft_ the id of the nft based on the hash of registry and tokenId
    /// @return nftValue_ the value of the nft

    /// @notice getter function for the future value
    /// @param nft_ the id of the nft based on the hash of registry and tokenId
    /// @return fv_ future value of the loan
    function futureValue(DataTypes.Storage storage _poolStorage, bytes32 nft_) internal view returns (uint256 fv_) {
        return uint256(_poolStorage.details[nft_].futureValue);
    }

    // function discountRate() internal view  returns (uint256) {
    //     return uint256(_getStorage().discountRate);
    // }

    /// @notice getter function for the recovery rate PD
    /// @param riskID id of a risk group
    /// @return recoveryRatePD_ recovery rate PD of the risk group
    function recoveryRatePD(
        DataTypes.RiskScore[] storage riskScores,
        uint256 riskID,
        uint256 termLength
    ) internal view returns (uint256 recoveryRatePD_) {
        DataTypes.RiskScore memory riskParam = getRiskScoreByIdx(riskScores, riskID);
        return
            Math.ONE -
            (Math.ONE * riskParam.probabilityOfDefault * riskParam.lossGivenDefault * termLength) /
            (ONE_HUNDRED_PERCENT * ONE_HUNDRED_PERCENT * 365 days);
    }

    /// @notice getter function for the borrowed amount
    /// @param loan id of a loan
    /// @return borrowed_ borrowed amount of the loan
    function borrowed(DataTypes.Storage storage _poolStorage, uint256 loan) internal view returns (uint256 borrowed_) {
        return uint256(_poolStorage.loanDetails[loan].borrowed);
    }

    /** UTILITY FUNCTION */
    // TODO have to use modifier in main contract
    function getRiskScoreByIdx(
        DataTypes.RiskScore[] storage riskScores,
        uint256 idx
    ) internal view returns (DataTypes.RiskScore memory) {
        if (idx == 0 || riskScores.length == 0) {
            // Default risk score
            return
                DataTypes.RiskScore({
                    daysPastDue: 0,
                    advanceRate: 1000000,
                    penaltyRate: 0,
                    interestRate: 0,
                    probabilityOfDefault: 0,
                    lossGivenDefault: 0,
                    writeOffAfterGracePeriod: 0,
                    gracePeriod: 0,
                    collectionPeriod: 0,
                    writeOffAfterCollectionPeriod: 0,
                    discountRate: 0
                });
        }
        // Because risk score upload = risk score index onchain + 1
        idx = idx - 1;
        return riskScores[idx];
    }

    /// @notice converts a uint256 to uint128
    /// @param value the value to be converted
    /// @return converted value to uint128
    function toUint128(uint256 value) internal pure returns (uint128 converted) {
        require(value <= type(uint128).max, "SafeCast: value doesn't fit in 128 bits");
        return uint128(value);
    }

    // TODO have to use modifier in main contract

    /// @notice returns if a loan is written off
    /// @param loan the id of the loan
    function isLoanWrittenOff(DataTypes.Storage storage _poolStorage, uint256 loan) internal view returns (bool) {
        return _poolStorage.loanRates[loan] >= WRITEOFF_RATE_GROUP_START;
    }

    /// @notice calculates and returns the current NAV
    /// @return nav_ current NAV
    function currentNAV(DataTypes.Storage storage _poolStorage) internal view returns (uint256 nav_) {
        (uint256 totalDiscount, uint256 overdue, uint256 writeOffs) = currentPVs(_poolStorage);
        return Math.safeAdd(totalDiscount, Math.safeAdd(overdue, writeOffs));
    }

    function currentNAVAsset(DataTypes.Storage storage _poolStorage, bytes32 tokenId) internal view returns (uint256) {
        (uint256 totalDiscount, uint256 overdue, uint256 writeOffs) = currentAV(_poolStorage, tokenId);
        return Math.safeAdd(totalDiscount, Math.safeAdd(overdue, writeOffs));
    }

    /// @notice calculates the present value of the loans together with overdue and written off loans
    /// @return totalDiscount the present value of the loans
    /// @return overdue the present value of the overdue loans
    /// @return writeOffs the present value of the written off loans
    function currentPVs(
        DataTypes.Storage storage _poolStorage
    ) internal view returns (uint256 totalDiscount, uint256 overdue, uint256 writeOffs) {
        uint256 latestDiscount;
        uint256 overdueLoans;
        uint256 discountRate;
        uint256 lastNAVUpdate;
        {
            latestDiscount = _poolStorage.latestDiscount;
            overdueLoans = _poolStorage.overdueLoans;
            discountRate = _poolStorage.discountRate;
            lastNAVUpdate = _poolStorage.lastNAVUpdate;
        }
        if (latestDiscount == 0) {
            // all loans are overdue or writtenOff
            return (0, overdueLoans, currentWriteOffs(_poolStorage));
        }

        uint256 errPV = 0;
        uint256 nnow = Discounting.uniqueDayTimestamp(block.timestamp);

        // find all new overdue loans since the last update
        // calculate the discount of the overdue loans which is needed
        // for the total discount calculation
        for (uint256 i = lastNAVUpdate; i < nnow; i = i + 1 days) {
            uint256 b = _poolStorage.buckets[i];
            if (b != 0) {
                errPV = Math.safeAdd(
                    errPV,
                    Math.rmul(b, Discounting.rpow(discountRate, Math.safeSub(nnow, i), Math.ONE))
                );
                overdue = Math.safeAdd(overdue, b);
            }
        }

        return (
            // calculate current totalDiscount based on the previous totalDiscount (optimized calculation)
            // the overdue loans are incorrectly in this new result with their current PV and need to be removed
            Discounting.secureSub(
                Math.rmul(latestDiscount, Discounting.rpow(discountRate, Math.safeSub(nnow, lastNAVUpdate), Math.ONE)),
                errPV
            ),
            // current overdue loans not written off
            Math.safeAdd(overdueLoans, overdue),
            // current write-offs loans
            currentWriteOffs(_poolStorage)
        );
    }

    function currentAV(
        DataTypes.Storage storage _poolStorage,
        bytes32 tokenId
    ) internal view returns (uint256 totalDiscount, uint256 overdue, uint256 writeOffs) {
        uint256 _currentWriteOffs = 0;
        uint256 discountRate;
        uint256 latestDiscountOfNavAssetsID;
        uint256 lastNAVUpdate;
        uint256 overdueLoansOfNavAssetsID;
        {
            discountRate = _poolStorage.discountRate;
            latestDiscountOfNavAssetsID = _poolStorage.latestDiscountOfNavAssets[tokenId];
            lastNAVUpdate = _poolStorage.lastNAVUpdate;
            overdueLoansOfNavAssetsID = _poolStorage.overdueLoansOfNavAssets[tokenId];
        }

        if (isLoanWrittenOff(_poolStorage, uint256(tokenId))) {
            uint256 writeOffGroupIndex = currentValidWriteOffGroup(_poolStorage, uint256(tokenId));
            _currentWriteOffs = Math.rmul(
                debt(_poolStorage, uint256(tokenId)),
                uint256(_poolStorage.writeOffGroups[writeOffGroupIndex].percentage)
            );
        }

        if (latestDiscountOfNavAssetsID == 0) {
            // all loans are overdue or writtenOff
            return (0, overdueLoansOfNavAssetsID, _currentWriteOffs);
        }

        uint256 errPV = 0;
        uint256 nnow = Discounting.uniqueDayTimestamp(block.timestamp);

        // loan is overdue since lastNAVUpdate
        uint256 mat = Discounting.uniqueDayTimestamp(maturityDate(_poolStorage, tokenId));
        if (mat >= lastNAVUpdate && mat < nnow) {
            uint256 b = futureValue(_poolStorage, tokenId);
            errPV = Math.rmul(b, Discounting.rpow(discountRate, Math.safeSub(nnow, mat), Math.ONE));
            overdue = b;
        }

        return (
            Discounting.secureSub(
                Math.rmul(
                    latestDiscountOfNavAssetsID,
                    Discounting.rpow(discountRate, Math.safeSub(nnow, lastNAVUpdate), Math.ONE)
                ),
                errPV
            ),
            Math.safeAdd(overdueLoansOfNavAssetsID, overdue),
            _currentWriteOffs
        );
    }

    /// @notice returns the sum of all write off loans
    /// @return sum of all write off loans
    function currentWriteOffs(DataTypes.Storage storage _poolStorage) internal view returns (uint256 sum) {
        for (uint256 i = 0; i < _poolStorage.writeOffGroups.length; i++) {
            // multiply writeOffGroupDebt with the writeOff rate

            sum = Math.safeAdd(
                sum,
                Math.rmul(
                    rateDebt(_poolStorage, WRITEOFF_RATE_GROUP_START + i),
                    uint256(_poolStorage.writeOffGroups[i].percentage)
                )
            );
        }
        return sum;
    }

    /// @notice calculates and returns the current NAV and updates the state
    /// @return nav_ current NAV
    function calcUpdateNAV(DataTypes.Storage storage _poolStorage) internal returns (uint256 nav_) {
        (uint256 totalDiscount, uint256 overdue, uint256 writeOffs) = currentPVs(_poolStorage);

        for (uint i = 0; i < _poolStorage.loanCount; ++i) {
            bytes32 _nftID = _poolStorage.loanToNFT[i];

            (uint256 td, uint256 ol, ) = currentAV(_poolStorage, _nftID);
            _poolStorage.overdueLoansOfNavAssets[_nftID] = ol;
            _poolStorage.latestDiscountOfNavAssets[_nftID] = td;
        }

        _poolStorage.overdueLoans = overdue;
        _poolStorage.latestDiscount = totalDiscount;

        _poolStorage.latestNAV = Math.safeAdd(Math.safeAdd(totalDiscount, overdue), writeOffs);
        _poolStorage.lastNAVUpdate = Discounting.uniqueDayTimestamp(block.timestamp);
        return _poolStorage.latestNAV;
    }

    /// @notice re-calculates the nav in a non-optimized way
    ///  the method is not updating the NAV to latest block.timestamp
    /// @return nav_ current NAV
    function reCalcNAV(DataTypes.Storage storage _poolStorage) internal returns (uint256 nav_) {
        // reCalcTotalDiscount
        /// @notice re-calculates the totalDiscount in a non-optimized way based on lastNAVUpdate
        /// @return latestDiscount_ returns the total discount of the active loans
        uint256 latestDiscount_ = 0;
        for (uint256 loanID = 1; loanID < _poolStorage.loanCount; loanID++) {
            bytes32 nftID_ = nftID(loanID);
            uint256 maturityDate_ = maturityDate(_poolStorage, nftID_);

            if (maturityDate_ < _poolStorage.lastNAVUpdate) {
                continue;
            }

            uint256 discountIncrease_ = Discounting.calcDiscount(
                _poolStorage.discountRate,
                futureValue(_poolStorage, nftID_),
                _poolStorage.lastNAVUpdate,
                maturityDate_
            );
            latestDiscount_ = Math.safeAdd(latestDiscount_, discountIncrease_);
            _poolStorage.latestDiscountOfNavAssets[nftID_] = discountIncrease_;
        }

        _poolStorage.latestNAV = Math.safeAdd(
            latestDiscount_,
            Math.safeSub(_poolStorage.latestNAV, _poolStorage.latestDiscount)
        );
        _poolStorage.latestDiscount = latestDiscount_;

        return _poolStorage.latestNAV;
    }

    /// @notice returns the nftID for the underlying collateral nft
    /// @param loan the loan id
    /// @return nftID_ the nftID of the loan
    function nftID(uint256 loan) internal pure returns (bytes32 nftID_) {
        return bytes32(loan);
    }

    /// @notice returns the current valid write off group of a loan
    /// @param loan the loan id
    /// @return writeOffGroup_ the current valid write off group of a loan
    function currentValidWriteOffGroup(
        DataTypes.Storage storage _poolStorage,
        uint256 loan
    ) internal view returns (uint256 writeOffGroup_) {
        bytes32 nftID_ = nftID(loan);
        uint256 maturityDate_ = maturityDate(_poolStorage, nftID_);
        uint256 nnow = Discounting.uniqueDayTimestamp(block.timestamp);

        DataTypes.NFTDetails memory nftDetail = getAsset(_poolStorage, nftID_);

        uint128 _loanRiskIndex = nftDetail.risk - 1;

        uint128 lastValidWriteOff = type(uint128).max;
        uint128 highestOverdueDays = 0;
        // it is not guaranteed that writeOff groups are sorted by overdue days
        for (uint128 i = 0; i < _poolStorage.writeOffGroups.length; i++) {
            uint128 overdueDays = _poolStorage.writeOffGroups[i].overdueDays;
            if (
                _poolStorage.writeOffGroups[i].riskIndex == _loanRiskIndex &&
                overdueDays >= highestOverdueDays &&
                nnow >= maturityDate_ + overdueDays * 1 days
            ) {
                lastValidWriteOff = i;
                highestOverdueDays = overdueDays;
            }
        }

        // returns type(uint128).max if no write-off group is valid for this loan
        return lastValidWriteOff;
    }

    function debt(DataTypes.Storage storage _poolStorage, uint256 loan) internal view returns (uint256 loanDebt) {
        uint256 rate_ = _poolStorage.loanRates[loan];
        uint256 chi_ = _poolStorage.rates[rate_].chi;
        uint256 penaltyChi_ = _poolStorage.rates[rate_].penaltyChi;
        if (block.timestamp >= _poolStorage.rates[rate_].lastUpdated) {
            chi_ = chargeInterest(
                _poolStorage.rates[rate_].chi,
                _poolStorage.rates[rate_].ratePerSecond,
                _poolStorage.rates[rate_].lastUpdated
            );
            penaltyChi_ = chargeInterest(
                _poolStorage.rates[rate_].penaltyChi,
                _poolStorage.rates[rate_].penaltyRatePerSecond,
                _poolStorage.rates[rate_].lastUpdated
            );
        }

        if (penaltyChi_ == 0) {
            return toAmount(chi_, _poolStorage.pie[loan]);
        } else {
            return toAmount(penaltyChi_, toAmount(chi_, _poolStorage.pie[loan]));
        }
    }

    function debtWithChi(
        DataTypes.Storage storage _poolStorage,
        uint256 loan,
        uint256 chi,
        uint256 penaltyChi
    ) internal view returns (uint256 loanDebt) {
        if (penaltyChi == 0) {
            return toAmount(chi, _poolStorage.pie[loan]);
        } else {
            return toAmount(penaltyChi, toAmount(chi, _poolStorage.pie[loan]));
        }
    }

    function chiAndPenaltyChi(
        DataTypes.Storage storage _poolStorage,
        uint256 loan
    ) internal view returns (uint256 chi, uint256 penaltyChi) {
        uint256 rate_ = _poolStorage.loanRates[loan];
        chi = _poolStorage.rates[rate_].chi;
        penaltyChi = _poolStorage.rates[rate_].penaltyChi;
    }

    function rateDebt(DataTypes.Storage storage _poolStorage, uint256 rate) internal view returns (uint256 totalDebt) {
        uint256 chi_ = _poolStorage.rates[rate].chi;
        uint256 penaltyChi_ = _poolStorage.rates[rate].penaltyChi;
        uint256 pie_ = _poolStorage.rates[rate].pie;

        if (block.timestamp >= _poolStorage.rates[rate].lastUpdated) {
            chi_ = chargeInterest(
                _poolStorage.rates[rate].chi,
                _poolStorage.rates[rate].ratePerSecond,
                _poolStorage.rates[rate].lastUpdated
            );
            penaltyChi_ = chargeInterest(
                _poolStorage.rates[rate].penaltyChi,
                _poolStorage.rates[rate].penaltyRatePerSecond,
                _poolStorage.rates[rate].lastUpdated
            );
        }

        if (penaltyChi_ == 0) {
            return toAmount(chi_, pie_);
        } else {
            return toAmount(penaltyChi_, toAmount(chi_, pie_));
        }
    }

    function setRate(DataTypes.Storage storage _poolStorage, uint256 loan, uint256 rate) internal {
        require(_poolStorage.pie[loan] == 0, 'non-zero-debt');
        // rate category has to be initiated
        require(_poolStorage.rates[rate].chi != 0, 'rate-group-not-set');
        _poolStorage.loanRates[loan] = rate;
        emit SetRate(nftID(loan), rate);
    }

    function changeRate(DataTypes.Storage storage _poolStorage, uint256 loan, uint256 newRate) internal {
        require(_poolStorage.rates[newRate].chi != 0, 'rate-group-not-set');
        if (newRate >= WRITEOFF_RATE_GROUP_START) {
            _poolStorage.rates[newRate].timeStartPenalty = uint48(block.timestamp);
        }
        uint256 currentRate = _poolStorage.loanRates[loan];
        drip(_poolStorage, currentRate);
        drip(_poolStorage, newRate);
        uint256 pie_ = _poolStorage.pie[loan];
        uint256 debt_ = toAmount(_poolStorage.rates[currentRate].chi, pie_);
        _poolStorage.rates[currentRate].pie = Math.safeSub(_poolStorage.rates[currentRate].pie, pie_);
        _poolStorage.pie[loan] = toPie(_poolStorage.rates[newRate].chi, debt_);
        _poolStorage.rates[newRate].pie = Math.safeAdd(_poolStorage.rates[newRate].pie, _poolStorage.pie[loan]);
        _poolStorage.loanRates[loan] = newRate;
        emit ChangeRate(nftID(loan), newRate);
    }

    function accrue(DataTypes.Storage storage _poolStorage, uint256 loan) internal {
        drip(_poolStorage, _poolStorage.loanRates[loan]);
    }

    function drip(DataTypes.Storage storage _poolStorage, uint256 rate) internal {
        if (block.timestamp >= _poolStorage.rates[rate].lastUpdated) {
            (uint256 chi, ) = compounding(
                _poolStorage.rates[rate].chi,
                _poolStorage.rates[rate].ratePerSecond,
                _poolStorage.rates[rate].lastUpdated,
                _poolStorage.rates[rate].pie
            );
            _poolStorage.rates[rate].chi = chi;
            if (
                _poolStorage.rates[rate].penaltyRatePerSecond != 0 &&
                _poolStorage.rates[rate].timeStartPenalty != 0 &&
                block.timestamp >= _poolStorage.rates[rate].timeStartPenalty
            ) {
                uint lastUpdated_ = _poolStorage.rates[rate].lastUpdated > _poolStorage.rates[rate].timeStartPenalty
                    ? _poolStorage.rates[rate].lastUpdated
                    : _poolStorage.rates[rate].timeStartPenalty;
                (uint256 penaltyChi, ) = compounding(
                    _poolStorage.rates[rate].penaltyChi,
                    _poolStorage.rates[rate].penaltyRatePerSecond,
                    lastUpdated_,
                    _poolStorage.rates[rate].pie
                );
                _poolStorage.rates[rate].penaltyChi = penaltyChi;
            }
            _poolStorage.rates[rate].lastUpdated = uint48(block.timestamp);
        }
    }

    /// Interest functions
    // @notice This function provides compounding in seconds
    // @param chi Accumulated interest rate over time
    // @param ratePerSecond Interest rate accumulation per second in RAD(10ˆ27)
    // @param lastUpdated When the interest rate was last updated
    // @param _pie Total sum of all amounts accumulating under one interest rate, divided by that rate
    // @return The new accumulated rate, as well as the difference between the debt calculated with the old and new accumulated rates.
    function compounding(uint chi, uint ratePerSecond, uint lastUpdated, uint _pie) internal view returns (uint, uint) {
        require(block.timestamp >= lastUpdated, 'tinlake-math/invalid-timestamp');
        require(chi != 0);
        // instead of a interestBearingAmount we use a accumulated interest rate index (chi)
        uint updatedChi = _chargeInterest(chi, ratePerSecond, lastUpdated, block.timestamp);
        return (updatedChi, Math.safeSub(Math.rmul(updatedChi, _pie), Math.rmul(chi, _pie)));
    }

    // @notice This function charge interest on a interestBearingAmount
    // @param interestBearingAmount is the interest bearing amount
    // @param ratePerSecond Interest rate accumulation per second in RAD(10ˆ27)
    // @param lastUpdated last time the interest has been charged
    // @return interestBearingAmount + interest
    function chargeInterest(
        uint interestBearingAmount,
        uint ratePerSecond,
        uint lastUpdated
    ) internal view returns (uint) {
        if (block.timestamp >= lastUpdated) {
            interestBearingAmount = _chargeInterest(interestBearingAmount, ratePerSecond, lastUpdated, block.timestamp);
        }
        return interestBearingAmount;
    }

    function _chargeInterest(
        uint interestBearingAmount,
        uint ratePerSecond,
        uint lastUpdated,
        uint current
    ) internal pure returns (uint) {
        return Math.rmul(Discounting.rpow(ratePerSecond, current - lastUpdated, Math.ONE), interestBearingAmount);
    }

    // convert pie to debt/savings amount
    function toAmount(uint chi, uint _pie) internal pure returns (uint) {
        return Math.rmul(_pie, chi);
    }

    // convert debt/savings amount to pie
    function toPie(uint chi, uint amount) internal pure returns (uint) {
        return Math.rdivup(amount, chi);
    }

    function getAsset(
        DataTypes.Storage storage _poolStorage,
        bytes32 agreementId
    ) internal view returns (DataTypes.NFTDetails memory) {
        return _poolStorage.details[agreementId];
    }

    /// @param amortizationUnitType AmortizationUnitType enum
    /// @return the corresponding length of the unit in seconds
    function _getAmortizationUnitLengthInSeconds(
        UnpackLoanParamtersLib.AmortizationUnitType amortizationUnitType
    ) private pure returns (uint256) {
        if (amortizationUnitType == UnpackLoanParamtersLib.AmortizationUnitType.MINUTES) {
            return 1 minutes;
        } else if (amortizationUnitType == UnpackLoanParamtersLib.AmortizationUnitType.HOURS) {
            return 1 hours;
        } else if (amortizationUnitType == UnpackLoanParamtersLib.AmortizationUnitType.DAYS) {
            return 1 days;
        } else if (amortizationUnitType == UnpackLoanParamtersLib.AmortizationUnitType.WEEKS) {
            return 7 days;
        } else if (amortizationUnitType == UnpackLoanParamtersLib.AmortizationUnitType.MONTHS) {
            return 30 days;
        } else if (amortizationUnitType == UnpackLoanParamtersLib.AmortizationUnitType.YEARS) {
            return 365 days;
        } else {
            revert('Unknown amortization unit type.');
        }
    }

    /**
     *   Get parameters by Agreement ID (commitment hash)
     */
    function unpackParamsForAgreementID(
        DataTypes.LoanEntry calldata loan
    ) internal pure returns (UnpackLoanParamtersLib.InterestParams memory params) {
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
        ) = UnpackLoanParamtersLib.unpackParametersFromBytes(loan.termsParam);

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
                termStartUnixTimestamp: loan.issuanceBlockTimestamp,
                termEndUnixTimestamp: termLengthInSeconds + loan.issuanceBlockTimestamp,
                amortizationUnitType: amortizationUnitType,
                termLengthInAmortizationUnits: termLengthInAmortizationUnits
            });
    }
}
