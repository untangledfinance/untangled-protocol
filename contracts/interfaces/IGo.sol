// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.19;

import {IUniqueIdentity} from './IUniqueIdentity.sol';

interface IGo {
    /// @notice Returns the address of the UniqueIdentity contract.
    function uniqueIdentity() external returns (IUniqueIdentity);

    function go(address account) external view returns (bool);

    function goOnlyIdTypes(address account, uint256[] memory onlyIdTypes) external view returns (bool);
}
