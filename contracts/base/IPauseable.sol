// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.19;

interface IPauseable {
    function pause() external;

    function unpause() external;

    function paused() external view returns (bool);
}
