// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import './IFinalizableCrowdsale.sol';
import './TimedCrowdsale.sol';

/// @title FinalizableCrowdsale
/// @author Untangled Team
/// @dev An abstract contract define finalize function for sale
abstract contract FinalizableCrowdsale is IFinalizableCrowdsale, TimedCrowdsale {
    bool internal _finalized;

    function finalized() public view virtual override returns (bool) {
        return _finalized;
    }

    /// @dev Validates that the crowdsale has not already been finalized and that it has either closed or reached the total cap
    /// @param claimRemainToken claim remaining token or not
    /// @param remainTokenRecipient Wallet will receive remaining token
    function finalize(bool claimRemainToken, address remainTokenRecipient) public whenNotPaused {
        require(_msgSender() == pool || _msgSender() == address(this), 'FinalizableCrowdsale: Only pool contract can finalize');
        require(!finalized(), 'FinalizableCrowdsale: already finalized');
        require(hasClosed() || totalCapReached(), 'FinalizableCrowdsale: not closed');
        _finalized = true;

        if (!isDistributedFully() && !isLongSale()) {
            uint256 tokenRemain = 0;
            tokenRemain = getTokenAmount(getCurrencyRemainAmount());

            if (claimRemainToken) {
                _processPurchase(remainTokenRecipient, tokenRemain);
            } else {
                _ejectTokens(tokenRemain);
            }
        }

        _finalization();
        emit CrowdsaleFinalized();
    }

    /// @dev This function is meant to be overridden in derived contracts to implement specific finalization logic
    function _finalization() internal virtual {
        // solhint-disable-previous-line no-empty-blocks
    }

    uint256[49] private __gap;
}
