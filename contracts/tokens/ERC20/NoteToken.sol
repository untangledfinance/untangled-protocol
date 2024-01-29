// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import '@openzeppelin/contracts-upgradeable/token/ERC20/presets/ERC20PresetMinterPauserUpgradeable.sol';
import './INoteToken.sol';

/// @title NoteToken
/// @author Untangled Team
/// @dev Template for SOT/JOT token
contract NoteToken is INoteToken, ERC20PresetMinterPauserUpgradeable {
    address internal _poolAddress;
    uint8 internal _noteTokenType;
    uint8 internal _decimals;

    function initialize(
        string memory name,
        string memory symbol,
        uint8 decimalsOfToken,
        address poolAddressOfToken,
        uint8 typeOfToken
    ) public initializer {
        __ERC20PresetMinterPauser_init(name, symbol);
        require(poolAddressOfToken != address(0), 'NoteToken: Invalid pool address');

        _decimals = decimalsOfToken;
        _poolAddress = poolAddressOfToken;
        _noteTokenType = typeOfToken;
    }

    function poolAddress() external view returns (address) {
        return _poolAddress;
    }

    function noteTokenType() external view returns (uint8) {
        return _noteTokenType;
    }

    function decimals() public view override(ERC20Upgradeable, IERC20MetadataUpgradeable) returns (uint8) {
        return _decimals;
    }

    function burn(uint256 amount) public override(ERC20BurnableUpgradeable, INoteToken) {
        return ERC20BurnableUpgradeable.burn(amount);
    }

    function mint(address receiver, uint256 amount) public override(INoteToken, ERC20PresetMinterPauserUpgradeable) {
        return ERC20PresetMinterPauserUpgradeable.mint(receiver, amount);
    }

    function pause() public virtual override(ERC20PresetMinterPauserUpgradeable, IPauseable) {
        super.pause();
    }

    function paused() public view virtual override(IPauseable, PausableUpgradeable) returns (bool) {
        return super.paused();
    }

    function unpause() public virtual override(ERC20PresetMinterPauserUpgradeable, IPauseable) {
        super.unpause();
    }
}
