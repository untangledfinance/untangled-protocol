// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.19;

import '../uid/UniqueIdentity.sol';

/// @title TestUniqueIdentity
/// @author Untangled Team
/// @dev Used for test purpose only
contract TestUniqueIdentity is UniqueIdentity {
    function _mintForTest(address to, uint256 id, uint256 amount, bytes memory data) public incrementNonce(to) {
        _mint(to, id, amount, data);
    }

    function _burnForTest(address account, uint256 id) public incrementNonce(account) {
        _burn(account, id, 1);
    }
}
