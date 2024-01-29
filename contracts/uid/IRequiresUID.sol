// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.19;

interface IRequiresUID {
    function hasAllowedUID(address sender) external view returns (bool);
}
