// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Registry} from '../../../../storage/Registry.sol';
import {TimedCrowdsale} from '../TimedCrowdsale.sol';

contract TimedCrowdsaleMock is TimedCrowdsale {
    function initialize(Registry _registry, address _pool, address _token, address _currency) public initializer {
        __TimedCrowdsale__init(_registry, _pool, _token, _currency);
    }

    function checkOnlyWhileOpen() public onlyWhileOpen {}

    function getTokenAmount(uint256 currencyAmount) public view virtual override returns (uint256) {
        return 0; // ignore
    }

    function isLongSale() public view virtual override returns (bool) {
        return false; // ignore
    }
}
