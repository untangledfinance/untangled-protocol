// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Registry} from '../../storage/Registry.sol';
import {IInterestRate} from './IInterestRate.sol';

interface IMintedTGE is IInterestRate {
    event YieldUpdated(uint256 newYield);
    event SetupLongSale(uint256 interestRate, uint256 termLengthInSeconds, uint256 timeStartEarningInterest);
    event UpdateInitialAmount(uint256 initialAmount);

    function initialize(
        Registry _registry,
        address _pool,
        address _token,
        address _currency,
        bool _isLongSale
    ) external;

    /// @notice initialize long sale settings
    function setupLongSale(
        uint256 interestRate,
        uint256 termLengthInSeconds,
        uint256 timeStartEarningInterest
    ) external;

    ///@notice investor bids for SOT/JOT token. Paid by pool's currency
    function buyTokens(address payee, address beneficiary, uint256 currencyAmount) external returns (uint256);

    function startNewRoundSale(uint256 openingTime_, uint256 closingTime_, uint256 rate_, uint256 cap_) external;

    function setTotalCap(uint256 cap_) external;
}
