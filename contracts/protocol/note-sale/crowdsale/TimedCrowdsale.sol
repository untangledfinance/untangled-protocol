// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import './Crowdsale.sol';

/// @title TimedCrowdsale
/// @author Untangled Team
/// @dev Note sale that has open time and close time
abstract contract TimedCrowdsale is Crowdsale {
    using ConfigHelper for Registry;
    uint256 public openingTime;
    uint256 public closingTime;

    bool public isEnableTimeLimit;

    event TimedCrowdsaleExtended(uint256 prevClosingTime, uint256 newClosingTime);
    event UpdateUsingTimeLimit(bool isEnableTimeLimit);
    event UpdateSaleRoundTime(uint256 newOpeningTime, uint256 newClosingTime);

    function __TimedCrowdsale__init(
        Registry _registry,
        address _pool,
        address _token,
        address _currency
    ) internal onlyInitializing {
        __Crowdsale__init(_registry, _pool, _token, _currency);

        isEnableTimeLimit = true;
    }

    modifier onlyWhileOpen() {
        require(isOpen() || isLongSale(), 'TimedCrowdsale: not open');
        _;
    }

    function isOpen() public view returns (bool) {
        if (!isEnableTimeLimit) {
            return true;
        }
        // solhint-disable-next-line not-rely-on-time
        return block.timestamp >= openingTime && block.timestamp <= closingTime;
    }

    function hasClosed() public view returns (bool) {
        // solhint-disable-next-line not-rely-on-time
        return block.timestamp > closingTime;
    }

    /// @notice Updates the closing time with the new closing time
    function extendTime(uint256 newClosingTime) external whenNotPaused nonReentrant onlyRole(OWNER_ROLE) {
        require(newClosingTime > closingTime, 'TimedCrowdsale: new closing time is before current closing time');

        emit TimedCrowdsaleExtended(closingTime, newClosingTime);
        closingTime = newClosingTime;
    }

    /// @notice Updates the opening time and closing time accordingly
    function newSaleRoundTime(uint256 newOpeningTime, uint256 newClosingTime) public whenNotPaused {
        require(
            hasRole(OWNER_ROLE, _msgSender()) || _msgSender() == address(registry.getSecuritizationManager()),
            'Crowdsale: Caller must be owner or pool'
        );
        require(newClosingTime >= newOpeningTime, 'TimedCrowdsale: opening time is not before closing time');
        // not accept opening time in the past
        if (newOpeningTime < block.timestamp) {
            newOpeningTime = block.timestamp;
        }

        if (newClosingTime <= newOpeningTime) {
            newClosingTime = newOpeningTime + 1;
        }

        openingTime = newOpeningTime;
        closingTime = newClosingTime;

        emit UpdateSaleRoundTime(newOpeningTime, newClosingTime);
    }

    /// @dev Sets the isEnableTimeLimit variable to the specified value
    function setUsingTimeLimit(bool usingTimeLimit) public whenNotPaused nonReentrant onlyRole(OWNER_ROLE) {
        isEnableTimeLimit = usingTimeLimit;
        emit UpdateUsingTimeLimit(usingTimeLimit);
    }

    uint256[47] private __gap;
}
