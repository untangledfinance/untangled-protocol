// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Registry} from '../storage/Registry.sol';

interface IMintedNormalTGE {
    event SetHasStarted(bool hasStarted);
    event UpdateMinBidAmount(uint256 minBidAmount);
    event UpdateTotalCap(uint256 totalCap);
    event UpdateInitialAmount(uint256 initialAmount);
    event TokensPurchased(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);

    enum SaleType {
        MINTED_INCREASING_INTEREST,
        NORMAL_SALE
    }

    function initialize(Registry _registry, address _pool, address _token, address _currency) external;

    ///@notice investor bids for SOT/JOT token. Paid by pool's currency
    function buyTokens(address payee, address beneficiary, uint256 currencyAmount) external returns (uint256);

    function getInterest() external view returns (uint256);

    function pool() external view returns (address);

    function token() external view returns (address);

    function initialAmount() external view returns (uint256);

    function currencyRaisedByInvestor(address _investor) external view returns (uint256);

    function currencyRaised() external view returns (uint256);

    function firstNoteTokenMintedTimestamp() external view returns (uint256);

    function setHasStarted(bool _hasStarted) external;

    function setMinBidAmount(uint256 _minBidAmount) external;

    function onRedeem(uint256 _currencyAmount) external;

    function setInterestRate(uint256 _interestRate) external;

    function setInitialAmount(uint256 _initialAmount) external;

    function setTotalCap(uint256 _cap) external;
}
