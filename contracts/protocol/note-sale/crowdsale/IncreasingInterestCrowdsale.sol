// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import './FinalizableCrowdsale.sol';
import '../IInterestRate.sol';

/// @title IncreasingInterestCrowdsale
/// @author Untangled Team
abstract contract IncreasingInterestCrowdsale is IInterestRate, FinalizableCrowdsale {
    using ConfigHelper for Registry;

    event UpdateInterestRange(
        uint32 initialInterest,
        uint32 finalInterest,
        uint32 timeInterval,
        uint32 amountChangeEachInterval
    );

    uint32 public initialInterest;
    uint32 public finalInterest;
    uint32 public timeInterval;
    uint32 public amountChangeEachInterval;
    uint32 public override pickedInterest;

    function setInterestRange(
        uint32 _initialInterest,
        uint32 _finalInterest,
        uint32 _timeInterval,
        uint32 _amountChangeEachInterval
    ) public whenNotPaused {
        require(
            hasRole(OWNER_ROLE, _msgSender()) || _msgSender() == address(registry.getSecuritizationManager()),
            'IncreasingInterestCrowdsale: Caller must be owner or pool'
        );
        require(!hasStarted, 'IncreasingInterestCrowdsale: sale already started');
        require(
            _initialInterest <= _finalInterest,
            'IncreasingInterestCrowdsale: initial interest is not less than final interest'
        );
        require(_timeInterval > 0, 'IncreasingInterestCrowdsale: time interval is 0');

        initialInterest = _initialInterest;
        finalInterest = _finalInterest;
        timeInterval = _timeInterval;
        amountChangeEachInterval = _amountChangeEachInterval;

        emit UpdateInterestRange(initialInterest, finalInterest, timeInterval, amountChangeEachInterval);
    }

    function getCurrentInterest() public view returns (uint32) {
        if (block.timestamp < openingTime) {
            return 0;
        }

        // solhint-disable-next-line not-rely-on-time
        uint256 elapsedTime = block.timestamp - openingTime;
        // uint256 numberInterval = elapsedTime / timeInterval;
        // uint32 currentInterest = uint32(amountChangeEachInterval * numberInterval + initialInterest);
        uint32 currentInterest = uint32((amountChangeEachInterval * elapsedTime) / timeInterval + initialInterest);

        if (currentInterest > finalInterest) {
            return finalInterest;
        } else {
            return currentInterest;
        }
    }

    /// @dev Override _finalization function. In Auction note sale, interest of token determined when the auction ends
    function _finalization() internal override {
        super._finalization();

        pickedInterest = getCurrentInterest();
    }

    function _preValidatePurchase(
        address beneficiary,
        uint256 currencyAmount,
        uint256 tokenAmount
    ) internal view override {
        super._preValidatePurchase(beneficiary, currencyAmount, tokenAmount);
        require(timeInterval > 0, 'IncreasingInterestCrowdsale: time interval not set');
    }

    uint256[45] private __gap;
}
