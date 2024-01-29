// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

/// @title TestERC20
/// @author Untangled Team
/// @dev Used for test purpose only
contract TestERC20 is ERC20 {
    address admin;

    constructor(string memory name, string memory symbol, uint256 initialSupply) ERC20(name, symbol) {
        admin = msg.sender;
        _mint(msg.sender, initialSupply);
    }

    function mint(uint256 amount) public {
        _mint(admin, amount);
    }
}
