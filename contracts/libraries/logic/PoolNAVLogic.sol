// SPDX-License-Identifier: AGPL-3.0-or-later

// https://github.com/centrifuge/tinlake
// src/borrower/feed/navfeed.sol -- Tinlake NAV Feed

// Copyright (C) 2022 Centrifuge
// Copyright (C) 2023 Untangled.Finance
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity 0.8.19;
import '../UnpackLoanParamtersLib.sol';
import {DataTypes, ONE_HUNDRED_PERCENT, ONE, WRITEOFF_RATE_GROUP_START} from '../DataTypes.sol';
import {Math} from '../Math.sol';
import {Discounting} from '../Discounting.sol';
import {GenericLogic} from './GenericLogic.sol';
import 'hardhat/console.sol';

/**
 * @title Untangled's SecuritizaionPoolNAV contract
 * @notice Main entry point for senior LPs (a.k.a. capital providers)
 *  Automatically invests across borrower pools using an adjustable strategy.
 * @author Untangled Team
 */
library PoolNAVLogic {
    event IncreaseDebt(bytes32 indexed loan, uint256 currencyAmount);
    event DecreaseDebt(bytes32 indexed loan, uint256 currencyAmount);

    // events
    event SetLoanMaturity(bytes32 indexed loan, uint256 maturityDate_);
    event WriteOff(bytes32 indexed loan, uint256 indexed writeOffGroupsIndex, bool override_);
    event AddLoan(bytes32 indexed loan, uint256 principalAmount, DataTypes.NFTDetails nftdetails);
    event Repay(bytes32 indexed loan, uint256 currencyAmount);
    event UpdateAssetRiskScore(bytes32 loan, uint256 risk);

    /** UTILITY FUNCTION */

    function getExpectedLoanvalue(
        DataTypes.Storage storage _poolStorage,
        DataTypes.LoanEntry calldata loanEntry
    ) public view returns (uint256 principalAmount) {
        UnpackLoanParamtersLib.InterestParams memory loanParam = GenericLogic.unpackParamsForAgreementID(loanEntry);
        DataTypes.RiskScore memory riskParam = GenericLogic.getRiskScoreByIdx(
            _poolStorage.riskScores,
            loanEntry.riskScore
        );
        principalAmount = (loanParam.principalAmount * riskParam.advanceRate) / (ONE_HUNDRED_PERCENT);
    }

    function addLoan(
        DataTypes.Storage storage _poolStorage,
        uint256 loan,
        DataTypes.LoanEntry calldata loanEntry
    ) public returns (uint256) {
        bytes32 _tokenId = bytes32(loan);
        UnpackLoanParamtersLib.InterestParams memory loanParam = GenericLogic.unpackParamsForAgreementID(loanEntry);

        _poolStorage.details[_tokenId].risk = loanEntry.riskScore;
        _poolStorage.details[_tokenId].debtor = loanEntry.debtor;
        _poolStorage.details[_tokenId].expirationTimestamp = loanEntry.expirationTimestamp;
        _poolStorage.details[_tokenId].principalTokenAddress = loanEntry.principalTokenAddress;
        _poolStorage.details[_tokenId].salt = loanEntry.salt;
        _poolStorage.details[_tokenId].issuanceBlockTimestamp = loanEntry.issuanceBlockTimestamp;
        _poolStorage.details[_tokenId].assetPurpose = loanEntry.assetPurpose;
        _poolStorage.details[_tokenId].termsParam = loanEntry.termsParam;

        _poolStorage.details[_tokenId].principalAmount = loanParam.principalAmount;
        _poolStorage.details[_tokenId].termStartUnixTimestamp = loanParam.termStartUnixTimestamp;
        _poolStorage.details[_tokenId].termEndUnixTimestamp = loanParam.termEndUnixTimestamp;
        _poolStorage.details[_tokenId].amortizationUnitType = loanParam.amortizationUnitType;
        _poolStorage.details[_tokenId].termLengthInAmortizationUnits = loanParam.termLengthInAmortizationUnits;
        _poolStorage.details[_tokenId].interestRate = loanParam.interestRate;

        DataTypes.RiskScore memory riskParam = GenericLogic.getRiskScoreByIdx(
            _poolStorage.riskScores,
            loanEntry.riskScore
        );
        uint256 principalAmount = loanParam.principalAmount;
        uint256 _convertedInterestRate;

        principalAmount = (principalAmount * riskParam.advanceRate) / (ONE_HUNDRED_PERCENT);
        _convertedInterestRate = Math.ONE + (riskParam.interestRate * Math.ONE) / (ONE_HUNDRED_PERCENT * 365 days);

        _poolStorage.loanToNFT[_poolStorage.loanCount] = _tokenId;
        _poolStorage.loanCount++;
        setLoanMaturityDate(_poolStorage, _tokenId, loanParam.termEndUnixTimestamp);
        if (_poolStorage.rates[_convertedInterestRate].ratePerSecond == 0) {
            // If interest rate is not set
            _file(_poolStorage, 'rate', _convertedInterestRate, _convertedInterestRate);
        }
        GenericLogic.setRate(_poolStorage, loan, _convertedInterestRate);
        GenericLogic.accrue(_poolStorage, loan);
        _poolStorage.balances[loan] = Math.safeAdd(_poolStorage.balances[loan], principalAmount);
        _poolStorage.balance = Math.safeAdd(_poolStorage.balance, principalAmount);

        // increase NAV
        borrow(_poolStorage, loan, principalAmount);
        _incDebt(_poolStorage, loan, principalAmount);

        emit AddLoan(_tokenId, principalAmount, _poolStorage.details[_tokenId]);

        return principalAmount;
    }

    function setLoanMaturityDate(
        DataTypes.Storage storage _poolStorage,
        bytes32 nftID_,
        uint256 maturityDate_
    ) internal {
        require((GenericLogic.futureValue(_poolStorage, nftID_) == 0), 'can-not-change-maturityDate-outstanding-debt');

        _poolStorage.details[nftID_].maturityDate = GenericLogic.toUint128(
            Discounting.uniqueDayTimestamp(maturityDate_)
        );
        emit SetLoanMaturity(nftID_, maturityDate_);
    }

    /// @notice file allows governance to change parameters of the contract
    /// @param name name of the parameter
    /// @param value new value of the parameter

    function file(DataTypes.Storage storage _poolStorage, bytes32 name, uint256 value) public {
        if (name == 'discountRate') {
            uint256 oldDiscountRate = _poolStorage.discountRate;
            _poolStorage.discountRate = Math.ONE + (value * Math.ONE) / (ONE_HUNDRED_PERCENT * 365 days);
            // the nav needs to be re-calculated based on the new discount rate
            // no need to recalculate it if initialized the first time
            if (oldDiscountRate != 0) {
                GenericLogic.reCalcNAV(_poolStorage);
            }
        } else {
            revert('unknown config parameter');
        }
    }

    /// @notice file allows governance to change parameters of the contract
    /// @param name name of the parameter group
    /// @param writeOffPercentage_ the write off rate in percent
    /// @param overdueDays_ the number of days after which a loan is considered overdue

    function file(
        DataTypes.Storage storage _poolStorage,
        bytes32 name,
        uint256 rate_,
        uint256 writeOffPercentage_,
        uint256 overdueDays_,
        uint256 penaltyRate_,
        uint256 riskIndex
    ) public {
        if (name == 'writeOffGroup') {
            uint256 index = _poolStorage.writeOffGroups.length;
            uint256 _convertedInterestRate = Math.ONE + (rate_ * Math.ONE) / (ONE_HUNDRED_PERCENT * 365 days);
            uint256 _convertedWriteOffPercentage = Math.ONE - (writeOffPercentage_ * Math.ONE) / ONE_HUNDRED_PERCENT;
            uint256 _convertedPenaltyRate = Math.ONE +
                (Math.ONE * penaltyRate_ * rate_) /
                (ONE_HUNDRED_PERCENT * ONE_HUNDRED_PERCENT * 365 days);
            uint256 _convertedOverdueDays = overdueDays_ / 1 days;
            _poolStorage.writeOffGroups.push(
                DataTypes.WriteOffGroup(
                    GenericLogic.toUint128(_convertedWriteOffPercentage),
                    GenericLogic.toUint128(_convertedOverdueDays),
                    GenericLogic.toUint128(riskIndex)
                )
            );
            _file(_poolStorage, 'rate', Math.safeAdd(WRITEOFF_RATE_GROUP_START, index), _convertedInterestRate);
            _file(_poolStorage, 'penalty', Math.safeAdd(WRITEOFF_RATE_GROUP_START, index), _convertedPenaltyRate);
        } else {
            revert('unknown name');
        }
    }

    /// @notice file manages different state configs for the pile
    /// only a ward can call this function
    /// @param what what config to change
    /// @param rate the interest rate group
    /// @param value the value to change
    function _file(DataTypes.Storage storage _poolStorage, bytes32 what, uint256 rate, uint256 value) private {
        if (what == 'rate') {
            require(value != 0, 'rate-per-second-can-not-be-0');
            if (_poolStorage.rates[rate].chi == 0) {
                _poolStorage.rates[rate].chi = Math.ONE;
                _poolStorage.rates[rate].lastUpdated = uint48(block.timestamp);
            } else {
                GenericLogic.drip(_poolStorage, rate);
            }
            _poolStorage.rates[rate].ratePerSecond = value;
        } else if (what == 'penalty') {
            require(value != 0, 'penalty-per-second-can-not-be-0');
            if (_poolStorage.rates[rate].penaltyChi == 0) {
                _poolStorage.rates[rate].penaltyChi = Math.ONE;
                _poolStorage.rates[rate].lastUpdated = uint48(block.timestamp);
            } else {
                GenericLogic.drip(_poolStorage, rate);
            }

            _poolStorage.rates[rate].penaltyRatePerSecond = value;
        } else {
            revert('unknown parameter');
        }
    }

    /// @notice borrow updates the NAV for a new borrowed loan
    /// @param loan the id of the loan
    /// @param amount the amount borrowed
    /// @return navIncrease the increase of the NAV impacted by the new borrow
    function borrow(
        DataTypes.Storage storage _poolStorage,
        uint256 loan,
        uint256 amount
    ) private returns (uint256 navIncrease) {
        uint256 nnow = Discounting.uniqueDayTimestamp(block.timestamp);
        bytes32 nftID_ = GenericLogic.nftID(loan);
        uint256 maturityDate_ = GenericLogic.maturityDate(_poolStorage, nftID_);

        require(maturityDate_ > nnow, 'maturity-date-is-not-in-the-future');

        if (nnow > _poolStorage.lastNAVUpdate) {
            GenericLogic.calcUpdateNAV(_poolStorage);
        }

        // uint256 beforeNAV = latestNAV;

        // calculate amount including fixed fee if applicatable
        DataTypes.Rate memory _rate = _poolStorage.rates[_poolStorage.loanRates[loan]];

        // calculate future value FV
        DataTypes.NFTDetails memory nftDetail = GenericLogic.getAsset(_poolStorage, bytes32(loan));
        uint256 fv = Discounting.calcFutureValue(
            _rate.ratePerSecond,
            amount,
            maturityDate_,
            GenericLogic.recoveryRatePD(
                _poolStorage.riskScores,
                nftDetail.risk,
                nftDetail.expirationTimestamp - nftDetail.issuanceBlockTimestamp
            )
        );
        _poolStorage.details[nftID_].futureValue = GenericLogic.toUint128(
            Math.safeAdd(GenericLogic.futureValue(_poolStorage, nftID_), fv)
        );

        // add future value to the bucket of assets with the same maturity date
        _poolStorage.buckets[maturityDate_] = Math.safeAdd(_poolStorage.buckets[maturityDate_], fv);

        // increase borrowed amount for future ceiling computations
        _poolStorage.loanDetails[loan].borrowed = GenericLogic.toUint128(
            Math.safeAdd(GenericLogic.borrowed(_poolStorage, loan), amount)
        );

        // return increase NAV amount
        navIncrease = Discounting.calcDiscount(_poolStorage.discountRate, fv, nnow, maturityDate_);
        _poolStorage.latestDiscount = Math.safeAdd(_poolStorage.latestDiscount, navIncrease);
        _poolStorage.latestDiscountOfNavAssets[nftID_] += navIncrease;

        _poolStorage.latestNAV = Math.safeAdd(_poolStorage.latestNAV, navIncrease);

        return navIncrease;
    }

    function _decreaseLoan(DataTypes.Storage storage _poolStorage, uint256 loan, uint256 amount) private {
        _poolStorage.latestNAV = Discounting.secureSub(
            _poolStorage.latestNAV,
            Math.rmul(
                amount,
                GenericLogic.toUint128(
                    _poolStorage.writeOffGroups[_poolStorage.loanRates[loan] - WRITEOFF_RATE_GROUP_START].percentage
                )
            )
        );
        decDebt(_poolStorage, loan, amount);
    }

    function _calcFutureValue(
        DataTypes.Storage storage _poolStorage,
        uint256 loan,
        uint256 _debt,
        uint256 _maturityDate
    ) private view returns (uint256) {
        DataTypes.Rate memory _rate = _poolStorage.rates[_poolStorage.loanRates[loan]];
        DataTypes.NFTDetails memory nftDetail = GenericLogic.getAsset(_poolStorage, GenericLogic.nftID(loan));
        uint256 fv = Discounting.calcFutureValue(
            _rate.ratePerSecond,
            _debt,
            _maturityDate,
            GenericLogic.recoveryRatePD(
                _poolStorage.riskScores,
                nftDetail.risk,
                nftDetail.expirationTimestamp - nftDetail.issuanceBlockTimestamp
            )
        );
        return fv;
    }

    /// @notice repay updates the NAV for a new repaid loan
    /// @param loans the ids of the loan
    /// @param amounts the amounts repaid
    function repayLoan(
        DataTypes.Storage storage _poolStorage,
        uint256[] calldata loans,
        uint256[] calldata amounts
    ) external returns (uint256[] memory, uint256[] memory) {
        uint256 nnow = Discounting.uniqueDayTimestamp(block.timestamp);

        uint256 numberOfLoans = loans.length;

        uint256[] memory repayAmounts = new uint256[](numberOfLoans);
        uint256[] memory previousDebts = new uint256[](numberOfLoans);

        for (uint256 i; i < numberOfLoans; i++) {
            uint256 loan = loans[i];
            uint256 amount = amounts[i];

            // re-define: prevent stack too deep
            DataTypes.Storage storage __poolStorage = _poolStorage;

            GenericLogic.accrue(__poolStorage, loan);

            if (nnow > __poolStorage.lastNAVUpdate) {
                GenericLogic.calcUpdateNAV(__poolStorage);
            }

            // In case of successful repayment the latestNAV is decreased by the repaid amount
            uint256 maturityDate_ = GenericLogic.maturityDate(__poolStorage, bytes32(loan));

            uint256 _currentDebt = GenericLogic.debt(__poolStorage, loan);
            if (amount > _currentDebt) {
                amount = _currentDebt;
            }

            repayAmounts[i] = amount;
            previousDebts[i] = _currentDebt;

            // case 1: repayment of a written-off loan
            if (GenericLogic.isLoanWrittenOff(__poolStorage, loan)) {
                // update nav with write-off decrease
                _decreaseLoan(__poolStorage, loan, amount);
                continue;
            }

            uint256 preFV = GenericLogic.futureValue(__poolStorage, bytes32(loan));
            // in case of partial repayment, compute the fv of the remaining debt and add to the according fv bucket
            uint256 fvDecrease = preFV;

            // prevent stack too deep
            {
                uint256 fv = 0;
                uint256 _debt = Math.safeSub(_currentDebt, amount); // Remaining
                if (_debt != 0) {
                    fv = _calcFutureValue(__poolStorage, loan, _debt, maturityDate_);
                    if (preFV >= fv) {
                        fvDecrease = Math.safeSub(preFV, fv);
                    } else {
                        fvDecrease = 0;
                    }
                }

                __poolStorage.details[bytes32(loan)].futureValue = GenericLogic.toUint128(fv);
            }

            // case 2: repayment of a loan before or on maturity date
            if (maturityDate_ >= nnow) {
                // remove future value decrease from bucket
                __poolStorage.buckets[maturityDate_] = Math.safeSub(__poolStorage.buckets[maturityDate_], fvDecrease);

                uint256 discountDecrease = Discounting.calcDiscount(
                    __poolStorage.discountRate,
                    fvDecrease,
                    nnow,
                    maturityDate_
                );

                __poolStorage.latestDiscount = Discounting.secureSub(__poolStorage.latestDiscount, discountDecrease);
                __poolStorage.latestDiscountOfNavAssets[bytes32(loan)] = Discounting.secureSub(
                    __poolStorage.latestDiscountOfNavAssets[bytes32(loan)],
                    discountDecrease
                );

                __poolStorage.latestNAV = Discounting.secureSub(__poolStorage.latestNAV, discountDecrease);
            } else {
                // case 3: repayment of an overdue loan
                __poolStorage.overdueLoans = Math.safeSub(__poolStorage.overdueLoans, fvDecrease);
                __poolStorage.overdueLoansOfNavAssets[bytes32(loan)] = Math.safeSub(
                    __poolStorage.overdueLoansOfNavAssets[bytes32(loan)],
                    fvDecrease
                );
                __poolStorage.latestNAV = Discounting.secureSub(__poolStorage.latestNAV, fvDecrease);
            }

            decDebt(__poolStorage, loan, amount);
            emit Repay(bytes32(loan), amount);
        }
        return (repayAmounts, previousDebts);
    }

    /// @notice writeOff writes off a loan if it is overdue
    /// @param loan the id of the loan
    function writeOff(DataTypes.Storage storage _poolStorage, uint256 loan) public {
        require(!_poolStorage.loanDetails[loan].authWriteOff, 'only-auth-write-off');

        bytes32 nftID_ = GenericLogic.nftID(loan);
        uint256 maturityDate_ = GenericLogic.maturityDate(_poolStorage, nftID_);
        require(maturityDate_ > 0, 'loan-does-not-exist');

        // can not write-off healthy loans
        uint256 nnow = Discounting.uniqueDayTimestamp(block.timestamp);
        DataTypes.NFTDetails memory nftDetail = GenericLogic.getAsset(_poolStorage, bytes32(loan));
        DataTypes.RiskScore memory riskParam = GenericLogic.getRiskScoreByIdx(_poolStorage.riskScores, nftDetail.risk);
        require(maturityDate_ + riskParam.gracePeriod <= nnow, 'maturity-date-in-the-future');
        // check the writeoff group based on the amount of days overdue
        uint256 writeOffGroupIndex_ = GenericLogic.currentValidWriteOffGroup(_poolStorage, loan);

        if (
            writeOffGroupIndex_ < type(uint128).max &&
            _poolStorage.loanRates[loan] != WRITEOFF_RATE_GROUP_START + writeOffGroupIndex_
        ) {
            _writeOff(_poolStorage, loan, writeOffGroupIndex_, nftID_, maturityDate_);
            emit WriteOff(nftID_, writeOffGroupIndex_, false);
        }
    }

    /// @notice internal function for the write off
    /// @param loan the id of the loan
    /// @param writeOffGroupIndex_ the index of the writeoff group
    /// @param nftID_ the nftID of the loan
    /// @param maturityDate_ the maturity date of the loan
    function _writeOff(
        DataTypes.Storage storage _poolStorage,
        uint256 loan,
        uint256 writeOffGroupIndex_,
        bytes32 nftID_,
        uint256 maturityDate_
    ) internal {
        uint256 nnow = Discounting.uniqueDayTimestamp(block.timestamp);
        // Ensure we have an up to date NAV
        if (nnow > _poolStorage.lastNAVUpdate) {
            GenericLogic.calcUpdateNAV(_poolStorage);
        }

        uint256 latestNAV_ = _poolStorage.latestNAV;

        // first time written-off
        if (!GenericLogic.isLoanWrittenOff(_poolStorage, loan)) {
            uint256 fv = GenericLogic.futureValue(_poolStorage, nftID_);
            if (Discounting.uniqueDayTimestamp(_poolStorage.lastNAVUpdate) > maturityDate_) {
                // write off after the maturity date
                _poolStorage.overdueLoans = Discounting.secureSub(_poolStorage.overdueLoans, fv);
                _poolStorage.overdueLoansOfNavAssets[nftID_] = Discounting.secureSub(
                    _poolStorage.overdueLoansOfNavAssets[nftID_],
                    fv
                );
                latestNAV_ = Discounting.secureSub(latestNAV_, fv);
            } else {
                // write off before or on the maturity date
                _poolStorage.buckets[maturityDate_] = Math.safeSub(_poolStorage.buckets[maturityDate_], fv);

                uint256 pv = Math.rmul(
                    fv,
                    Discounting.rpow(
                        _poolStorage.discountRate,
                        Math.safeSub(Discounting.uniqueDayTimestamp(maturityDate_), nnow),
                        Math.ONE
                    )
                );
                _poolStorage.latestDiscount = Discounting.secureSub(_poolStorage.latestDiscount, pv);
                _poolStorage.latestDiscountOfNavAssets[nftID_] = Discounting.secureSub(
                    _poolStorage.latestDiscountOfNavAssets[nftID_],
                    pv
                );

                latestNAV_ = Discounting.secureSub(latestNAV_, pv);
            }
        }

        GenericLogic.changeRate(_poolStorage, loan, WRITEOFF_RATE_GROUP_START + writeOffGroupIndex_);
        _poolStorage.latestNAV = Math.safeAdd(
            latestNAV_,
            Math.rmul(
                GenericLogic.debt(_poolStorage, loan),
                _poolStorage.writeOffGroups[writeOffGroupIndex_].percentage
            )
        );
    }

    function updateAssetRiskScore(DataTypes.Storage storage _poolStorage, bytes32 nftID_, uint256 risk_) public {
        uint256 nnow = Discounting.uniqueDayTimestamp(block.timestamp);

        // no change in risk group
        if (risk_ == GenericLogic.risk(_poolStorage, nftID_)) {
            return;
        }

        _poolStorage.details[nftID_].risk = GenericLogic.toUint128(risk_);

        // update nav -> latestNAVUpdate = now
        if (nnow > _poolStorage.lastNAVUpdate) {
            GenericLogic.calcUpdateNAV(_poolStorage);
        }

        // switch of collateral risk group results in new: ceiling, threshold and interest rate for existing loan
        // change to new rate interestRate immediately in pile if loan debt exists
        uint256 loan = uint256(nftID_);
        if (_poolStorage.pie[loan] != 0) {
            DataTypes.RiskScore memory riskParam = GenericLogic.getRiskScoreByIdx(_poolStorage.riskScores, risk_);
            uint256 _convertedInterestRate = Math.ONE +
                (riskParam.interestRate * Math.ONE) /
                (ONE_HUNDRED_PERCENT * 365 days);
            if (_poolStorage.rates[_convertedInterestRate].ratePerSecond == 0) {
                // If interest rate is not set
                _file(_poolStorage, 'rate', _convertedInterestRate, _convertedInterestRate);
            }
            GenericLogic.changeRate(_poolStorage, loan, _convertedInterestRate);
            _poolStorage.details[nftID_].interestRate = riskParam.interestRate;
        }

        // no currencyAmount borrowed yet
        if (GenericLogic.futureValue(_poolStorage, nftID_) == 0) {
            return;
        }

        uint256 maturityDate_ = GenericLogic.maturityDate(_poolStorage, nftID_);

        // Changing the risk group of an nft, might lead to a new interest rate for the dependant loan.
        // New interest rate leads to a future value.
        // recalculation required
        {
            uint256 fvDecrease = GenericLogic.futureValue(_poolStorage, nftID_);

            uint256 navDecrease = Discounting.calcDiscount(_poolStorage.discountRate, fvDecrease, nnow, maturityDate_);

            _poolStorage.buckets[maturityDate_] = Math.safeSub(_poolStorage.buckets[maturityDate_], fvDecrease);

            _poolStorage.latestDiscount = Discounting.secureSub(_poolStorage.latestDiscount, navDecrease);
            _poolStorage.latestDiscountOfNavAssets[nftID_] = Discounting.secureSub(
                _poolStorage.latestDiscountOfNavAssets[nftID_],
                navDecrease
            );

            _poolStorage.latestNAV = Discounting.secureSub(_poolStorage.latestNAV, navDecrease);
        }

        // update latest NAV
        // update latest Discount
        DataTypes.Rate memory _rate = _poolStorage.rates[_poolStorage.loanRates[loan]];
        DataTypes.NFTDetails memory nftDetail = GenericLogic.getAsset(_poolStorage, bytes32(loan));
        _poolStorage.details[nftID_].futureValue = GenericLogic.toUint128(
            Discounting.calcFutureValue(
                _rate.ratePerSecond,
                GenericLogic.debt(_poolStorage, loan),
                GenericLogic.maturityDate(_poolStorage, nftID_),
                GenericLogic.recoveryRatePD(
                    _poolStorage.riskScores,
                    risk_,
                    nftDetail.expirationTimestamp - nftDetail.issuanceBlockTimestamp
                )
            )
        );

        uint256 fvIncrease = GenericLogic.futureValue(_poolStorage, nftID_);
        uint256 navIncrease = Discounting.calcDiscount(_poolStorage.discountRate, fvIncrease, nnow, maturityDate_);

        _poolStorage.buckets[maturityDate_] = Math.safeAdd(_poolStorage.buckets[maturityDate_], fvIncrease);

        _poolStorage.latestDiscount = Math.safeAdd(_poolStorage.latestDiscount, navIncrease);
        _poolStorage.latestDiscountOfNavAssets[nftID_] += navIncrease;

        _poolStorage.latestNAV = Math.safeAdd(_poolStorage.latestNAV, navIncrease);
        emit UpdateAssetRiskScore(nftID_, risk_);
    }

    function _incDebt(DataTypes.Storage storage _poolStorage, uint256 loan, uint256 currencyAmount) private {
        uint256 rate = _poolStorage.loanRates[loan];
        require(block.timestamp == _poolStorage.rates[rate].lastUpdated, 'rate-group-not-updated');
        uint256 pieAmount = GenericLogic.toPie(_poolStorage.rates[rate].chi, currencyAmount);

        _poolStorage.pie[loan] = Math.safeAdd(_poolStorage.pie[loan], pieAmount);
        _poolStorage.rates[rate].pie = Math.safeAdd(_poolStorage.rates[rate].pie, pieAmount);

        emit IncreaseDebt(GenericLogic.nftID(loan), currencyAmount);
    }

    function decDebt(DataTypes.Storage storage _poolStorage, uint256 loan, uint256 currencyAmount) private {
        uint256 rate = _poolStorage.loanRates[loan];
        require(block.timestamp == _poolStorage.rates[rate].lastUpdated, 'rate-group-not-updated');
        uint256 penaltyChi_ = _poolStorage.rates[rate].penaltyChi;
        if (penaltyChi_ > 0) {
            currencyAmount = GenericLogic.toPie(penaltyChi_, currencyAmount);
        }
        uint256 pieAmount = GenericLogic.toPie(_poolStorage.rates[rate].chi, currencyAmount);

        _poolStorage.pie[loan] = Math.safeSub(_poolStorage.pie[loan], pieAmount);
        _poolStorage.rates[rate].pie = Math.safeSub(_poolStorage.rates[rate].pie, pieAmount);

        emit DecreaseDebt(GenericLogic.nftID(loan), currencyAmount);
    }
}
