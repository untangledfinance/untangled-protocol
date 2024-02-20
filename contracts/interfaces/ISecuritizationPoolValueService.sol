// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;
import "../libraries/DataTypes.sol";
interface ISecuritizationPoolValueService {
    /// @notice calculates the total expected value of all assets in the securitization pool at a given timestamp
    /// @dev iterates over the NFT assets and token assets in the pool, calling getExpectedAssetValue
    /// or getExpectedERC20AssetValue for each asset and summing up the values
    function getExpectedAssetsValue(address poolAddress) external view returns (uint256 expectedAssetsValue);

    /// @notice the amount which belongs to the senior investor (SOT) in a pool
    /// @dev  calculates  the amount which accrues interest for the senior tranche in the securitization pool at a given timestamp
    function getSeniorAsset(address poolAddress) external view returns (uint256);

    /// @notice calculates  the amount of Junior Debt at the current time
    function getJuniorAsset(address poolAddress) external view returns (uint256);

    /// @notice returns the rate that belongs to Junior investors at the current time
    function getJuniorRatio(address poolAddress) external view returns (uint256);

    function getPoolValue(address poolAddress) external view returns (uint256);
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

    function getExternalTokenInfos(address poolAddress) external view returns (DataTypes.NoteToken[] memory);

    /// @notice the available cash balance in the securitization pool
    function getCashBalance(address pool) external view returns (uint256);

    /// @notice calculates the corresponding total asset value for a specific token address, investor, and end time
    function calcCorrespondingTotalAssetValue(address tokenAddress, address investor) external view returns (uint256);
}
