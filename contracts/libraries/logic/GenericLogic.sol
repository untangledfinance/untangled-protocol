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
/**
 * @title Untangled's SecuritizaionPoolNAV contract
 * @notice Main entry point for senior LPs (a.k.a. capital providers)
 *  Automatically invests across borrower pools using an adjustable strategy.
 * @author Untangled Team
 */
library GenericLogic 
{
    // move to DataTypes later
    bytes32 constant OWNER_ROLE = keccak256('OWNER_ROLE');
    bytes32 constant POOL_ADMIN = keccak256('POOL_CREATOR');
    bytes32 constant ORIGINATOR_ROLE = keccak256('ORIGINATOR_ROLE');

    bytes32 constant BACKEND_ADMIN = keccak256('BACKEND_ADMIN');
    bytes32 constant SIGNER_ROLE = keccak256('SIGNER_ROLE');

    // In PoolNAV we use this
    bytes32 constant POOL = keccak256('POOL');

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

    // using ConfigHelper for Registry;

    // function supportsInterface(
    //     bytes4 interfaceId
    // )
    //     public
    //     view
    //     virtual
    //     (ERC165Upgradeable, SecuritizationAccessControl, SecuritizationPoolStorage)
    //     returns (bool)
    // {
    //     return
    //         super.supportsInterface(interfaceId) ||
    //         interfaceId == type(ISecuritizationPoolExtension).interfaceId ||
    //         interfaceId == type(ISecuritizationAccessControl).interfaceId ||
    //         interfaceId == type(ISecuritizationPoolStorage).interfaceId ||
    //         interfaceId == type(ISecuritizationPoolNAV).interfaceId;
    // }

    // function installExtension(
    //     bytes memory params
    // ) public virtual (SecuritizationAccessControl, SecuritizationPoolStorage) onlyCallInTargetPool {
    //     __SecuritizationPoolNAV_init_unchained();
    // }

    // function __SecuritizationPoolNAV_init_unchained() internal {
    //     Storage storage $ = _getStorage();
    //     $.lastNAVUpdate = Discounting.uniqueDayTimestamp(block.timestamp);

    //     // pre-definition for loans without interest rates
    //     $.rates[0].chi = Math.ONE;
    //     $.rates[0].ratePerSecond = Math.ONE;

    //     // Default discount rate
    //     $.discountRate = Math.ONE;
    // }

    // modifier onlySecuritizationPool() {
    //     require(_msgSender() == address(this), 'SecuritizationPool: Only SecuritizationPool');
    //     _;
    // }

    /** GETTER */
    /// @notice getter function for the maturityDate
    /// @param nft_ the id of the nft based on the hash of registry and tokenId
    /// @return maturityDate_ the maturityDate of the nft
    function maturityDate(DataTypes.Storage storage _poolStorage,bytes32 nft_) public view  returns (uint256 maturityDate_) {
        // Storage storage $ = _getStorage();
        return uint256(_poolStorage.details[nft_].maturityDate);
    }

    /// @notice getter function for the risk group
    /// @param nft_ the id of the nft based on the hash of registry and tokenId
    /// @return risk_ the risk group of the nft

    function risk(DataTypes.Storage storage _poolStorage,bytes32 nft_) public view returns (uint256 risk_) {
        // Storage storage $ = _getStorage();
        return uint256(_poolStorage.details[nft_].risk);
    }

    /// @notice getter function for the nft value
    /// @param nft_ the id of the nft based on the hash of registry and tokenId
    /// @return nftValue_ the value of the nft

    /// @notice getter function for the future value
    /// @param nft_ the id of the nft based on the hash of registry and tokenId
    /// @return fv_ future value of the loan
    function futureValue(DataTypes.Storage storage _poolStorage, bytes32 nft_) public view  returns (uint256 fv_) {
        // Storage storage $ = _getStorage();
        return uint256(_poolStorage.details[nft_].futureValue);
    }

    // function discountRate() public view  returns (uint256) {
    //     return uint256(_getStorage().discountRate);
    // }

    /// @notice getter function for the recovery rate PD
    /// @param riskID id of a risk group
    /// @return recoveryRatePD_ recovery rate PD of the risk group
    function recoveryRatePD(DataTypes.RiskScore[] storage riskScores,uint256 riskID, uint256 termLength) public view returns (uint256 recoveryRatePD_) {
        DataTypes.RiskScore memory riskParam = getRiskScoreByIdx(riskScores,riskID);
        return
            Math.ONE -
            (Math.ONE * riskParam.probabilityOfDefault * riskParam.lossGivenDefault * termLength) /
            (ONE_HUNDRED_PERCENT * ONE_HUNDRED_PERCENT * 365 days);
    }

    /// @notice getter function for the borrowed amount
    /// @param loan id of a loan
    /// @return borrowed_ borrowed amount of the loan
    function borrowed(DataTypes.Storage storage _poolStorage,uint256 loan) public view returns (uint256 borrowed_) {
        return uint256(_poolStorage.loanDetails[loan].borrowed);
    }

    /** UTILITY FUNCTION */
    // TODO have to use modifier in main contract
    function getRiskScoreByIdx(DataTypes.RiskScore[] storage riskScores,uint256 idx) private view returns (DataTypes.RiskScore memory) {
        // ISecuritizationPool securitizationPool = ISecuritizationPool(address(this));
        // require(address(securitizationPool) != address(0), 'Pool was not deployed');
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

    // TODO have to use modifier in main contract
    function addLoan(DataTypes.Storage storage _poolStorage, uint256 loan, DataTypes.LoanEntry calldata loanEntry) public returns (uint256) {
        bytes32 _tokenId = bytes32(loan);
        UnpackLoanParamtersLib.InterestParams memory loanParam = unpackParamsForAgreementID(loanEntry);

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

    /// @notice returns if a loan is written off
    /// @param loan the id of the loan
    function isLoanWrittenOff(DataTypes.Storage storage _poolStorage,uint256 loan) public view returns (bool) {
        return _poolStorage.loanRates[loan] >= WRITEOFF_RATE_GROUP_START;
    }

    /// @notice calculates and returns the current NAV
    /// @return nav_ current NAV
    function currentNAV(DataTypes.Storage storage _poolStorage) public view returns (uint256 nav_) {
        (uint256 totalDiscount, uint256 overdue, uint256 writeOffs) = currentPVs(_poolStorage);
        return Math.safeAdd(totalDiscount, Math.safeAdd(overdue, writeOffs));
    }

    function currentNAVAsset(DataTypes.Storage storage _poolStorage,bytes32 tokenId) public view returns (uint256) {
        (uint256 totalDiscount, uint256 overdue, uint256 writeOffs) = currentAV(_poolStorage,tokenId);
        return Math.safeAdd(totalDiscount, Math.safeAdd(overdue, writeOffs));
    }

    /// @notice calculates the present value of the loans together with overdue and written off loans
    /// @return totalDiscount the present value of the loans
    /// @return overdue the present value of the overdue loans
    /// @return writeOffs the present value of the written off loans
    function currentPVs(DataTypes.Storage storage _poolStorage) public view returns (uint256 totalDiscount, uint256 overdue, uint256 writeOffs) {
        // Storage storage $ = _getStorage();
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
                errPV = Math.safeAdd(errPV, Math.rmul(b, Discounting.rpow(discountRate, Math.safeSub(nnow, i), Math.ONE)));
                overdue = Math.safeAdd(overdue, b);
            }
        }

        return (
            // calculate current totalDiscount based on the previous totalDiscount (optimized calculation)
            // the overdue loans are incorrectly in this new result with their current PV and need to be removed
            Discounting.secureSub(Math.rmul(latestDiscount, Discounting.rpow(discountRate, Math.safeSub(nnow, lastNAVUpdate), Math.ONE)), errPV),
            // current overdue loans not written off
            Math.safeAdd(overdueLoans, overdue),
            // current write-offs loans
            currentWriteOffs(_poolStorage)
        );
    }

    function currentWriteOffAsset(DataTypes.Storage storage _poolStorage,bytes32 tokenId) public view returns (uint256) {
        // Storage storage $ = _getStorage();
        uint256 _currentWriteOffs = 0;
        uint256 writeOffGroupIndex = currentValidWriteOffGroup(_poolStorage,uint256(tokenId));
        _currentWriteOffs = Math.rmul(debt(_poolStorage,uint256(tokenId)), uint256(_poolStorage.writeOffGroups[writeOffGroupIndex].percentage));
        return _currentWriteOffs;
    }

    function currentAV(
        DataTypes.Storage storage _poolStorage,
        bytes32 tokenId
    ) public view returns (uint256 totalDiscount, uint256 overdue, uint256 writeOffs) {
        // Storage storage $ = _getStorage();
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

        if (isLoanWrittenOff(_poolStorage,uint256(tokenId))) {
            uint256 writeOffGroupIndex = currentValidWriteOffGroup(_poolStorage,uint256(tokenId));
            _currentWriteOffs = Math.rmul(debt(_poolStorage,uint256(tokenId)), uint256(_poolStorage.writeOffGroups[writeOffGroupIndex].percentage));
        }

        if (latestDiscountOfNavAssetsID == 0) {
            // all loans are overdue or writtenOff
            return (0, overdueLoansOfNavAssetsID, _currentWriteOffs);
        }

        uint256 errPV = 0;
        uint256 nnow = Discounting.uniqueDayTimestamp(block.timestamp);

        // loan is overdue since lastNAVUpdate
        uint256 mat = Discounting.uniqueDayTimestamp(maturityDate(_poolStorage,tokenId));
        if (mat >= lastNAVUpdate && mat < nnow) {
            uint256 b = futureValue(_poolStorage,tokenId);
            errPV = Math.rmul(b, Discounting.rpow(discountRate, Math.safeSub(nnow, mat), Math.ONE));
            overdue = b;
        }

        return (
            Discounting.secureSub(
                Math.rmul(latestDiscountOfNavAssetsID, Discounting.rpow(discountRate, Math.safeSub(nnow, lastNAVUpdate), Math.ONE)),
                errPV
            ),
            Math.safeAdd(overdueLoansOfNavAssetsID, overdue),
            _currentWriteOffs
        );
    }

    /// @notice returns the sum of all write off loans
    /// @return sum of all write off loans
    function currentWriteOffs(DataTypes.Storage storage _poolStorage) public view returns (uint256 sum) {
        // Storage storage $ = _getStorage();
        for (uint256 i = 0; i < _poolStorage.writeOffGroups.length; i++) {
            // multiply writeOffGroupDebt with the writeOff rate

            sum = Math.safeAdd(sum, Math.rmul(rateDebt(_poolStorage,WRITEOFF_RATE_GROUP_START + i), uint256(_poolStorage.writeOffGroups[i].percentage)));
        }
        return sum;
    }

    /// @notice calculates and returns the current NAV and updates the state
    /// @return nav_ current NAV
    function calcUpdateNAV(DataTypes.Storage storage _poolStorage) public returns (uint256 nav_) {
        (uint256 totalDiscount, uint256 overdue, uint256 writeOffs) = currentPVs(_poolStorage);
        // Storage storage $ = _getStorage();

        for (uint i = 0; i < _poolStorage.loanCount; ++i) {
            bytes32 _nftID = _poolStorage.loanToNFT[i];

            (uint256 td, uint256 ol, ) = currentAV(_poolStorage,_nftID);
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
    function reCalcNAV(DataTypes.Storage storage _poolStorage) public returns (uint256 nav_) {
        // reCalcTotalDiscount
        /// @notice re-calculates the totalDiscount in a non-optimized way based on lastNAVUpdate
        /// @return latestDiscount_ returns the total discount of the active loans
        // Storage storage $ = _getStorage();
        uint256 latestDiscount_ = 0;
        for (uint256 loanID = 1; loanID < _poolStorage.loanCount; loanID++) {
            bytes32 nftID_ = nftID(loanID);
            uint256 maturityDate_ = maturityDate(_poolStorage,nftID_);

            if (maturityDate_ < _poolStorage.lastNAVUpdate) {
                continue;
            }

            uint256 discountIncrease_ = Discounting.calcDiscount(
                _poolStorage.discountRate,
                futureValue(_poolStorage,nftID_),
                _poolStorage.lastNAVUpdate,
                maturityDate_
            );
            latestDiscount_ = Math.safeAdd(latestDiscount_, discountIncrease_);
            _poolStorage.latestDiscountOfNavAssets[nftID_] = discountIncrease_;
        }

        _poolStorage.latestNAV = Math.safeAdd(latestDiscount_, Math.safeSub(_poolStorage.latestNAV, _poolStorage.latestDiscount));
        _poolStorage.latestDiscount = latestDiscount_;

        return _poolStorage.latestNAV;
    }

    /// @notice updates the risk group of active loans (borrowed and unborrowed loans)
    /// @param nftID_ the nftID of the loan
    /// @param risk_ the new value appraisal of the collateral NFT
    /// @param risk_ the new risk group
    function updateAssetRiskScore(DataTypes.Storage storage _poolStorage,bytes32 nftID_, uint256 risk_) public {
        // registry().requirePoolAdmin(_msgSender());
        uint256 nnow = Discounting.uniqueDayTimestamp(block.timestamp);

        // no change in risk group
        if (risk_ == risk(_poolStorage,nftID_)) {
            return;
        }

        // Storage storage $ = _getStorage();
        _poolStorage.details[nftID_].risk = toUint128(risk_);

        // update nav -> latestNAVUpdate = now
        if (nnow > _poolStorage.lastNAVUpdate) {
            calcUpdateNAV(_poolStorage);
        }

        // switch of collateral risk group results in new: ceiling, threshold and interest rate for existing loan
        // change to new rate interestRate immediately in pile if loan debt exists
        uint256 loan = uint256(nftID_);
        if (_poolStorage.pie[loan] != 0) {
            DataTypes.RiskScore memory riskParam = getRiskScoreByIdx(_poolStorage.riskScores,risk_);
            uint256 _convertedInterestRate = Math.ONE + (riskParam.interestRate * Math.ONE) / (ONE_HUNDRED_PERCENT * 365 days);
            if (_poolStorage.rates[_convertedInterestRate].ratePerSecond == 0) {
                // If interest rate is not set
                _file(_poolStorage,'rate', _convertedInterestRate, _convertedInterestRate);
            }
            changeRate(_poolStorage,loan, _convertedInterestRate);
            _poolStorage.details[nftID_].interestRate = riskParam.interestRate;
        }

        // no currencyAmount borrowed yet
        if (futureValue(_poolStorage,nftID_) == 0) {
            return;
        }

        uint256 maturityDate_ = maturityDate(_poolStorage,nftID_);

        // Changing the risk group of an nft, might lead to a new interest rate for the dependant loan.
        // New interest rate leads to a future value.
        // recalculation required
        {
        uint256 fvDecrease = futureValue(_poolStorage,nftID_);

        uint256 navDecrease = Discounting.calcDiscount(_poolStorage.discountRate, fvDecrease, nnow, maturityDate_);

        _poolStorage.buckets[maturityDate_] = Math.safeSub(_poolStorage.buckets[maturityDate_], fvDecrease);

        _poolStorage.latestDiscount = Discounting.secureSub(_poolStorage.latestDiscount, navDecrease);
        _poolStorage.latestDiscountOfNavAssets[nftID_] = Discounting.secureSub(_poolStorage.latestDiscountOfNavAssets[nftID_], navDecrease);

        _poolStorage.latestNAV = Discounting.secureSub(_poolStorage.latestNAV, navDecrease);
        }

        // update latest NAV
        // update latest Discount
        DataTypes.Rate memory _rate = _poolStorage.rates[_poolStorage.loanRates[loan]];
        DataTypes.NFTDetails memory nftDetail = getAsset(_poolStorage,bytes32(loan));
        _poolStorage.details[nftID_].futureValue = toUint128(
            Discounting.calcFutureValue(
                _rate.ratePerSecond,
                debt(_poolStorage,loan),
                maturityDate(_poolStorage,nftID_),
                recoveryRatePD(_poolStorage.riskScores,risk_, nftDetail.expirationTimestamp - nftDetail.issuanceBlockTimestamp)
            )
        );

        uint256 fvIncrease = futureValue(_poolStorage,nftID_);
        uint256 navIncrease = Discounting.calcDiscount(_poolStorage.discountRate, fvIncrease, nnow, maturityDate_);

        _poolStorage.buckets[maturityDate_] = Math.safeAdd(_poolStorage.buckets[maturityDate_], fvIncrease);

        _poolStorage.latestDiscount = Math.safeAdd(_poolStorage.latestDiscount, navIncrease);
        _poolStorage.latestDiscountOfNavAssets[nftID_] += navIncrease;

        _poolStorage.latestNAV = Math.safeAdd(_poolStorage.latestNAV, navIncrease);
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
    function currentValidWriteOffGroup(DataTypes.Storage storage _poolStorage,uint256 loan) public view returns (uint256 writeOffGroup_) {
        bytes32 nftID_ = nftID(loan);
        uint256 maturityDate_ = maturityDate(_poolStorage,nftID_);
        uint256 nnow = Discounting.uniqueDayTimestamp(block.timestamp);

        DataTypes.NFTDetails memory nftDetail = getAsset(_poolStorage,nftID_);

        uint128 _loanRiskIndex = nftDetail.risk - 1;

        uint128 lastValidWriteOff = type(uint128).max;
        uint128 highestOverdueDays = 0;
        // Storage storage $ = _getStorage();
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

    function debt(DataTypes.Storage storage _poolStorage,uint256 loan) public view  returns (uint256 loanDebt) {
        // Storage storage $ = _getStorage();
        uint256 rate_ = _poolStorage.loanRates[loan];
        uint256 chi_ = _poolStorage.rates[rate_].chi;
        uint256 penaltyChi_ = _poolStorage.rates[rate_].penaltyChi;
        if (block.timestamp >= _poolStorage.rates[rate_].lastUpdated) {
            chi_ = chargeInterest(_poolStorage.rates[rate_].chi, _poolStorage.rates[rate_].ratePerSecond, _poolStorage.rates[rate_].lastUpdated);
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

    function rateDebt(DataTypes.Storage storage _poolStorage,uint256 rate) public view returns (uint256 totalDebt) {
        // Storage storage $ = _getStorage();
        uint256 chi_ = _poolStorage.rates[rate].chi;
        uint256 penaltyChi_ = _poolStorage.rates[rate].penaltyChi;
        uint256 pie_ = _poolStorage.rates[rate].pie;

        if (block.timestamp >= _poolStorage.rates[rate].lastUpdated) {
            chi_ = chargeInterest(_poolStorage.rates[rate].chi, _poolStorage.rates[rate].ratePerSecond, _poolStorage.rates[rate].lastUpdated);
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

    function setRate(DataTypes.Storage storage _poolStorage,uint256 loan, uint256 rate) internal {
        // Storage storage $ = _getStorage();
        require(_poolStorage.pie[loan] == 0, 'non-zero-debt');
        // rate category has to be initiated
        require(_poolStorage.rates[rate].chi != 0, 'rate-group-not-set');
        _poolStorage.loanRates[loan] = rate;
        emit SetRate(nftID(loan), rate);
    }

    function changeRate(DataTypes.Storage storage _poolStorage,uint256 loan, uint256 newRate) internal {
        // Storage storage $ = _getStorage();
        require(_poolStorage.rates[newRate].chi != 0, 'rate-group-not-set');
        if (newRate >= WRITEOFF_RATE_GROUP_START) {
            _poolStorage.rates[newRate].timeStartPenalty = uint48(block.timestamp);
        }
        uint256 currentRate = _poolStorage.loanRates[loan];
        drip(_poolStorage,currentRate);
        drip(_poolStorage,newRate);
        uint256 pie_ = _poolStorage.pie[loan];
        uint256 debt_ = toAmount(_poolStorage.rates[currentRate].chi, pie_);
        _poolStorage.rates[currentRate].pie = Math.safeSub(_poolStorage.rates[currentRate].pie, pie_);
        _poolStorage.pie[loan] = toPie(_poolStorage.rates[newRate].chi, debt_);
        _poolStorage.rates[newRate].pie = Math.safeAdd(_poolStorage.rates[newRate].pie, _poolStorage.pie[loan]);
        _poolStorage.loanRates[loan] = newRate;
        emit ChangeRate(nftID(loan), newRate);
    }

    function accrue(DataTypes.Storage storage _poolStorage,uint256 loan) internal {
        drip(_poolStorage,_poolStorage.loanRates[loan]);
    }

    function drip(DataTypes.Storage storage _poolStorage,uint256 rate) internal {
        // Storage storage $ = _getStorage();
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
    function compounding(uint chi, uint ratePerSecond, uint lastUpdated, uint _pie) public view returns (uint, uint) {
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
        return Math.rmul(Discounting.rpow(ratePerSecond, current - lastUpdated, Math.ONE), interestBearingAmount);
    }

    // convert pie to debt/savings amount
    function toAmount(uint chi, uint _pie) public pure returns (uint) {
        return Math.rmul(_pie, chi);
    }

    // convert debt/savings amount to pie
    function toPie(uint chi, uint amount) public pure returns (uint) {
        return Math.rdivup(amount, chi);
    }

    function getAsset(DataTypes.Storage storage _poolStorage,bytes32 agreementId) public view  returns (DataTypes.NFTDetails memory) {
        // Storage storage $ = _getStorage();
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
    ) public pure returns (UnpackLoanParamtersLib.InterestParams memory params) {
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
