// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import '../../../storage/Registry.sol';
import '../../../interfaces/INoteToken.sol';

interface INoteTokenFactory {
    event TokenCreated(
        address indexed token,
        address indexed poolAddress,
        Configuration.NOTE_TOKEN_TYPE indexed tokenType,
        uint8 decimals,
        string ticker
    );

    event UpdateNoteTokenImplementation(address indexed newAddress);

    function tokens(uint256 idx) external view returns (INoteToken);

    function isExistingTokens(address tokenAddress) external view returns (bool);

    function changeMinterRole(address token, address newController) external;

    function setNoteTokenImplementation(address newAddress) external;

    function noteTokenImplementation() external view returns (address);

    /// @notice Creates a new NoteToken contract instance with the specified parameters
    /// Initializes the token with the provided parameters, including the pool address and note token type
    function createToken(
        address poolAddress,
        Configuration.NOTE_TOKEN_TYPE noteTokenType,
        uint8 _nDecimals,
        string calldata ticker
    ) external returns (address);
}
