// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '../../base/UntangledBase.sol';
import './crowdsale/IncreasingInterestCrowdsale.sol';
import './IMintedTGE.sol';
import './base/LongSaleInterest.sol';
import './IInterestRate.sol';
import '../../interfaces/INoteToken.sol';

/// @title MintedIncreasingInterestTGE
/// @author Untangled Team
/// @dev Note sale for SOT - auction
contract MintedIncreasingInterestTGE is IMintedTGE, UntangledBase, IncreasingInterestCrowdsale, LongSaleInterest {
    using ConfigHelper for Registry;

    bool public longSale;
    uint256 public timeStartEarningInterest;
    uint256 public termLengthInSeconds;
    uint256 public interestRate;
    uint256 public yield;

    function initialize(
        Registry _registry,
        address _pool,
        address _token,
        address _currency,
        bool _longSale
    ) public initializer {
        __Crowdsale__init(_registry, _pool, _token, _currency);

        longSale = _longSale;
    }

    /// @inheritdoc Crowdsale
    function isLongSale() public view override returns (bool) {
        return longSale;
    }

    /// @dev Sets the yield variable to the specified value
    function setYield(uint256 _yield) public whenNotPaused onlyRole(OWNER_ROLE) {
        yield = _yield;
        emit YieldUpdated(_yield);
    }

    function setupLongSale(
        uint256 _interestRate,
        uint256 _termLengthInSeconds,
        uint256 _timeStartEarningInterest
    ) public whenNotPaused securitizationPoolRestricted {
        if (isLongSale()) {
            interestRate = _interestRate;
            timeStartEarningInterest = _timeStartEarningInterest;
            termLengthInSeconds = _termLengthInSeconds;
            yield = _interestRate;

            emit SetupLongSale(interestRate, termLengthInSeconds, timeStartEarningInterest);
            emit YieldUpdated(yield);
        }
    }

    /// @notice Calculate token price
    /// @dev This sale is for SOT. So the function return SOT token price
    function getTokenPrice() public view returns (uint256) {
        return registry.getDistributionAssessor().getSOTTokenPrice(pool);
    }

    /// @notice Get amount of token can receive from an amount of currency
    function getTokenAmount(uint256 currencyAmount) public view override returns (uint256) {
        return (currencyAmount * 10 ** INoteToken(token).decimals()) / getTokenPrice();
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
            'MintedIncreasingInterestTGE: Caller must be owner or manager'
        );
        _preValidateNewSaleRound();

        // call inner function for each extension
        _newSaleRound(rate_);
        newSaleRoundTime(openingTime_, closingTime_);
        _setTotalCap(cap_);
    }

    function setTotalCap(uint256 cap_) external whenNotPaused {
        require(
            hasRole(OWNER_ROLE, _msgSender()) || _msgSender() == address(registry.getSecuritizationManager()),
            'MintedIncreasingInterestTGE: Caller must be owner or manager'
        );
        _setTotalCap(cap_);
    }

    /// @dev Validates that the previous sale round is closed and the time interval for increasing interest is greater than zero
    function _preValidateNewSaleRound() internal view {
        require(hasClosed() || totalCapReached(), 'MintedIncreasingInterestTGE: Previous round not closed');
        require(timeInterval > 0, 'MintedIncreasingInterestTGE: Time interval increasing interest is 0');
    }

    function buyTokens(
        address payee,
        address beneficiary,
        uint256 currencyAmount
    ) public override(IMintedTGE, Crowdsale) returns (uint256 tokenAmount) {
        tokenAmount = Crowdsale.buyTokens(payee, beneficiary, currencyAmount);
        if (_currencyRaised >= totalCap) {
            if (!this.finalized()) {
                this.finalize(false, pool);
            }
        }
    }

    uint256[45] private __gap;
}
