// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;
import './ISecuritizationPool.sol';

interface IDistributionAssessor {
    struct NoteToken {
        address poolAddress;
        address noteTokenAddress;
        uint256 balance;
        uint256 apy;
    }

    /// @notice current individual asset price for the "SOT" tranche at the current timestamp
    function getSOTTokenPrice(address securitizationPool) external view returns (uint256);

    /// @notice calculates the token price for the "JOT" tranche at the current timestamp
    function getJOTTokenPrice(address securitizationPool) external view returns (uint256);

    /// @notice calculates the token price for a specific token address in the securitization pool
    function calcTokenPrice(address pool, address tokenAddress) external view returns (uint256);

    function getTokenValues(
        address[] calldata tokenAddresses,
        address[] calldata investors
    ) external view returns (uint256[] memory);

    function getTokenPrices(
        address[] calldata pools,
        address[] calldata tokenAddresses
    ) external view returns (uint256[] memory);

    function getExternalTokenInfos(address poolAddress) external view returns (NoteToken[] memory);

    /// @notice the available cash balance in the securitization pool
    function getCashBalance(address pool) external view returns (uint256);

    /// @notice calculates the corresponding total asset value for a specific token address, investor, and end time
    function calcCorrespondingTotalAssetValue(address tokenAddress, address investor) external view returns (uint256);
}
