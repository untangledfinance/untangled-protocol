// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ICrowdSale {
    event SetHasStarted(bool hasStarted);

    function pool() external view returns (address);

    function token() external view returns (address);

    function currencyRaisedByInvestor(address investor) external view returns (uint256);

    function currencyRaised() external view returns (uint256);

    function firstNoteTokenMintedTimestamp() external view returns (uint64);

    function buyTokens(address payee, address beneficiary, uint256 currencyAmount) external returns (uint256);

    function onRedeem(uint256 currencyAmount) external;

    function setHasStarted(bool _hasStarted) external;

    function setMinBidAmount(uint256 _minBidAmount) external;
}
