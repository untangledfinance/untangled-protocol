// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol';
import {IERC20MetadataUpgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol';
import {IPauseable} from '../../base/IPauseable.sol';

interface INoteToken is IERC20Upgradeable, IERC20MetadataUpgradeable, IPauseable {
    // address public poolAddress;
    // uint8 public noteTokenType;

    // uint8 internal immutable _d;
    function poolAddress() external view returns (address);

    function noteTokenType() external view returns (uint8);

    function mint(address receiver, uint256 amount) external;

    function burn(uint256 amount) external;
}
