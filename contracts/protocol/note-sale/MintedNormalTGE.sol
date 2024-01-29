// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Registry} from '../../storage/Registry.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {Crowdsale} from './crowdsale/Crowdsale.sol';
import {FinalizableCrowdsale} from './crowdsale/FinalizableCrowdsale.sol';
import {ISecuritizationPool} from '../pool/ISecuritizationPool.sol';
import {IMintedTGE} from './IMintedTGE.sol';
import {LongSaleInterest} from './base/LongSaleInterest.sol';
import '../../interfaces/INoteToken.sol';

/// @title MintedNormalTGE
/// @author Untangled Team
/// @dev Note sale for JOT
contract MintedNormalTGE is IMintedTGE, FinalizableCrowdsale, LongSaleInterest {
    using ConfigHelper for Registry;

    bool public longSale;
    uint256 public interestRate;
    uint256 public initialAmount;

    uint32 public pickedInterest;
    uint8 saleType;

    function initialize(
        Registry _registry,
        address _pool,
        address _token,
        address _currency,
        bool _longSale
    ) public initializer {
        __Crowdsale__init(_registry, _pool, _token, _currency);

        longSale = _longSale;
        saleType = uint8(SaleType.NORMAL_SALE);
    }

    /// @inheritdoc Crowdsale
    function isLongSale() public view override returns (bool) {
        return longSale;
    }

    function getTokenPrice() public view returns (uint256) {
        return registry.getDistributionAssessor().calcTokenPrice(pool, token);
    }

    function getTokenAmount(uint256 currencyAmount) public view override returns (uint256) {
        uint256 tokenPrice = getTokenPrice();

        if (tokenPrice == 0) {
            return 0;
        }
        return (currencyAmount * 10 ** INoteToken(token).decimals()) / tokenPrice;
    }

    function getInterest() public view override returns (uint256) {
        return interestRate;
    }

    /// @notice Setup a new round sale for note token
    /// @param openingTime_ Define when the sale should start
    /// @param closingTime_ Define when the sale should end
    /// @param cap_ Target amount of raised currency
    function startNewRoundSale(
        uint256 openingTime_,
        uint256 closingTime_,
        uint256 rate_,
        uint256 cap_
    ) external override whenNotPaused {
        require(
            hasRole(OWNER_ROLE, _msgSender()) || _msgSender() == address(registry.getSecuritizationManager()),
            'MintedNormalTGE: Caller must be owner or manager'
        );
        _preValidateNewSaleRound();

        // call inner function for each extension
        _newSaleRound(rate_);
        newSaleRoundTime(openingTime_, closingTime_);
        _setTotalCap(cap_);
    }

    function setInterestRate(uint256 _interestRate) external whenNotPaused {
        require(
            hasRole(OWNER_ROLE, _msgSender()) || _msgSender() == address(registry.getSecuritizationManager()),
            'MintedNormalTGE: Caller must be owner or manager'
        );
        interestRate = _interestRate;
    }

    function setTotalCap(uint256 cap_) external whenNotPaused {
        require(
            hasRole(OWNER_ROLE, _msgSender()) || _msgSender() == address(registry.getSecuritizationManager()),
            'MintedNormalTGE: Caller must be owner or manager'
        );
        _setTotalCap(cap_);
    }

    /// @notice Setup initial amount currency raised for JOT condition
    /// @param _initialAmount Expected minimum amount of JOT before SOT start
    function setInitialAmount(uint256 _initialAmount) external whenNotPaused {
        require(
            hasRole(OWNER_ROLE, _msgSender()) || _msgSender() == address(registry.getSecuritizationManager()),
            'MintedNormalTGE: Caller must be owner or manager'
        );
        require(initialAmount < totalCap, 'MintedNormalTGE: Initial JOT amount must be less than total cap');
        initialAmount = _initialAmount;
        emit UpdateInitialAmount(_initialAmount);
    }

    /// @dev Validates that the previous sale round is closed and the time interval for increasing interest is greater than zero
    function _preValidateNewSaleRound() internal view {
        require(hasClosed() || totalCapReached(), 'MintedIncreasingInterestTGE: Previous round not closed');
    }

    function _finalization() internal override {
        super._finalization();

        pickedInterest = uint32(interestRate);
    }

    function buyTokens(
        address payee,
        address beneficiary,
        uint256 currencyAmount
    ) public override(IMintedTGE, Crowdsale) returns (uint256) {
        return Crowdsale.buyTokens(payee, beneficiary, currencyAmount);
    }

    uint256[45] private __gap;
}
