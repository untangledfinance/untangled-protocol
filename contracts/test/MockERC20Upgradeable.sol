// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.19;

import '@openzeppelin/contracts-upgradeable/token/ERC20/presets/ERC20PresetMinterPauserUpgradeable.sol';

contract MockERC20Upgradeable is ERC20PresetMinterPauserUpgradeable {
    uint8 public currentDecimal;

    function initialize(string memory name, string memory symbol, uint8 _currentDecimal) public initializer {
        __ERC20PresetMinterPauser_init(name, symbol);
        currentDecimal = _currentDecimal;
    }

    function decimals() public view override returns (uint8) {
        return currentDecimal;
    }

    function setDecimal(uint8 _decimal) public onlyRole(DEFAULT_ADMIN_ROLE) {
        currentDecimal = _decimal;
    }
}
