// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Registry} from '../../../../storage/Registry.sol';
import {FinalizableCrowdsale} from '../FinalizableCrowdsale.sol';

contract FinalizableCrowdsaleMock is FinalizableCrowdsale {
    function isLongSale() public view virtual override returns (bool) {}

    function getTokenAmount(uint256 currencyAmount) public view virtual override returns (uint256) {}

    function initialize(Registry _registry, address _pool, address _token, address _currency) public initializer {
        __TimedCrowdsale__init(_registry, _pool, _token, _currency);
    }
}
