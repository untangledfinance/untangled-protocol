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

import {ERC165Upgradeable} from '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol';
import {IERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol';
import {IERC721ReceiverUpgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC721ReceiverUpgradeable.sol';
import {ReentrancyGuardUpgradeable} from '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

import {PausableUpgradeable} from '../../base/PauseableUpgradeable.sol';
import {IUntangledERC721} from '../../interfaces/IUntangledERC721.sol';
import {ICrowdSale} from '../note-sale/crowdsale/ICrowdSale.sol';
import {ISecuritizationPool} from './ISecuritizationPool.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {UntangledMath} from '../../libraries/UntangledMath.sol';
import {Registry} from '../../storage/Registry.sol';
import {Discounting} from './libs/discounting.sol';
import {POOL, ONE_HUNDRED_PERCENT, RATE_SCALING_FACTOR, WRITEOFF_RATE_GROUP_START} from './types.sol';

import {ISecuritizationPoolStorage} from './ISecuritizationPoolStorage.sol';
import {RegistryInjection} from './RegistryInjection.sol';
import {SecuritizationAccessControl} from './SecuritizationAccessControl.sol';
import {ISecuritizationAccessControl} from './ISecuritizationAccessControl.sol';
import {ISecuritizationPoolNAV} from './ISecuritizationPoolNAV.sol';
import {RiskScore, LoanEntry} from './base/types.sol';
import {SecuritizationPoolStorage} from './SecuritizationPoolStorage.sol';
import {ISecuritizationPoolExtension, SecuritizationPoolExtension} from './SecuritizationPoolExtension.sol';
import 'contracts/libraries/UnpackLoanParamtersLib.sol';

/**
 * @title Untangled's SecuritizaionPoolNAV contract
 * @notice Main entry point for senior LPs (a.k.a. capital providers)
 *  Automatically invests across borrower pools using an adjustable strategy.
 * @author Untangled Team
 */
contract SecuritizationPoolNAV is
    Discounting,
    ERC165Upgradeable,
    RegistryInjection,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    SecuritizationPoolStorage,
    SecuritizationAccessControl,
    ISecuritizationPoolNAV
{
    using ConfigHelper for Registry;

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC165Upgradeable, SecuritizationAccessControl, SecuritizationPoolStorage)
        returns (bool)
    {
        return
            super.supportsInterface(interfaceId) ||
            interfaceId == type(ISecuritizationPoolExtension).interfaceId ||
            interfaceId == type(ISecuritizationAccessControl).interfaceId ||
            interfaceId == type(ISecuritizationPoolStorage).interfaceId ||
            interfaceId == type(ISecuritizationPoolNAV).interfaceId;
    }

    function installExtension(
        bytes memory params
    ) public virtual override(SecuritizationAccessControl, SecuritizationPoolStorage) onlyCallInTargetPool {
        __SecuritizationPoolNAV_init_unchained();
    }

    function __SecuritizationPoolNAV_init_unchained() internal {
        Storage storage $ = _getStorage();
        $.lastNAVUpdate = uniqueDayTimestamp(block.timestamp);

        // pre-definition for loans without interest rates
        $.rates[0].chi = ONE;
        $.rates[0].ratePerSecond = ONE;

        // Default discount rate
        $.discountRate = ONE;
    }

    modifier onlySecuritizationPool() {
        require(_msgSender() == address(this), 'SecuritizationPool: Only SecuritizationPool');
        _;
    }

    /** GETTER */
    /// @notice getter function for the maturityDate
    /// @param nft_ the id of the nft based on the hash of registry and tokenId
    /// @return maturityDate_ the maturityDate of the nft
    function maturityDate(bytes32 nft_) public view override returns (uint256 maturityDate_) {
        Storage storage $ = _getStorage();
        return uint256($.details[nft_].maturityDate);
    }

    /// @notice getter function for the risk group
    /// @param nft_ the id of the nft based on the hash of registry and tokenId
    /// @return risk_ the risk group of the nft

    function risk(bytes32 nft_) public view returns (uint256 risk_) {
        Storage storage $ = _getStorage();
        return uint256($.details[nft_].risk);
    }

    /// @notice getter function for the nft value
    /// @param nft_ the id of the nft based on the hash of registry and tokenId
    /// @return nftValue_ the value of the nft

    /// @notice getter function for the future value
    /// @param nft_ the id of the nft based on the hash of registry and tokenId
    /// @return fv_ future value of the loan
    function futureValue(bytes32 nft_) public view override returns (uint256 fv_) {
        Storage storage $ = _getStorage();
        return uint256($.details[nft_].futureValue);
    }

    function discountRate() public view override returns (uint256) {
        return uint256(_getStorage().discountRate);
    }

    /// @notice getter function for the recovery rate PD
    /// @param riskID id of a risk group
    /// @return recoveryRatePD_ recovery rate PD of the risk group
    function recoveryRatePD(uint256 riskID, uint256 termLength) public view returns (uint256 recoveryRatePD_) {
        RiskScore memory riskParam = getRiskScoreByIdx(riskID);
        return
            ONE -
            (ONE * riskParam.probabilityOfDefault * riskParam.lossGivenDefault * termLength) /
            (ONE_HUNDRED_PERCENT * ONE_HUNDRED_PERCENT * 365 days);
    }

    /// @notice getter function for the borrowed amount
    /// @param loan id of a loan
    /// @return borrowed_ borrowed amount of the loan
    function borrowed(uint256 loan) public view returns (uint256 borrowed_) {
        return uint256(_getStorage().loanDetails[loan].borrowed);
    }

    /** UTILITY FUNCTION */
    function getRiskScoreByIdx(uint256 idx) private view returns (RiskScore memory) {
        ISecuritizationPool securitizationPool = ISecuritizationPool(address(this));
        require(address(securitizationPool) != address(0), 'Pool was not deployed');
        if (idx == 0 || securitizationPool.getRiskScoresLength() == 0) {
            // Default risk score
            return
                RiskScore({
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
        return securitizationPool.riskScores(idx);
    }

    function addLoan(uint256 loan, LoanEntry calldata loanEntry) public onlySecuritizationPool returns (uint256) {
        Storage storage $ = _getStorage();
        bytes32 _tokenId = bytes32(loan);
        UnpackLoanParamtersLib.InterestParams memory loanParam = unpackParamsForAgreementID(loanEntry);

        $.details[_tokenId].risk = loanEntry.riskScore;
        $.details[_tokenId].debtor = loanEntry.debtor;
        $.details[_tokenId].expirationTimestamp = loanEntry.expirationTimestamp;
        $.details[_tokenId].principalTokenAddress = loanEntry.principalTokenAddress;
        $.details[_tokenId].salt = loanEntry.salt;
        $.details[_tokenId].issuanceBlockTimestamp = loanEntry.issuanceBlockTimestamp;
        $.details[_tokenId].assetPurpose = loanEntry.assetPurpose;
        $.details[_tokenId].termsParam = loanEntry.termsParam;

        $.details[_tokenId].principalAmount = loanParam.principalAmount;
        $.details[_tokenId].termStartUnixTimestamp = loanParam.termStartUnixTimestamp;
        $.details[_tokenId].termEndUnixTimestamp = loanParam.termEndUnixTimestamp;
        $.details[_tokenId].amortizationUnitType = loanParam.amortizationUnitType;
        $.details[_tokenId].termLengthInAmortizationUnits = loanParam.termLengthInAmortizationUnits;
        $.details[_tokenId].interestRate = loanParam.interestRate;

        RiskScore memory riskParam = getRiskScoreByIdx(loanEntry.riskScore);
        uint256 principalAmount = loanParam.principalAmount;
        uint256 _convertedInterestRate;

        principalAmount = (principalAmount * riskParam.advanceRate) / (ONE_HUNDRED_PERCENT);
        _convertedInterestRate = ONE + (riskParam.interestRate * ONE) / (ONE_HUNDRED_PERCENT * 365 days);

        $.loanToNFT[$.loanCount] = _tokenId;
        $.loanCount++;
        setLoanMaturityDate(_tokenId, loanParam.termEndUnixTimestamp);
        if ($.rates[_convertedInterestRate].ratePerSecond == 0) {
            // If interest rate is not set
            _file('rate', _convertedInterestRate, _convertedInterestRate);
        }
        setRate(loan, _convertedInterestRate);
        accrue(loan);

        $.balances[loan] = safeAdd($.balances[loan], principalAmount);
        $.balance = safeAdd($.balance, principalAmount);

        // increase NAV
        borrow(loan, principalAmount);
        _incDebt(loan, principalAmount);

        emit AddLoan(_tokenId, principalAmount, $.details[_tokenId]);

        return principalAmount;
    }

    /// @notice converts a uint256 to uint128
    /// @param value the value to be converted
    /// @return converted value to uint128
    function toUint128(uint256 value) internal pure returns (uint128 converted) {
        require(value <= type(uint128).max, "SafeCast: value doesn't fit in 128 bits");
        return uint128(value);
    }

    function setLoanMaturityDate(bytes32 nftID_, uint256 maturityDate_) internal {
        require((futureValue(nftID_) == 0), 'can-not-change-maturityDate-outstanding-debt');
        Storage storage $ = _getStorage();
        $.details[nftID_].maturityDate = toUint128(uniqueDayTimestamp(maturityDate_));
        emit SetLoanMaturity(nftID_, maturityDate_);
    }

    /// @notice file allows governance to change parameters of the contract
    /// @param name name of the parameter
    /// @param value new value of the parameter
    function file(bytes32 name, uint256 value) public override onlySecuritizationPool {
        if (name == 'discountRate') {
            Storage storage $ = _getStorage();
            uint256 oldDiscountRate = $.discountRate;
            $.discountRate = ONE + (value * ONE) / (ONE_HUNDRED_PERCENT * 365 days);
            // the nav needs to be re-calculated based on the new discount rate
            // no need to recalculate it if initialized the first time
            if (oldDiscountRate != 0) {
                reCalcNAV();
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
        bytes32 name,
        uint256 rate_,
        uint256 writeOffPercentage_,
        uint256 overdueDays_,
        uint256 penaltyRate_,
        uint256 riskIndex
    ) public override onlySecuritizationPool {
        if (name == 'writeOffGroup') {
            Storage storage $ = _getStorage();
            uint256 index = $.writeOffGroups.length;
            uint256 _convertedInterestRate = ONE + (rate_ * ONE) / (ONE_HUNDRED_PERCENT * 365 days);
            uint256 _convertedWriteOffPercentage = ONE - (writeOffPercentage_ * ONE) / ONE_HUNDRED_PERCENT;
            uint256 _convertedPenaltyRate = ONE +
                (ONE * penaltyRate_ * rate_) /
                (ONE_HUNDRED_PERCENT * ONE_HUNDRED_PERCENT * 365 days);
            uint256 _convertedOverdueDays = overdueDays_ / 1 days;
            $.writeOffGroups.push(
                WriteOffGroup(
                    toUint128(_convertedWriteOffPercentage),
                    toUint128(_convertedOverdueDays),
                    toUint128(riskIndex)
                )
            );
            _file('rate', safeAdd(WRITEOFF_RATE_GROUP_START, index), _convertedInterestRate);
            _file('penalty', safeAdd(WRITEOFF_RATE_GROUP_START, index), _convertedPenaltyRate);
        } else {
            revert('unknown name');
        }
    }

    /// @notice file manages different state configs for the pile
    /// only a ward can call this function
    /// @param what what config to change
    /// @param rate the interest rate group
    /// @param value the value to change
    function _file(bytes32 what, uint256 rate, uint256 value) private {
        Storage storage $ = _getStorage();
        if (what == 'rate') {
            require(value != 0, 'rate-per-second-can-not-be-0');
            if ($.rates[rate].chi == 0) {
                $.rates[rate].chi = ONE;
                $.rates[rate].lastUpdated = uint48(block.timestamp);
            } else {
                drip(rate);
            }
            $.rates[rate].ratePerSecond = value;
        } else if (what == 'penalty') {
            require(value != 0, 'penalty-per-second-can-not-be-0');
            if ($.rates[rate].penaltyChi == 0) {
                $.rates[rate].penaltyChi = ONE;
                $.rates[rate].lastUpdated = uint48(block.timestamp);
            } else {
                drip(rate);
            }

            $.rates[rate].penaltyRatePerSecond = value;
        } else {
            revert('unknown parameter');
        }
    }

    /// @notice borrow updates the NAV for a new borrowed loan
    /// @param loan the id of the loan
    /// @param amount the amount borrowed
    /// @return navIncrease the increase of the NAV impacted by the new borrow
    function borrow(uint256 loan, uint256 amount) private returns (uint256 navIncrease) {
        uint256 nnow = uniqueDayTimestamp(block.timestamp);
        bytes32 nftID_ = nftID(loan);
        uint256 maturityDate_ = maturityDate(nftID_);

        require(maturityDate_ > nnow, 'maturity-date-is-not-in-the-future');

        Storage storage $ = _getStorage();

        if (nnow > $.lastNAVUpdate) {
            calcUpdateNAV();
        }

        // uint256 beforeNAV = latestNAV;

        // calculate amount including fixed fee if applicatable
        Rate memory _rate = $.rates[$.loanRates[loan]];

        // calculate future value FV
        NFTDetails memory nftDetail = getAsset(bytes32(loan));
        uint256 fv = calcFutureValue(
            _rate.ratePerSecond,
            amount,
            maturityDate_,
            recoveryRatePD(nftDetail.risk, nftDetail.expirationTimestamp - nftDetail.issuanceBlockTimestamp)
        );
        $.details[nftID_].futureValue = toUint128(safeAdd(futureValue(nftID_), fv));

        // add future value to the bucket of assets with the same maturity date
        $.buckets[maturityDate_] = safeAdd($.buckets[maturityDate_], fv);

        // increase borrowed amount for future ceiling computations
        $.loanDetails[loan].borrowed = toUint128(safeAdd(borrowed(loan), amount));

        // return increase NAV amount
        navIncrease = calcDiscount($.discountRate, fv, nnow, maturityDate_);
        $.latestDiscount = safeAdd($.latestDiscount, navIncrease);
        $.latestDiscountOfNavAssets[nftID_] += navIncrease;

        $.latestNAV = safeAdd($.latestNAV, navIncrease);

        return navIncrease;
    }

    function _decreaseLoan(uint256 loan, uint256 amount) private {
        Storage storage $ = _getStorage();
        $.latestNAV = secureSub(
            $.latestNAV,
            rmul(amount, toUint128($.writeOffGroups[$.loanRates[loan] - WRITEOFF_RATE_GROUP_START].percentage))
        );
        decDebt(loan, amount);
    }

    function _calcFutureValue(uint256 loan, uint256 _debt, uint256 _maturityDate) private view returns (uint256) {
        Storage storage $ = _getStorage();
        Rate memory _rate = $.rates[$.loanRates[loan]];
        NFTDetails memory nftDetail = getAsset(nftID(loan));
        uint256 fv = calcFutureValue(
            _rate.ratePerSecond,
            _debt,
            _maturityDate,
            recoveryRatePD(nftDetail.risk, nftDetail.expirationTimestamp - nftDetail.issuanceBlockTimestamp)
        );
        return fv;
    }

    /// @notice repay updates the NAV for a new repaid loan
    /// @param loan the id of the loan
    /// @param amount the amount repaid
    function repayLoan(uint256 loan, uint256 amount) external returns (uint256) {
        require(address(registry().getLoanRepaymentRouter()) == msg.sender, 'not authorized');
        accrue(loan);
        uint256 nnow = uniqueDayTimestamp(block.timestamp);
        Storage storage $ = _getStorage();
        if (nnow > $.lastNAVUpdate) {
            calcUpdateNAV();
        }

        // In case of successful repayment the latestNAV is decreased by the repaid amount
        bytes32 nftID_ = nftID(loan);
        uint256 maturityDate_ = maturityDate(nftID_);

        uint256 _currentDebt = debt(loan);
        if (amount > _currentDebt) {
            amount = _currentDebt;
        }
        // case 1: repayment of a written-off loan
        if (isLoanWrittenOff(loan)) {
            // update nav with write-off decrease
            _decreaseLoan(loan, amount);
            return amount;
        }
        uint256 _debt = safeSub(_currentDebt, amount); // Remaining
        uint256 preFV = futureValue(nftID_);
        // in case of partial repayment, compute the fv of the remaining debt and add to the according fv bucket
        uint256 fv = 0;
        uint256 fvDecrease = preFV;
        if (_debt != 0) {
            fv = _calcFutureValue(loan, _debt, maturityDate_);
            if (preFV >= fv) {
                fvDecrease = safeSub(preFV, fv);
            } else {
                fvDecrease = 0;
            }
        }

        $.details[nftID_].futureValue = toUint128(fv);

        // case 2: repayment of a loan before or on maturity date
        if (maturityDate_ >= nnow) {
            // remove future value decrease from bucket
            $.buckets[maturityDate_] = safeSub($.buckets[maturityDate_], fvDecrease);

            uint256 discountDecrease = calcDiscount($.discountRate, fvDecrease, nnow, maturityDate_);

            $.latestDiscount = secureSub($.latestDiscount, discountDecrease);
            $.latestDiscountOfNavAssets[nftID_] = secureSub($.latestDiscountOfNavAssets[nftID_], discountDecrease);

            $.latestNAV = secureSub($.latestNAV, discountDecrease);
        } else {
            // case 3: repayment of an overdue loan
            $.overdueLoans = safeSub($.overdueLoans, fvDecrease);
            $.overdueLoansOfNavAssets[nftID_] = safeSub($.overdueLoansOfNavAssets[nftID_], fvDecrease);
            $.latestNAV = secureSub($.latestNAV, fvDecrease);
        }

        decDebt(loan, amount);

        emit Repay(nftID_, amount);
        return amount;
    }

    /// @notice writeOff writes off a loan if it is overdue
    /// @param loan the id of the loan
    function writeOff(uint256 loan) public {
        Storage storage $ = _getStorage();
        require(!$.loanDetails[loan].authWriteOff, 'only-auth-write-off');

        bytes32 nftID_ = nftID(loan);
        uint256 maturityDate_ = maturityDate(nftID_);
        require(maturityDate_ > 0, 'loan-does-not-exist');

        // can not write-off healthy loans
        uint256 nnow = uniqueDayTimestamp(block.timestamp);
        NFTDetails memory nftDetail = getAsset(bytes32(loan));
        RiskScore memory riskParam = getRiskScoreByIdx(nftDetail.risk);
        require(maturityDate_ + riskParam.gracePeriod <= nnow, 'maturity-date-in-the-future');
        // check the writeoff group based on the amount of days overdue
        uint256 writeOffGroupIndex_ = currentValidWriteOffGroup(loan);

        if (
            writeOffGroupIndex_ < type(uint128).max &&
            $.loanRates[loan] != WRITEOFF_RATE_GROUP_START + writeOffGroupIndex_
        ) {
            _writeOff(loan, writeOffGroupIndex_, nftID_, maturityDate_);
            emit WriteOff(nftID_, writeOffGroupIndex_, false);
        }
    }

    /// @notice internal function for the write off
    /// @param loan the id of the loan
    /// @param writeOffGroupIndex_ the index of the writeoff group
    /// @param nftID_ the nftID of the loan
    /// @param maturityDate_ the maturity date of the loan
    function _writeOff(uint256 loan, uint256 writeOffGroupIndex_, bytes32 nftID_, uint256 maturityDate_) internal {
        Storage storage $ = _getStorage();
        uint256 nnow = uniqueDayTimestamp(block.timestamp);
        // Ensure we have an up to date NAV
        if (nnow > $.lastNAVUpdate) {
            calcUpdateNAV();
        }

        uint256 latestNAV_ = $.latestNAV;

        // first time written-off
        if (isLoanWrittenOff(loan) == false) {
            uint256 fv = futureValue(nftID_);
            if (uniqueDayTimestamp($.lastNAVUpdate) > maturityDate_) {
                // write off after the maturity date
                $.overdueLoans = secureSub($.overdueLoans, fv);
                $.overdueLoansOfNavAssets[nftID_] = secureSub($.overdueLoansOfNavAssets[nftID_], fv);
                latestNAV_ = secureSub(latestNAV_, fv);
            } else {
                // write off before or on the maturity date
                $.buckets[maturityDate_] = safeSub($.buckets[maturityDate_], fv);

                uint256 pv = rmul(fv, rpow($.discountRate, safeSub(uniqueDayTimestamp(maturityDate_), nnow), ONE));
                $.latestDiscount = secureSub($.latestDiscount, pv);
                $.latestDiscountOfNavAssets[nftID_] = secureSub($.latestDiscountOfNavAssets[nftID_], pv);

                latestNAV_ = secureSub(latestNAV_, pv);
            }
        }

        changeRate(loan, WRITEOFF_RATE_GROUP_START + writeOffGroupIndex_);
        $.latestNAV = safeAdd(latestNAV_, rmul(debt(loan), $.writeOffGroups[writeOffGroupIndex_].percentage));
    }

    /// @notice returns if a loan is written off
    /// @param loan the id of the loan
    function isLoanWrittenOff(uint256 loan) public view returns (bool) {
        return _getStorage().loanRates[loan] >= WRITEOFF_RATE_GROUP_START;
    }

    /// @notice calculates and returns the current NAV
    /// @return nav_ current NAV
    function currentNAV() public view override returns (uint256 nav_) {
        (uint256 totalDiscount, uint256 overdue, uint256 writeOffs) = currentPVs();
        return safeAdd(totalDiscount, safeAdd(overdue, writeOffs));
    }

    function currentNAVAsset(bytes32 tokenId) public view override returns (uint256) {
        (uint256 totalDiscount, uint256 overdue, uint256 writeOffs) = currentAV(tokenId);
        return safeAdd(totalDiscount, safeAdd(overdue, writeOffs));
    }

    /// @notice calculates the present value of the loans together with overdue and written off loans
    /// @return totalDiscount the present value of the loans
    /// @return overdue the present value of the overdue loans
    /// @return writeOffs the present value of the written off loans
    function currentPVs() public view returns (uint256 totalDiscount, uint256 overdue, uint256 writeOffs) {
        Storage storage $ = _getStorage();
        if ($.latestDiscount == 0) {
            // all loans are overdue or writtenOff
            return (0, $.overdueLoans, currentWriteOffs());
        }

        uint256 errPV = 0;
        uint256 nnow = uniqueDayTimestamp(block.timestamp);

        // find all new overdue loans since the last update
        // calculate the discount of the overdue loans which is needed
        // for the total discount calculation
        for (uint256 i = $.lastNAVUpdate; i < nnow; i = i + 1 days) {
            uint256 b = $.buckets[i];
            if (b != 0) {
                errPV = safeAdd(errPV, rmul(b, rpow($.discountRate, safeSub(nnow, i), ONE)));
                overdue = safeAdd(overdue, b);
            }
        }

        return (
            // calculate current totalDiscount based on the previous totalDiscount (optimized calculation)
            // the overdue loans are incorrectly in this new result with their current PV and need to be removed
            secureSub(rmul($.latestDiscount, rpow($.discountRate, safeSub(nnow, $.lastNAVUpdate), ONE)), errPV),
            // current overdue loans not written off
            safeAdd($.overdueLoans, overdue),
            // current write-offs loans
            currentWriteOffs()
        );
    }

    function currentWriteOffAsset(bytes32 tokenId) public view returns (uint256) {
        Storage storage $ = _getStorage();
        uint256 _currentWriteOffs = 0;
        uint256 writeOffGroupIndex = currentValidWriteOffGroup(uint256(tokenId));
        _currentWriteOffs = rmul(debt(uint256(tokenId)), uint256($.writeOffGroups[writeOffGroupIndex].percentage));
        return _currentWriteOffs;
    }

    function currentAV(
        bytes32 tokenId
    ) public view returns (uint256 totalDiscount, uint256 overdue, uint256 writeOffs) {
        Storage storage $ = _getStorage();
        uint256 _currentWriteOffs = 0;

        if (isLoanWrittenOff(uint256(tokenId))) {
            uint256 writeOffGroupIndex = currentValidWriteOffGroup(uint256(tokenId));
            _currentWriteOffs = rmul(debt(uint256(tokenId)), uint256($.writeOffGroups[writeOffGroupIndex].percentage));
        }

        if ($.latestDiscountOfNavAssets[tokenId] == 0) {
            // all loans are overdue or writtenOff
            return (0, $.overdueLoansOfNavAssets[tokenId], _currentWriteOffs);
        }

        uint256 errPV = 0;
        uint256 nnow = uniqueDayTimestamp(block.timestamp);

        // loan is overdue since lastNAVUpdate
        uint256 mat = uniqueDayTimestamp(maturityDate(tokenId));
        if (mat >= $.lastNAVUpdate && mat < nnow) {
            uint256 b = futureValue(tokenId);
            errPV = rmul(b, rpow($.discountRate, safeSub(nnow, mat), ONE));
            overdue = b;
        }

        return (
            secureSub(
                rmul($.latestDiscountOfNavAssets[tokenId], rpow($.discountRate, safeSub(nnow, $.lastNAVUpdate), ONE)),
                errPV
            ),
            safeAdd($.overdueLoansOfNavAssets[tokenId], overdue),
            _currentWriteOffs
        );
    }

    /// @notice returns the sum of all write off loans
    /// @return sum of all write off loans
    function currentWriteOffs() public view returns (uint256 sum) {
        Storage storage $ = _getStorage();
        for (uint256 i = 0; i < $.writeOffGroups.length; i++) {
            // multiply writeOffGroupDebt with the writeOff rate

            sum = safeAdd(sum, rmul(rateDebt(WRITEOFF_RATE_GROUP_START + i), uint256($.writeOffGroups[i].percentage)));
        }
        return sum;
    }

    /// @notice calculates and returns the current NAV and updates the state
    /// @return nav_ current NAV
    function calcUpdateNAV() public returns (uint256 nav_) {
        (uint256 totalDiscount, uint256 overdue, uint256 writeOffs) = currentPVs();
        Storage storage $ = _getStorage();

        for (uint i = 0; i < $.loanCount; ++i) {
            bytes32 _nftID = $.loanToNFT[i];

            (uint256 td, uint256 ol, ) = currentAV(_nftID);
            $.overdueLoansOfNavAssets[_nftID] = ol;
            $.latestDiscountOfNavAssets[_nftID] = td;
        }

        $.overdueLoans = overdue;
        $.latestDiscount = totalDiscount;

        $.latestNAV = safeAdd(safeAdd(totalDiscount, overdue), writeOffs);
        $.lastNAVUpdate = uniqueDayTimestamp(block.timestamp);
        return $.latestNAV;
    }

    /// @notice re-calculates the nav in a non-optimized way
    ///  the method is not updating the NAV to latest block.timestamp
    /// @return nav_ current NAV
    function reCalcNAV() public returns (uint256 nav_) {
        // reCalcTotalDiscount
        /// @notice re-calculates the totalDiscount in a non-optimized way based on lastNAVUpdate
        /// @return latestDiscount_ returns the total discount of the active loans
        Storage storage $ = _getStorage();
        uint256 latestDiscount_ = 0;
        for (uint256 loanID = 1; loanID < $.loanCount; loanID++) {
            bytes32 nftID_ = nftID(loanID);
            uint256 maturityDate_ = maturityDate(nftID_);

            if (maturityDate_ < $.lastNAVUpdate) {
                continue;
            }

            uint256 discountIncrease_ = calcDiscount(
                $.discountRate,
                futureValue(nftID_),
                $.lastNAVUpdate,
                maturityDate_
            );
            latestDiscount_ = safeAdd(latestDiscount_, discountIncrease_);
            $.latestDiscountOfNavAssets[nftID_] = discountIncrease_;
        }

        $.latestNAV = safeAdd(latestDiscount_, safeSub($.latestNAV, $.latestDiscount));
        $.latestDiscount = latestDiscount_;

        return $.latestNAV;
    }

    /// @notice updates the risk group of active loans (borrowed and unborrowed loans)
    /// @param nftID_ the nftID of the loan
    /// @param risk_ the new value appraisal of the collateral NFT
    /// @param risk_ the new risk group
    function updateAssetRiskScore(bytes32 nftID_, uint256 risk_) public {
        registry().requirePoolAdmin(_msgSender());
        uint256 nnow = uniqueDayTimestamp(block.timestamp);

        // no change in risk group
        if (risk_ == risk(nftID_)) {
            return;
        }

        Storage storage $ = _getStorage();
        $.details[nftID_].risk = toUint128(risk_);

        // update nav -> latestNAVUpdate = now
        if (nnow > $.lastNAVUpdate) {
            calcUpdateNAV();
        }

        // switch of collateral risk group results in new: ceiling, threshold and interest rate for existing loan
        // change to new rate interestRate immediately in pile if loan debt exists
        uint256 loan = uint256(nftID_);
        if ($.pie[loan] != 0) {
            RiskScore memory riskParam = getRiskScoreByIdx(risk_);
            uint256 _convertedInterestRate = ONE + (riskParam.interestRate * ONE) / (ONE_HUNDRED_PERCENT * 365 days);
            if ($.rates[_convertedInterestRate].ratePerSecond == 0) {
                // If interest rate is not set
                _file('rate', _convertedInterestRate, _convertedInterestRate);
            }
            changeRate(loan, _convertedInterestRate);
            $.details[nftID_].interestRate = riskParam.interestRate;
        }

        // no currencyAmount borrowed yet
        if (futureValue(nftID_) == 0) {
            return;
        }

        uint256 maturityDate_ = maturityDate(nftID_);

        // Changing the risk group of an nft, might lead to a new interest rate for the dependant loan.
        // New interest rate leads to a future value.
        // recalculation required
        uint256 fvDecrease = futureValue(nftID_);

        uint256 navDecrease = calcDiscount($.discountRate, fvDecrease, nnow, maturityDate_);

        $.buckets[maturityDate_] = safeSub($.buckets[maturityDate_], fvDecrease);

        $.latestDiscount = secureSub($.latestDiscount, navDecrease);
        $.latestDiscountOfNavAssets[nftID_] = secureSub($.latestDiscountOfNavAssets[nftID_], navDecrease);

        $.latestNAV = secureSub($.latestNAV, navDecrease);

        // update latest NAV
        // update latest Discount
        Rate memory _rate = $.rates[$.loanRates[loan]];
        NFTDetails memory nftDetail = getAsset(bytes32(loan));
        $.details[nftID_].futureValue = toUint128(
            calcFutureValue(
                _rate.ratePerSecond,
                debt(loan),
                maturityDate(nftID_),
                recoveryRatePD(risk_, nftDetail.expirationTimestamp - nftDetail.issuanceBlockTimestamp)
            )
        );

        uint256 fvIncrease = futureValue(nftID_);
        uint256 navIncrease = calcDiscount($.discountRate, fvIncrease, nnow, maturityDate_);

        $.buckets[maturityDate_] = safeAdd($.buckets[maturityDate_], fvIncrease);

        $.latestDiscount = safeAdd($.latestDiscount, navIncrease);
        $.latestDiscountOfNavAssets[nftID_] += navIncrease;

        $.latestNAV = safeAdd($.latestNAV, navIncrease);
        emit UpdateAssetRiskScore(nftID_, risk_);
    }

    /// @notice returns the nftID for the underlying collateral nft
    /// @param loan the loan id
    /// @return nftID_ the nftID of the loan
    function nftID(uint256 loan) public pure returns (bytes32 nftID_) {
        return bytes32(loan);
    }

    /// @notice returns the current valid write off group of a loan
    /// @param loan the loan id
    /// @return writeOffGroup_ the current valid write off group of a loan
    function currentValidWriteOffGroup(uint256 loan) public view returns (uint256 writeOffGroup_) {
        bytes32 nftID_ = nftID(loan);
        uint256 maturityDate_ = maturityDate(nftID_);
        uint256 nnow = uniqueDayTimestamp(block.timestamp);

        NFTDetails memory nftDetail = getAsset(nftID_);

        uint128 _loanRiskIndex = nftDetail.risk - 1;

        uint128 lastValidWriteOff = type(uint128).max;
        uint128 highestOverdueDays = 0;
        Storage storage $ = _getStorage();
        // it is not guaranteed that writeOff groups are sorted by overdue days
        for (uint128 i = 0; i < $.writeOffGroups.length; i++) {
            uint128 overdueDays = $.writeOffGroups[i].overdueDays;
            if (
                $.writeOffGroups[i].riskIndex == _loanRiskIndex &&
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

    function _incDebt(uint256 loan, uint256 currencyAmount) private {
        Storage storage $ = _getStorage();
        uint256 rate = $.loanRates[loan];
        require(block.timestamp == $.rates[rate].lastUpdated, 'rate-group-not-updated');
        uint256 pieAmount = toPie($.rates[rate].chi, currencyAmount);

        $.pie[loan] = safeAdd($.pie[loan], pieAmount);
        $.rates[rate].pie = safeAdd($.rates[rate].pie, pieAmount);

        emit IncreaseDebt(nftID(loan), currencyAmount);
    }

    function decDebt(uint256 loan, uint256 currencyAmount) private {
        Storage storage $ = _getStorage();
        uint256 rate = $.loanRates[loan];
        require(block.timestamp == $.rates[rate].lastUpdated, 'rate-group-not-updated');
        uint256 penaltyChi_ = $.rates[rate].penaltyChi;
        if (penaltyChi_ > 0) {
            currencyAmount = toPie(penaltyChi_, currencyAmount);
        }
        uint256 pieAmount = toPie($.rates[rate].chi, currencyAmount);

        $.pie[loan] = safeSub($.pie[loan], pieAmount);
        $.rates[rate].pie = safeSub($.rates[rate].pie, pieAmount);

        emit DecreaseDebt(nftID(loan), currencyAmount);
    }

    function debt(uint256 loan) public view override returns (uint256 loanDebt) {
        Storage storage $ = _getStorage();
        uint256 rate_ = $.loanRates[loan];
        uint256 chi_ = $.rates[rate_].chi;
        uint256 penaltyChi_ = $.rates[rate_].penaltyChi;
        if (block.timestamp >= $.rates[rate_].lastUpdated) {
            chi_ = chargeInterest($.rates[rate_].chi, $.rates[rate_].ratePerSecond, $.rates[rate_].lastUpdated);
            penaltyChi_ = chargeInterest(
                $.rates[rate_].penaltyChi,
                $.rates[rate_].penaltyRatePerSecond,
                $.rates[rate_].lastUpdated
            );
        }

        if (penaltyChi_ == 0) {
            return toAmount(chi_, $.pie[loan]);
        } else {
            return toAmount(penaltyChi_, toAmount(chi_, $.pie[loan]));
        }
    }

    function rateDebt(uint256 rate) public view returns (uint256 totalDebt) {
        Storage storage $ = _getStorage();
        uint256 chi_ = $.rates[rate].chi;
        uint256 penaltyChi_ = $.rates[rate].penaltyChi;
        uint256 pie_ = $.rates[rate].pie;

        if (block.timestamp >= $.rates[rate].lastUpdated) {
            chi_ = chargeInterest($.rates[rate].chi, $.rates[rate].ratePerSecond, $.rates[rate].lastUpdated);
            penaltyChi_ = chargeInterest(
                $.rates[rate].penaltyChi,
                $.rates[rate].penaltyRatePerSecond,
                $.rates[rate].lastUpdated
            );
        }

        if (penaltyChi_ == 0) {
            return toAmount(chi_, pie_);
        } else {
            return toAmount(penaltyChi_, toAmount(chi_, pie_));
        }
    }

    function setRate(uint256 loan, uint256 rate) internal {
        Storage storage $ = _getStorage();
        require($.pie[loan] == 0, 'non-zero-debt');
        // rate category has to be initiated
        require($.rates[rate].chi != 0, 'rate-group-not-set');
        $.loanRates[loan] = rate;
        emit SetRate(nftID(loan), rate);
    }

    function changeRate(uint256 loan, uint256 newRate) internal {
        Storage storage $ = _getStorage();
        require($.rates[newRate].chi != 0, 'rate-group-not-set');
        if (newRate >= WRITEOFF_RATE_GROUP_START) {
            $.rates[newRate].timeStartPenalty = uint48(block.timestamp);
        }
        uint256 currentRate = $.loanRates[loan];
        drip(currentRate);
        drip(newRate);
        uint256 pie_ = $.pie[loan];
        uint256 debt_ = toAmount($.rates[currentRate].chi, pie_);
        $.rates[currentRate].pie = safeSub($.rates[currentRate].pie, pie_);
        $.pie[loan] = toPie($.rates[newRate].chi, debt_);
        $.rates[newRate].pie = safeAdd($.rates[newRate].pie, $.pie[loan]);
        $.loanRates[loan] = newRate;
        emit ChangeRate(nftID(loan), newRate);
    }

    function accrue(uint256 loan) internal {
        drip(_getStorage().loanRates[loan]);
    }

    function drip(uint256 rate) internal {
        Storage storage $ = _getStorage();
        if (block.timestamp >= $.rates[rate].lastUpdated) {
            (uint256 chi, ) = compounding(
                $.rates[rate].chi,
                $.rates[rate].ratePerSecond,
                $.rates[rate].lastUpdated,
                $.rates[rate].pie
            );
            $.rates[rate].chi = chi;
            if (
                $.rates[rate].penaltyRatePerSecond != 0 &&
                $.rates[rate].timeStartPenalty != 0 &&
                block.timestamp >= $.rates[rate].timeStartPenalty
            ) {
                uint lastUpdated_ = $.rates[rate].lastUpdated > $.rates[rate].timeStartPenalty
                    ? $.rates[rate].lastUpdated
                    : $.rates[rate].timeStartPenalty;
                (uint256 penaltyChi, ) = compounding(
                    $.rates[rate].penaltyChi,
                    $.rates[rate].penaltyRatePerSecond,
                    lastUpdated_,
                    $.rates[rate].pie
                );
                $.rates[rate].penaltyChi = penaltyChi;
            }
            $.rates[rate].lastUpdated = uint48(block.timestamp);
        }
    }

    /// Interest functions
    // @notice This function provides compounding in seconds
    // @param chi Accumulated interest rate over time
    // @param ratePerSecond Interest rate accumulation per second in RAD(10ˆ27)
    // @param lastUpdated When the interest rate was last updated
    // @param _pie Total sum of all amounts accumulating under one interest rate, divided by that rate
    // @return The new accumulated rate, as well as the difference between the debt calculated with the old and new accumulated rates.
    function compounding(uint chi, uint ratePerSecond, uint lastUpdated, uint _pie) public view returns (uint, uint) {
        require(block.timestamp >= lastUpdated, 'tinlake-math/invalid-timestamp');
        require(chi != 0);
        // instead of a interestBearingAmount we use a accumulated interest rate index (chi)
        uint updatedChi = _chargeInterest(chi, ratePerSecond, lastUpdated, block.timestamp);
        return (updatedChi, safeSub(rmul(updatedChi, _pie), rmul(chi, _pie)));
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
    ) public view returns (uint) {
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
        return rmul(rpow(ratePerSecond, current - lastUpdated, ONE), interestBearingAmount);
    }

    // convert pie to debt/savings amount
    function toAmount(uint chi, uint _pie) public pure returns (uint) {
        return rmul(_pie, chi);
    }

    // convert debt/savings amount to pie
    function toPie(uint chi, uint amount) public pure returns (uint) {
        return rdivup(amount, chi);
    }

    /// @inheritdoc ISecuritizationPoolNAV
    function getAsset(bytes32 agreementId) public view override returns (NFTDetails memory) {
        Storage storage $ = _getStorage();
        return $.details[agreementId];
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
        LoanEntry calldata loan
    ) private pure returns (UnpackLoanParamtersLib.InterestParams memory params) {
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

    function getFunctionSignatures()
        public
        view
        virtual
        override(SecuritizationAccessControl, SecuritizationPoolStorage)
        returns (bytes4[] memory)
    {
        bytes4[] memory _functionSignatures = new bytes4[](14);

        _functionSignatures[0] = this.addLoan.selector;
        _functionSignatures[1] = this.repayLoan.selector;
        _functionSignatures[2] = bytes4(keccak256(bytes('file(bytes32,uint256)')));
        _functionSignatures[3] = this.debt.selector;
        _functionSignatures[4] = this.risk.selector;
        _functionSignatures[5] = this.currentNAV.selector;
        _functionSignatures[6] = this.currentNAVAsset.selector;
        _functionSignatures[7] = this.futureValue.selector;
        _functionSignatures[8] = this.maturityDate.selector;
        _functionSignatures[9] = this.discountRate.selector;
        _functionSignatures[10] = this.updateAssetRiskScore.selector;
        _functionSignatures[11] = this.writeOff.selector;
        _functionSignatures[12] = bytes4(keccak256(bytes('file(bytes32,uint256,uint256,uint256,uint256,uint256)')));
        _functionSignatures[13] = this.getAsset.selector;

        return _functionSignatures;
    }
}
