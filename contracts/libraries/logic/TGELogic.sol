// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol';
import {ISecuritizationPoolValueService} from '../../interfaces/ISecuritizationPoolValueService.sol';
import {IMintedNormalTGE} from '../../interfaces/IMintedNormalTGE.sol';
import {Configuration} from '../Configuration.sol';
import {DataTypes, RATE_SCALING_FACTOR} from '../DataTypes.sol';
import {TransferHelper} from '../TransferHelper.sol';

library TGELogic {
    event UpdateTGEAddress(address tge, Configuration.NOTE_TOKEN_TYPE noteType);
    event IncreaseReserve(uint256 increasingAmount, uint256 currencyAmount);
    event IncreaseCapitalReserve(uint256 increasingAmount, uint256 currencyAmount);
    event DecreaseReserve(uint256 decreasingAmount, uint256 currencyAmount);
    event DecreaseCapitalReserve(uint256 decreasingAmount, uint256 currencyAmount);
    event DecreaseIncomeReserve(uint256 decreasingAmount, uint256 currencyAmount);
    event UpdateDebtCeiling(uint256 _debtCeiling);
    event UpdateMintFirstLoss(uint32 _mintFirstLoss);
    event UpdateInterestRateSot(uint32 _interestRateSot);
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

    function minFirstLossCushion(DataTypes.Storage storage _poolStorage) public view returns (uint32) {
        return _poolStorage.minFirstLossCushion;
    }

    function debtCeiling(DataTypes.Storage storage _poolStorage) public view returns (uint256) {
        return _poolStorage.debtCeiling;
    }

    function interestRateSOT(DataTypes.Storage storage _poolStorage) public view returns (uint256) {
        return _poolStorage.interestRateSOT;
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
            require(_poolStorage.tgeAddress == address(0), 'SecuritizationPool: Already issue sot');
            _poolStorage.tgeAddress = _tgeAddress;
            _poolStorage.sotToken = _tokenAddress;
        } else {
            require(_poolStorage.secondTGEAddress == address(0), 'SecuritizationPool: Already issue jot');
            _poolStorage.secondTGEAddress = _tgeAddress;
            _poolStorage.jotToken = _tokenAddress;
        }

        emit UpdateTGEAddress(_tgeAddress, _noteType);
    }

    function disburse(DataTypes.Storage storage _poolStorage, address usr, uint256 currencyAmount) external {
        TransferHelper.safeTransferFrom(_poolStorage.underlyingCurrency, _poolStorage.pot, usr, currencyAmount);
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
        _poolStorage.totalAssetRepaidCurrency = _poolStorage.totalAssetRepaidCurrency + amount;
    }

    function hasFinishedRedemption(DataTypes.Storage storage _poolStorage) public view returns (bool) {
        address sToken = sotToken(_poolStorage);
        if (sToken != address(0)) {
            require(IERC20Upgradeable(sToken).totalSupply() == 0, 'SecuritizationPool: SOT still remain');
        }

        address jToken = jotToken(_poolStorage);
        if (jToken != address(0)) {
            require(IERC20Upgradeable(jToken).totalSupply() == 0, 'SecuritizationPool: JOT still remain');
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

    function _setInterestRateSOT(DataTypes.Storage storage _poolStorage, uint32 _newRate) external {
        _poolStorage.interestRateSOT = _newRate;
        emit UpdateInterestRateSot(_newRate);
    }

    function increaseCapitalReserve(DataTypes.Storage storage _poolStorage, uint256 currencyAmount) external {
        _poolStorage.capitalReserve = _poolStorage.capitalReserve + currencyAmount;
        emit IncreaseCapitalReserve(currencyAmount, _poolStorage.capitalReserve);
    }

    function decreaseCapitalReserve(DataTypes.Storage storage _poolStorage, uint256 currencyAmount) external {
        require(_poolStorage.capitalReserve >= currencyAmount, 'insufficient balance of capital reserve');
        _poolStorage.capitalReserve = _poolStorage.capitalReserve - currencyAmount;
        emit DecreaseCapitalReserve(currencyAmount, _poolStorage.capitalReserve);
    }

    function decreaseIncomeReserve(DataTypes.Storage storage _poolStorage, uint256 currencyAmount) external {
        require(_poolStorage.incomeReserve >= currencyAmount, 'insufficient balance of income reserve');
        _poolStorage.incomeReserve = _poolStorage.incomeReserve - currencyAmount;
        emit DecreaseIncomeReserve(currencyAmount, _poolStorage.incomeReserve);
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

    function withdraw(DataTypes.Storage storage _poolStorage, address to, uint256 amount) public {
        require(_poolStorage.capitalReserve >= amount, 'SecuritizationPool: insufficient balance of capital reserve');
        _poolStorage.capitalReserve = _poolStorage.capitalReserve - amount;

        TransferHelper.safeTransferFrom(_poolStorage.underlyingCurrency, _poolStorage.pot, to, amount);
        emit DecreaseCapitalReserve(amount, _poolStorage.capitalReserve);
    }
}
