// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Registry} from '../../storage/Registry.sol';
import {IInterestRate} from './IInterestRate.sol';

interface IMintedTGE is IInterestRate {
    event UpdateInitialAmount(uint256 initialAmount);

    enum SaleType {
        MINTED_INCREASING_INTEREST,
        NORMAL_SALE
    }

    function initialize(
        Registry _registry,
        address _pool,
        address _token,
        address _currency,
        bool _isLongSale
    ) external;

    ///@notice investor bids for SOT/JOT token. Paid by pool's currency
    function buyTokens(address payee, address beneficiary, uint256 currencyAmount) external returns (uint256);

    function startNewRoundSale(uint256 openingTime_, uint256 closingTime_, uint256 rate_, uint256 cap_) external;

    function setTotalCap(uint256 cap_) external;

    function getInterest() external view returns (uint256);
}
