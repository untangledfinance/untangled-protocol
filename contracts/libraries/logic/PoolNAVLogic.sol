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
import {DataTypes} from '../DataTypes.sol';
import {Math} from '../Math.sol';
import {Discounting} from '../Discounting.sol';
import {GenericLogic} from './GenericLogic.sol';
/**
 * @title Untangled's SecuritizaionPoolNAV contract
 * @notice Main entry point for senior LPs (a.k.a. capital providers)
 *  Automatically invests across borrower pools using an adjustable strategy.
 * @author Untangled Team
 */
library PoolNAVLogic 
{

    uint256 constant RATE_SCALING_FACTOR = 10 ** 4;

    uint256 constant ONE_HUNDRED_PERCENT = 100 * RATE_SCALING_FACTOR;

    uint256 constant ONE = 10 ** 27;
    uint256 constant WRITEOFF_RATE_GROUP_START = 1000 * ONE;

    event IncreaseDebt(bytes32 indexed loan, uint256 currencyAmount);
    event DecreaseDebt(bytes32 indexed loan, uint256 currencyAmount);
    event SetRate(bytes32 indexed loan, uint256 rate);
    event ChangeRate(bytes32 indexed loan, uint256 newRate);
    event File(bytes32 indexed what, uint256 rate, uint256 value);

    // events
    event SetLoanMaturity(bytes32 indexed loan, uint256 maturityDate_);
    event WriteOff(bytes32 indexed loan, uint256 indexed writeOffGroupsIndex, bool override_);
    event AddLoan(bytes32 indexed loan, uint256 principalAmount, DataTypes.NFTDetails nftdetails);
    event Repay(bytes32 indexed loan, uint256 currencyAmount);
    event UpdateAssetRiskScore(bytes32 loan, uint256 risk);

    /** GETTER */
    /// @notice getter function for the maturityDate
    /// @param nft_ the id of the nft based on the hash of registry and tokenId
    /// @return maturityDate_ the maturityDate of the nft
    function maturityDate(DataTypes.Storage storage _poolStorage,bytes32 nft_) internal view  returns (uint256 maturityDate_) {
        return GenericLogic.maturityDate(_poolStorage, nft_);
    }
    function futureValue(DataTypes.Storage storage _poolStorage, bytes32 nft_) public view  returns (uint256 fv_) {
        return GenericLogic.futureValue(_poolStorage, nft_);
    }

    /// @notice getter function for the recovery rate PD
    /// @param riskID id of a risk group
    /// @return recoveryRatePD_ recovery rate PD of the risk group
    function recoveryRatePD(DataTypes.RiskScore[] storage riskScores,uint256 riskID, uint256 termLength) internal view returns (uint256 recoveryRatePD_) {
        return GenericLogic.recoveryRatePD(riskScores, riskID, termLength);
    }

    /// @notice getter function for the borrowed amount
    /// @param loan id of a loan
    /// @return borrowed_ borrowed amount of the loan
    function borrowed(DataTypes.Storage storage _poolStorage,uint256 loan) internal view returns (uint256 borrowed_) {
        return GenericLogic.borrowed(_poolStorage, loan);
    }

    /** UTILITY FUNCTION */
    // TODO have to use modifier in main contract
    function getRiskScoreByIdx(DataTypes.RiskScore[] storage riskScores,uint256 idx) private view returns (DataTypes.RiskScore memory) {
        return GenericLogic.getRiskScoreByIdx(riskScores, idx);
    }

    // TODO have to use modifier in main contract
    function addLoan(DataTypes.Storage storage _poolStorage, uint256 loan, DataTypes.LoanEntry calldata loanEntry) public returns (uint256) {
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

        DataTypes.RiskScore memory riskParam = getRiskScoreByIdx(_poolStorage.riskScores,loanEntry.riskScore);
        uint256 principalAmount = loanParam.principalAmount;
        uint256 _convertedInterestRate;

        principalAmount = (principalAmount * riskParam.advanceRate) / (ONE_HUNDRED_PERCENT);
        _convertedInterestRate = Math.ONE + (riskParam.interestRate * Math.ONE) / (ONE_HUNDRED_PERCENT * 365 days);

        _poolStorage.loanToNFT[_poolStorage.loanCount] = _tokenId;
        _poolStorage.loanCount++;
        setLoanMaturityDate(_poolStorage,_tokenId, loanParam.termEndUnixTimestamp);
        if (_poolStorage.rates[_convertedInterestRate].ratePerSecond == 0) {
            // If interest rate is not set
            _file(_poolStorage,'rate', _convertedInterestRate, _convertedInterestRate);
        }
        setRate(_poolStorage,loan, _convertedInterestRate);
        accrue(_poolStorage,loan);

        _poolStorage.balances[loan] = Math.safeAdd(_poolStorage.balances[loan], principalAmount);
        _poolStorage.balance = Math.safeAdd(_poolStorage.balance, principalAmount);

        // increase NAV
        borrow(_poolStorage,loan, principalAmount);
        _incDebt(_poolStorage,loan, principalAmount);

        emit AddLoan(_tokenId, principalAmount, _poolStorage.details[_tokenId]);

        return principalAmount;
    }

    /// @notice converts a uint256 to uint128
    /// @param value the value to be converted
    /// @return converted value to uint128
    function toUint128(uint256 value) internal pure returns (uint128 converted) {
        require(value <= type(uint128).max, "SafeCast: value doesn't fit in 128 bits");
        return uint128(value);
    }
    // TODO have to use modifier in main contract
    function setLoanMaturityDate(DataTypes.Storage storage _poolStorage,bytes32 nftID_, uint256 maturityDate_) internal {
        require((futureValue(_poolStorage,nftID_) == 0), 'can-not-change-maturityDate-outstanding-debt');
        // Storage storage $ = _getStorage();
        _poolStorage.details[nftID_].maturityDate = toUint128(Discounting.uniqueDayTimestamp(maturityDate_));
        emit SetLoanMaturity(nftID_, maturityDate_);
    }

    /// @notice file allows governance to change parameters of the contract
    /// @param name name of the parameter
    /// @param value new value of the parameter
    // TODO have to use modifier in main contract
    function file(DataTypes.Storage storage _poolStorage,bytes32 name, uint256 value) public {
        if (name == 'discountRate') {
            // Storage storage $ = _getStorage();
            uint256 oldDiscountRate = _poolStorage.discountRate;
            _poolStorage.discountRate = Math.ONE + (value * Math.ONE) / (ONE_HUNDRED_PERCENT * 365 days);
            // the nav needs to be re-calculated based on the new discount rate
            // no need to recalculate it if initialized the first time
            if (oldDiscountRate != 0) {
                reCalcNAV(_poolStorage);
            }
        } else {
            revert('unknown config parameter');
        }
    }

    /// @notice file allows governance to change parameters of the contract
    /// @param name name of the parameter group
    /// @param writeOffPercentage_ the write off rate in percent
    /// @param overdueDays_ the number of days after which a loan is considered overdue
    // TODO have to use modifier in main contract
    function file(
        DataTypes.Storage storage _poolStorage,
        bytes32 name,
        uint256 rate_,
        uint256 writeOffPercentage_,
        uint256 overdueDays_,
        uint256 penaltyRate_,
        uint256 riskIndex
    ) public  {
        if (name == 'writeOffGroup') {
            // Storage storage $ = _getStorage();
            uint256 index = _poolStorage.writeOffGroups.length;
            uint256 _convertedInterestRate = Math.ONE + (rate_ * Math.ONE) / (ONE_HUNDRED_PERCENT * 365 days);
            uint256 _convertedWriteOffPercentage = Math.ONE - (writeOffPercentage_ * Math.ONE) / ONE_HUNDRED_PERCENT;
            uint256 _convertedPenaltyRate = Math.ONE +
                (Math.ONE * penaltyRate_ * rate_) /
                (ONE_HUNDRED_PERCENT * ONE_HUNDRED_PERCENT * 365 days);
            uint256 _convertedOverdueDays = overdueDays_ / 1 days;
            _poolStorage.writeOffGroups.push(
                DataTypes.WriteOffGroup(
                    toUint128(_convertedWriteOffPercentage),
                    toUint128(_convertedOverdueDays),
                    toUint128(riskIndex)
                )
            );
            _file(_poolStorage,'rate', Math.safeAdd(WRITEOFF_RATE_GROUP_START, index), _convertedInterestRate);
            _file(_poolStorage,'penalty', Math.safeAdd(WRITEOFF_RATE_GROUP_START, index), _convertedPenaltyRate);
        } else {
            revert('unknown name');
        }
    }

    /// @notice file manages different state configs for the pile
    /// only a ward can call this function
    /// @param what what config to change
    /// @param rate the interest rate group
    /// @param value the value to change
    function _file(DataTypes.Storage storage _poolStorage,bytes32 what, uint256 rate, uint256 value) private {
        // Storage storage $ = _getStorage();
        if (what == 'rate') {
            require(value != 0, 'rate-per-second-can-not-be-0');
            if (_poolStorage.rates[rate].chi == 0) {
                _poolStorage.rates[rate].chi = Math.ONE;
                _poolStorage.rates[rate].lastUpdated = uint48(block.timestamp);
            } else {
                drip(_poolStorage,rate);
            }
            _poolStorage.rates[rate].ratePerSecond = value;
        } else if (what == 'penalty') {
            require(value != 0, 'penalty-per-second-can-not-be-0');
            if (_poolStorage.rates[rate].penaltyChi == 0) {
                _poolStorage.rates[rate].penaltyChi = Math.ONE;
                _poolStorage.rates[rate].lastUpdated = uint48(block.timestamp);
            } else {
                drip(_poolStorage,rate);
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
    function borrow(DataTypes.Storage storage _poolStorage,uint256 loan, uint256 amount) private returns (uint256 navIncrease) {
        uint256 nnow = Discounting.uniqueDayTimestamp(block.timestamp);
        bytes32 nftID_ = nftID(loan);
        uint256 maturityDate_ = maturityDate(_poolStorage,nftID_);

        require(maturityDate_ > nnow, 'maturity-date-is-not-in-the-future');

        // Storage storage $ = _getStorage();

        if (nnow > _poolStorage.lastNAVUpdate) {
            calcUpdateNAV(_poolStorage);
        }

        // uint256 beforeNAV = latestNAV;

        // calculate amount including fixed fee if applicatable
        DataTypes.Rate memory _rate = _poolStorage.rates[_poolStorage.loanRates[loan]];

        // calculate future value FV
        DataTypes.NFTDetails memory nftDetail = getAsset(_poolStorage,bytes32(loan));
        uint256 fv = Discounting.calcFutureValue(
            _rate.ratePerSecond,
            amount,
            maturityDate_,
            recoveryRatePD(_poolStorage.riskScores,nftDetail.risk, nftDetail.expirationTimestamp - nftDetail.issuanceBlockTimestamp)
        );
        _poolStorage.details[nftID_].futureValue = toUint128(Math.safeAdd(futureValue(_poolStorage,nftID_), fv));

        // add future value to the bucket of assets with the same maturity date
        _poolStorage.buckets[maturityDate_] = Math.safeAdd(_poolStorage.buckets[maturityDate_], fv);

        // increase borrowed amount for future ceiling computations
        _poolStorage.loanDetails[loan].borrowed = toUint128(Math.safeAdd(borrowed(_poolStorage,loan), amount));

        // return increase NAV amount
        navIncrease = Discounting.calcDiscount(_poolStorage.discountRate, fv, nnow, maturityDate_);
        _poolStorage.latestDiscount = Math.safeAdd(_poolStorage.latestDiscount, navIncrease);
        _poolStorage.latestDiscountOfNavAssets[nftID_] += navIncrease;

        _poolStorage.latestNAV = Math.safeAdd(_poolStorage.latestNAV, navIncrease);

        return navIncrease;
    }

    function _decreaseLoan(DataTypes.Storage storage _poolStorage,uint256 loan, uint256 amount) private {
        // Storage storage $ = _getStorage();
        _poolStorage.latestNAV = Discounting.secureSub(
            _poolStorage.latestNAV,
            Math.rmul(amount, toUint128(_poolStorage.writeOffGroups[_poolStorage.loanRates[loan] - WRITEOFF_RATE_GROUP_START].percentage))
        );
        decDebt(_poolStorage,loan, amount);
    }

    function _calcFutureValue(DataTypes.Storage storage _poolStorage,uint256 loan, uint256 _debt, uint256 _maturityDate) private view returns (uint256) {
        // Storage storage $ = _getStorage();
        DataTypes.Rate memory _rate = _poolStorage.rates[_poolStorage.loanRates[loan]];
        DataTypes.NFTDetails memory nftDetail = getAsset(_poolStorage,nftID(loan));
        uint256 fv = Discounting.calcFutureValue(
            _rate.ratePerSecond,
            _debt,
            _maturityDate,
            recoveryRatePD(_poolStorage.riskScores,nftDetail.risk, nftDetail.expirationTimestamp - nftDetail.issuanceBlockTimestamp)
        );
        return fv;
    }

    /// @notice repay updates the NAV for a new repaid loan
    /// @param loan the id of the loan
    /// @param amount the amount repaid
    function repayLoan(DataTypes.Storage storage _poolStorage,uint256 loan, uint256 amount) external returns (uint256) {
        // require(address(registry().getLoanRepaymentRouter()) == msg.sender, 'not authorized');
        accrue(_poolStorage,loan);
        uint256 nnow = Discounting.uniqueDayTimestamp(block.timestamp);
        // Storage storage $ = _getStorage();
        if (nnow > _poolStorage.lastNAVUpdate) {
            calcUpdateNAV(_poolStorage);
        }

        // In case of successful repayment the latestNAV is decreased by the repaid amount
        bytes32 nftID_ = nftID(loan);
        uint256 maturityDate_ = maturityDate(_poolStorage,nftID_);

        uint256 _currentDebt = debt(_poolStorage,loan);
        if (amount > _currentDebt) {
            amount = _currentDebt;
        }
        // case 1: repayment of a written-off loan
        if (isLoanWrittenOff(_poolStorage,loan)) {
            // update nav with write-off decrease
            _decreaseLoan(_poolStorage,loan, amount);
            return amount;
        }
        uint256 _debt = Math.safeSub(_currentDebt, amount); // Remaining
        uint256 preFV = futureValue(_poolStorage,nftID_);
        // in case of partial repayment, compute the fv of the remaining debt and add to the according fv bucket
        uint256 fv = 0;
        uint256 fvDecrease = preFV;
        if (_debt != 0) {
            fv = _calcFutureValue(_poolStorage,loan, _debt, maturityDate_);
            if (preFV >= fv) {
                fvDecrease = Math.safeSub(preFV, fv);
            } else {
                fvDecrease = 0;
            }
        }

        _poolStorage.details[nftID_].futureValue = toUint128(fv);

        // case 2: repayment of a loan before or on maturity date
        if (maturityDate_ >= nnow) {
            // remove future value decrease from bucket
            _poolStorage.buckets[maturityDate_] = Math.safeSub(_poolStorage.buckets[maturityDate_], fvDecrease);

            uint256 discountDecrease = Discounting.calcDiscount(_poolStorage.discountRate, fvDecrease, nnow, maturityDate_);

            _poolStorage.latestDiscount = Discounting.secureSub(_poolStorage.latestDiscount, discountDecrease);
            _poolStorage.latestDiscountOfNavAssets[nftID_] = Discounting.secureSub(_poolStorage.latestDiscountOfNavAssets[nftID_], discountDecrease);

            _poolStorage.latestNAV = Discounting.secureSub(_poolStorage.latestNAV, discountDecrease);
        } else {
            // case 3: repayment of an overdue loan
            _poolStorage.overdueLoans = Math.safeSub(_poolStorage.overdueLoans, fvDecrease);
            _poolStorage.overdueLoansOfNavAssets[nftID_] = Math.safeSub(_poolStorage.overdueLoansOfNavAssets[nftID_], fvDecrease);
            _poolStorage.latestNAV = Discounting.secureSub(_poolStorage.latestNAV, fvDecrease);
        }

        decDebt(_poolStorage,loan, amount);

        emit Repay(nftID_, amount);
        return amount;
    }

    /// @notice writeOff writes off a loan if it is overdue
    /// @param loan the id of the loan
    function writeOff(DataTypes.Storage storage _poolStorage,uint256 loan) public {
        // Storage storage $ = _getStorage();
        require(!_poolStorage.loanDetails[loan].authWriteOff, 'only-auth-write-off');

        bytes32 nftID_ = nftID(loan);
        uint256 maturityDate_ = maturityDate(_poolStorage,nftID_);
        require(maturityDate_ > 0, 'loan-does-not-exist');

        // can not write-off healthy loans
        uint256 nnow = Discounting.uniqueDayTimestamp(block.timestamp);
        DataTypes.NFTDetails memory nftDetail = getAsset(_poolStorage,bytes32(loan));
        DataTypes.RiskScore memory riskParam = getRiskScoreByIdx(_poolStorage.riskScores,nftDetail.risk);
        require(maturityDate_ + riskParam.gracePeriod <= nnow, 'maturity-date-in-the-future');
        // check the writeoff group based on the amount of days overdue
        uint256 writeOffGroupIndex_ = currentValidWriteOffGroup(_poolStorage,loan);

        if (
            writeOffGroupIndex_ < type(uint128).max &&
            _poolStorage.loanRates[loan] != WRITEOFF_RATE_GROUP_START + writeOffGroupIndex_
        ) {
            _writeOff(_poolStorage,loan, writeOffGroupIndex_, nftID_, maturityDate_);
            emit WriteOff(nftID_, writeOffGroupIndex_, false);
        }
    }

    /// @notice internal function for the write off
    /// @param loan the id of the loan
    /// @param writeOffGroupIndex_ the index of the writeoff group
    /// @param nftID_ the nftID of the loan
    /// @param maturityDate_ the maturity date of the loan
    function _writeOff(DataTypes.Storage storage _poolStorage,uint256 loan, uint256 writeOffGroupIndex_, bytes32 nftID_, uint256 maturityDate_) internal {
        // Storage storage $ = _getStorage();
        uint256 nnow = Discounting.uniqueDayTimestamp(block.timestamp);
        // Ensure we have an up to date NAV
        if (nnow > _poolStorage.lastNAVUpdate) {
            calcUpdateNAV(_poolStorage);
        }

        uint256 latestNAV_ = _poolStorage.latestNAV;

        // first time written-off
        if (isLoanWrittenOff(_poolStorage,loan) == false) {
            uint256 fv = futureValue(_poolStorage,nftID_);
            if (Discounting.uniqueDayTimestamp(_poolStorage.lastNAVUpdate) > maturityDate_) {
                // write off after the maturity date
                _poolStorage.overdueLoans = Discounting.secureSub(_poolStorage.overdueLoans, fv);
                _poolStorage.overdueLoansOfNavAssets[nftID_] = Discounting.secureSub(_poolStorage.overdueLoansOfNavAssets[nftID_], fv);
                latestNAV_ = Discounting.secureSub(latestNAV_, fv);
            } else {
                // write off before or on the maturity date
                _poolStorage.buckets[maturityDate_] = Math.safeSub(_poolStorage.buckets[maturityDate_], fv);

                uint256 pv = Math.rmul(fv, Discounting.rpow(_poolStorage.discountRate, Math.safeSub(Discounting.uniqueDayTimestamp(maturityDate_), nnow), Math.ONE));
                _poolStorage.latestDiscount = Discounting.secureSub(_poolStorage.latestDiscount, pv);
                _poolStorage.latestDiscountOfNavAssets[nftID_] = Discounting.secureSub(_poolStorage.latestDiscountOfNavAssets[nftID_], pv);

                latestNAV_ = Discounting.secureSub(latestNAV_, pv);
            }
        }

        changeRate(_poolStorage,loan, WRITEOFF_RATE_GROUP_START + writeOffGroupIndex_);
        _poolStorage.latestNAV = Math.safeAdd(latestNAV_, Math.rmul(debt(_poolStorage,loan), _poolStorage.writeOffGroups[writeOffGroupIndex_].percentage));
    }

    /// @notice returns if a loan is written off
    /// @param loan the id of the loan
    function isLoanWrittenOff(DataTypes.Storage storage _poolStorage,uint256 loan) internal view returns (bool) {
        return GenericLogic.isLoanWrittenOff(_poolStorage, loan);
    }

    /// @notice calculates and returns the current NAV and updates the state
    /// @return nav_ current NAV
    function calcUpdateNAV(DataTypes.Storage storage _poolStorage) internal returns (uint256 nav_) {
        return GenericLogic.calcUpdateNAV(_poolStorage);
    }

    /// @notice re-calculates the nav in a non-optimized way
    ///  the method is not updating the NAV to latest block.timestamp
    /// @return nav_ current NAV
    function reCalcNAV(DataTypes.Storage storage _poolStorage) internal returns (uint256 nav_) {
        return GenericLogic.reCalcNAV(_poolStorage);
    }

    /// @notice returns the nftID for the underlying collateral nft
    /// @param loan the loan id
    /// @return nftID_ the nftID of the loan
    function nftID(uint256 loan) internal pure returns (bytes32 nftID_) {
        return GenericLogic.nftID(loan);
    }

    /// @notice returns the current valid write off group of a loan
    /// @param loan the loan id
    /// @return writeOffGroup_ the current valid write off group of a loan
    function currentValidWriteOffGroup(DataTypes.Storage storage _poolStorage,uint256 loan) internal view returns (uint256 writeOffGroup_) {
        return GenericLogic.currentValidWriteOffGroup(_poolStorage, loan);
    }

    function _incDebt(DataTypes.Storage storage _poolStorage,uint256 loan, uint256 currencyAmount) private {
        // Storage storage $ = _getStorage();
        uint256 rate = _poolStorage.loanRates[loan];
        require(block.timestamp == _poolStorage.rates[rate].lastUpdated, 'rate-group-not-updated');
        uint256 pieAmount = toPie(_poolStorage.rates[rate].chi, currencyAmount);

        _poolStorage.pie[loan] = Math.safeAdd(_poolStorage.pie[loan], pieAmount);
        _poolStorage.rates[rate].pie = Math.safeAdd(_poolStorage.rates[rate].pie, pieAmount);

        emit IncreaseDebt(nftID(loan), currencyAmount);
    }

    function decDebt(DataTypes.Storage storage _poolStorage,uint256 loan, uint256 currencyAmount) private {
        // Storage storage $ = _getStorage();
        uint256 rate = _poolStorage.loanRates[loan];
        require(block.timestamp == _poolStorage.rates[rate].lastUpdated, 'rate-group-not-updated');
        uint256 penaltyChi_ = _poolStorage.rates[rate].penaltyChi;
        if (penaltyChi_ > 0) {
            currencyAmount = toPie(penaltyChi_, currencyAmount);
        }
        uint256 pieAmount = toPie(_poolStorage.rates[rate].chi, currencyAmount);

        _poolStorage.pie[loan] = Math.safeSub(_poolStorage.pie[loan], pieAmount);
        _poolStorage.rates[rate].pie = Math.safeSub(_poolStorage.rates[rate].pie, pieAmount);

        emit DecreaseDebt(nftID(loan), currencyAmount);
    }

    function debt(DataTypes.Storage storage _poolStorage,uint256 loan) internal view  returns (uint256 loanDebt) {
        return GenericLogic.debt(_poolStorage, loan);
    }

    function rateDebt(DataTypes.Storage storage _poolStorage,uint256 rate) internal view returns (uint256 totalDebt) {
        return GenericLogic.rateDebt(_poolStorage, rate);
    }

    function setRate(DataTypes.Storage storage _poolStorage,uint256 loan, uint256 rate) internal {
        GenericLogic.setRate(_poolStorage, loan, rate);
    }

    function changeRate(DataTypes.Storage storage _poolStorage,uint256 loan, uint256 newRate) internal {
        GenericLogic.changeRate(_poolStorage, loan, newRate);
    }

    function accrue(DataTypes.Storage storage _poolStorage,uint256 loan) internal {
        drip(_poolStorage,_poolStorage.loanRates[loan]);
    }

    function drip(DataTypes.Storage storage _poolStorage,uint256 rate) internal {
        GenericLogic.drip(_poolStorage, rate);
    }

    // convert debt/savings amount to pie
    function toPie(uint chi, uint amount) internal pure returns (uint) {
        return Math.rdivup(amount, chi);
    }

    function getAsset(DataTypes.Storage storage _poolStorage,bytes32 agreementId) internal view  returns (DataTypes.NFTDetails memory) {
        return GenericLogic.getAsset(_poolStorage, agreementId);
    }
}
