// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol';
import {ISecuritizationPoolValueService} from '../../interfaces/ISecuritizationPoolValueService.sol';
import {IMintedNormalTGE} from '../../interfaces/IMintedNormalTGE.sol';
import {Configuration} from '../Configuration.sol';
import {DataTypes} from '../DataTypes.sol';
import {TransferHelper} from '../TransferHelper.sol';

library TGELogic {
    uint256 constant RATE_SCALING_FACTOR = 10 ** 4;

    event UpdateTGEAddress(address tge, Configuration.NOTE_TOKEN_TYPE noteType);
    event IncreaseReserve(uint256 increasingAmount, uint256 currencyAmount);
    event DecreaseReserve(uint256 decreasingAmount, uint256 currencyAmount);
    event UpdateDebtCeiling(uint256 _debtCeiling);
    event UpdateMintFirstLoss(uint32 _mintFirstLoss);
    event UpdateInterestRateSot(uint256 _interestRateSot);
    event Withdraw(address originatorAddress, uint256 amount);
    event ClaimCashRemain(address pot, address recipientWallet, uint256 balance);

    // alias
    function sotToken(DataTypes.Storage storage _poolStorage) public view returns (address) {
        address tge = _poolStorage.tgeAddress;
        if (tge == address(0)) return address(0);
        return IMintedNormalTGE(tge).token();
    }

    // alias
    function jotToken(DataTypes.Storage storage _poolStorage) public view returns (address) {
        address tge = _poolStorage.secondTGEAddress;
        if (tge == address(0)) return address(0);
        return IMintedNormalTGE(tge).token();
    }

    function underlyingCurrency(DataTypes.Storage storage _poolStorage) public view returns (address) {
        return _poolStorage.underlyingCurrency;
    }

    function reserve(DataTypes.Storage storage _poolStorage) public view returns (uint256) {
        return _poolStorage.reserve;
    }

    function minFirstLossCushion(DataTypes.Storage storage _poolStorage) public view returns (uint32) {
        return _poolStorage.minFirstLossCushion;
    }

    function paidPrincipalAmountSOT(DataTypes.Storage storage _poolStorage) public view returns (uint256) {
        return _poolStorage.paidPrincipalAmountSOT;
    }

    function debtCeiling(DataTypes.Storage storage _poolStorage) public view returns (uint256) {
        return _poolStorage.debtCeiling;
    }

    function interestRateSOT(DataTypes.Storage storage _poolStorage) public view returns (uint256) {
        return _poolStorage.interestRateSOT;
    }

    function paidPrincipalAmountSOTByInvestor(
        DataTypes.Storage storage _poolStorage,
        address user
    ) public view returns (uint256) {
        return _poolStorage.paidPrincipalAmountSOTByInvestor[user];
    }

    function totalAssetRepaidCurrency(DataTypes.Storage storage _poolStorage) public view returns (uint256) {
        return _poolStorage.totalAssetRepaidCurrency;
    }

    function injectTGEAddress(
        DataTypes.Storage storage _poolStorage,
        address _tgeAddress,
        Configuration.NOTE_TOKEN_TYPE _noteType
    ) external {
        require(_tgeAddress != address(0), 'SecuritizationPool: Address zero');
        address _tokenAddress = IMintedNormalTGE(_tgeAddress).token();
        require(_tokenAddress != address(0), 'SecuritizationPool: Address zero');

        if (_noteType == Configuration.NOTE_TOKEN_TYPE.SENIOR) {
            _poolStorage.tgeAddress = _tgeAddress;
            _poolStorage.sotToken = _tokenAddress;
        } else {
            _poolStorage.secondTGEAddress = _tgeAddress;
            _poolStorage.jotToken = _tokenAddress;
        }

        _poolStorage.state = DataTypes.CycleState.CROWDSALE;

        emit UpdateTGEAddress(_tgeAddress, _noteType);
    }

    function disburse(DataTypes.Storage storage _poolStorage, address usr, uint256 currencyAmount) external {
        TransferHelper.safeTransferFrom(_poolStorage.underlyingCurrency, _poolStorage.pot, usr, currencyAmount);
    }

    function checkMinFirstLost(
        DataTypes.Storage storage _poolStorage,
        address poolServiceAddress
    ) public view returns (bool) {
        ISecuritizationPoolValueService poolService = ISecuritizationPoolValueService(poolServiceAddress);
        return _poolStorage.minFirstLossCushion <= poolService.getJuniorRatio(address(this));
    }

    function isDebtCeilingValid(DataTypes.Storage storage _poolStorage) public view returns (bool) {
        uint256 totalDebt = 0;
        if (_poolStorage.tgeAddress != address(0)) {
            totalDebt += IMintedNormalTGE(_poolStorage.tgeAddress).currencyRaised();
        }
        if (_poolStorage.secondTGEAddress != address(0)) {
            totalDebt += IMintedNormalTGE(_poolStorage.secondTGEAddress).currencyRaised();
        }
        return _poolStorage.debtCeiling >= totalDebt;
    }

    // Increase by value
    function increaseTotalAssetRepaidCurrency(DataTypes.Storage storage _poolStorage, uint256 amount) external {
        _poolStorage.reserve = _poolStorage.reserve + amount;
        _poolStorage.totalAssetRepaidCurrency = _poolStorage.totalAssetRepaidCurrency + amount;

        emit IncreaseReserve(amount, _poolStorage.reserve);
    }

    function hasFinishedRedemption(DataTypes.Storage storage _poolStorage) public view returns (bool) {
        address stoken = sotToken(_poolStorage);
        if (stoken != address(0)) {
            require(IERC20Upgradeable(stoken).totalSupply() == 0, 'SecuritizationPool: SOT still remain');
        }

        address jtoken = jotToken(_poolStorage);
        if (jtoken != address(0)) {
            require(IERC20Upgradeable(jtoken).totalSupply() == 0, 'SecuritizationPool: JOT still remain');
        }

        return true;
    }

    function setPot(DataTypes.Storage storage _poolStorage, address _pot) external {
        require(_poolStorage.pot != _pot, 'SecuritizationPool: Same address with current pot');
        _poolStorage.pot = _pot;

        if (_pot == address(this)) {
            require(
                IERC20Upgradeable(_poolStorage.underlyingCurrency).approve(_pot, type(uint256).max),
                'SecuritizationPool: Pot not approved'
            );
        }
    }

    function setMinFirstLossCushion(DataTypes.Storage storage _poolStorage, uint32 _minFirstLossCushion) external {
        _setMinFirstLossCushion(_poolStorage, _minFirstLossCushion);
    }

    function _setMinFirstLossCushion(DataTypes.Storage storage _poolStorage, uint32 _minFirstLossCushion) internal {
        require(
            _minFirstLossCushion <= 100 * RATE_SCALING_FACTOR,
            'SecuritizationPool: minFirstLossCushion is greater than 100'
        );

        _poolStorage.minFirstLossCushion = _minFirstLossCushion;
        emit UpdateMintFirstLoss(_minFirstLossCushion);
    }

    function setDebtCeiling(DataTypes.Storage storage _poolStorage, uint256 _debtCeiling) external {
        _setDebtCeiling(_poolStorage, _debtCeiling);
    }

    function _setDebtCeiling(DataTypes.Storage storage _poolStorage, uint256 _debtCeiling) internal {
        _poolStorage.debtCeiling = _debtCeiling;
        emit UpdateDebtCeiling(_debtCeiling);
    }

    function _setInterestRateSOT(DataTypes.Storage storage _poolStorage, uint256 _newRate) external {
        _poolStorage.interestRateSOT = _newRate;
        emit UpdateInterestRateSot(_newRate);
    }

    function increaseReserve(
        DataTypes.Storage storage _poolStorage,
        address poolServiceAddress,
        uint256 currencyAmount
    ) external {
        _poolStorage.reserve = _poolStorage.reserve + currencyAmount;
        // require(checkMinFirstLost(_poolStorage, poolServiceAddress), 'MinFirstLoss is not satisfied');

        emit IncreaseReserve(currencyAmount, _poolStorage.reserve);
    }

    function decreaseReserve(
        DataTypes.Storage storage _poolStorage,
        address poolServiceAddress,
        uint256 currencyAmount
    ) external {
        _decreaseReserve(_poolStorage, poolServiceAddress, currencyAmount);
    }

    function _decreaseReserve(
        DataTypes.Storage storage _poolStorage,
        address poolServiceAddress,
        uint256 currencyAmount
    ) private {
        _poolStorage.reserve = _poolStorage.reserve - currencyAmount;
        // require(checkMinFirstLost(_poolStorage, poolServiceAddress), 'MinFirstLoss is not satisfied');

        emit DecreaseReserve(currencyAmount, _poolStorage.reserve);
    }

    // After closed pool and redeem all not -> get remain cash to recipient wallet
    function claimCashRemain(DataTypes.Storage storage _poolStorage, address recipientWallet) external {
        IERC20Upgradeable currency = IERC20Upgradeable(_poolStorage.underlyingCurrency);
        uint256 balance = currency.balanceOf(_poolStorage.pot);
        require(
            currency.transferFrom(_poolStorage.pot, recipientWallet, balance),
            'SecuritizationPool: Transfer failed'
        );

        emit ClaimCashRemain(_poolStorage.pot, recipientWallet, balance);
    }

    function withdraw(
        DataTypes.Storage storage _poolStorage,
        address poolServiceAddress,
        address to,
        uint256 amount
    ) public {
        require(_poolStorage.reserve >= amount, 'SecuritizationPool: not enough reserve');

        _decreaseReserve(_poolStorage, poolServiceAddress, amount);

        TransferHelper.safeTransferFrom(_poolStorage.underlyingCurrency, _poolStorage.pot, to, amount);
        emit Withdraw(to, amount);
    }
}
