// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/interfaces/IERC20.sol';
import {INoteToken} from '../../interfaces/INoteToken.sol';
import {IPool} from '../../interfaces/IPool.sol';
import {ISecuritizationPoolValueService} from '../../interfaces/ISecuritizationPoolValueService.sol';
import {SecuritizationPoolServiceBase} from './base/SecuritizationPoolServiceBase.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {UntangledMath} from '../../libraries/UntangledMath.sol';
import {DataTypes, ONE_HUNDRED_PERCENT} from '../../libraries/DataTypes.sol';
import {IMintedNormalTGE} from '../../interfaces/IMintedNormalTGE.sol';

/// @title SecuritizationPoolValueService
/// @author Untangled Team
/// @dev Calculate pool's values
contract SecuritizationPoolValueService is SecuritizationPoolServiceBase, ISecuritizationPoolValueService {
    using Math for uint256;

    uint256 public constant RATE_SCALING_FACTOR = 10 ** 4;
    uint256 public constant YEAR_LENGTH_IN_DAYS = 365;
    // All time units in seconds
    uint256 public constant MINUTE_LENGTH_IN_SECONDS = 60;
    uint256 public constant HOUR_LENGTH_IN_SECONDS = MINUTE_LENGTH_IN_SECONDS * 60;
    uint256 public constant DAY_LENGTH_IN_SECONDS = HOUR_LENGTH_IN_SECONDS * 24;
    uint256 public constant YEAR_LENGTH_IN_SECONDS = DAY_LENGTH_IN_SECONDS * YEAR_LENGTH_IN_DAYS;

    function getAssetInterestRates(
        address poolAddress,
        bytes32[] calldata tokenIds
    ) public view returns (uint256[] memory) {
        uint256 tokenIdsLength = tokenIds.length;
        uint256[] memory interestRates = new uint256[](tokenIdsLength);
        for (uint256 i; i < tokenIdsLength; i++) {
            interestRates[i] = getAssetInterestRate(poolAddress, tokenIds[i]);
        }
        return interestRates;
    }

    function getAssetInterestRate(address poolAddress, bytes32 tokenId) public view returns (uint256) {
        uint256 interestRate = IPool(poolAddress).getAsset(tokenId).interestRate;

        return interestRate;
    }

    function getAssetRiskScores(
        address poolAddress,
        bytes32[] calldata tokenIds
    ) public view returns (uint256[] memory) {
        uint256 tokenIdsLength = tokenIds.length;
        uint256[] memory riskScores = new uint256[](tokenIdsLength);

        IPool poolNAV = IPool(poolAddress);
        for (uint256 i; i < tokenIdsLength; i++) {
            riskScores[i] = poolNAV.risk(tokenIds[i]);
        }
        return riskScores;
    }

    function getExpectedLATAssetValue(address poolAddress) public view returns (uint256) {
        return IPool(poolAddress).currentNAV();
    }

    function getExpectedAssetValue(address poolAddress, bytes32 tokenId) public view returns (uint256) {
        IPool poolNav = IPool(poolAddress);
        return poolNav.currentNAVAsset(tokenId);
    }

    function getExpectedAssetValues(
        address poolAddress,
        bytes32[] calldata tokenIds
    ) public view returns (uint256[] memory expectedAssetsValues) {
        expectedAssetsValues = new uint256[](tokenIds.length);
        IPool poolNav = IPool(poolAddress);
        for (uint i = 0; i < tokenIds.length; i++) {
            expectedAssetsValues[i] = poolNav.currentNAVAsset(tokenIds[i]);
        }

        return expectedAssetsValues;
    }

    function getDebtAssetValues(
        address poolAddress,
        bytes32[] calldata tokenIds
    ) public view returns (uint256[] memory debtAssetsValues) {
        debtAssetsValues = new uint256[](tokenIds.length);
        IPool poolNav = IPool(poolAddress);
        for (uint i = 0; i < tokenIds.length; i++) {
            debtAssetsValues[i] = poolNav.debt(uint256(tokenIds[i]));
        }

        return debtAssetsValues;
    }

    /// @inheritdoc ISecuritizationPoolValueService
    function getExpectedAssetsValue(address poolAddress) public view returns (uint256 expectedAssetsValue) {
        expectedAssetsValue = 0;
        IPool securitizationPool = IPool(poolAddress);

        expectedAssetsValue = expectedAssetsValue + getExpectedLATAssetValue(poolAddress);
    }

    function getPoolValue(address poolAddress) public view returns (uint256) {
        IPool securitizationPool = IPool(poolAddress);
        require(address(securitizationPool) != address(0), 'Pool was not deployed');
        uint256 nAVpoolValue = getExpectedAssetsValue(poolAddress);

        // use reserve variable instead
        uint256 balancePool = IPool(poolAddress).reserve();
        uint256 poolValue = balancePool + nAVpoolValue;

        return poolValue;
    }

    /// @inheritdoc ISecuritizationPoolValueService
    function getJuniorRatio(address poolAddress) public view returns (uint256) {
        return IPool(poolAddress).calcJuniorRatio();
    }

    function getApprovedReserved(address poolAddress) public view returns (uint256 approvedReserved) {
        address poolPot = IPool(poolAddress).pot();
        address underlyingCurrency = IPool(poolAddress).underlyingCurrency();
        uint256 currentAllowance = IERC20(underlyingCurrency).allowance(poolPot, poolAddress);

        return currentAllowance;
    }

    function getMaxAvailableReserve(
        address poolAddress,
        uint256 sotRequest
    ) public view returns (uint256, uint256, uint256) {
        IPool pool = IPool(poolAddress);

        uint256 decimals = INoteToken(pool.sotToken()).decimals();

        (uint256 jotPrice, uint256 sotPrice) = pool.calcTokenPrices();
        uint256 reserve = pool.reserve();
        uint256 nav = pool.currentNAV();
        uint256 ableToWithdraw = Math.min(getApprovedReserved(poolAddress), reserve);
        uint256 expectedSOTCurrencyAmount = (sotRequest * sotPrice) / 10 ** decimals;

        // When we withdraw all SOT in reserve/approved
        if (expectedSOTCurrencyAmount > ableToWithdraw) {
            return (ableToWithdraw, (ableToWithdraw * 10 ** decimals) / sotPrice, 0);
        }

        uint256 jotAllowedCurrencyAmount;
        {
            uint256 poolValue = reserve + nav;
            (uint256 seniorDebt, uint256 seniorBalance) = pool.seniorDebtAndBalance();
            uint256 seniorAsset = Math.min(seniorDebt + seniorBalance, poolValue);
            uint256 minFirstLossCushion = pool.minFirstLossCushion();

            jotAllowedCurrencyAmount =
                poolValue -
                expectedSOTCurrencyAmount -
                ((seniorAsset - expectedSOTCurrencyAmount) * RATE_SCALING_FACTOR) /
                (ONE_HUNDRED_PERCENT - minFirstLossCushion);
        }

        uint256 ableToWithdrawLeft = ableToWithdraw - expectedSOTCurrencyAmount;

        // When we withdraw all JOT in reserve/approved
        if (jotAllowedCurrencyAmount > ableToWithdrawLeft) {
            return (
                ableToWithdraw,
                (expectedSOTCurrencyAmount * 10 ** decimals) / sotPrice,
                (ableToWithdrawLeft * 10 ** decimals) / jotPrice
            );
        }

        // When we withdraw all JOT able to
        return (
            expectedSOTCurrencyAmount + jotAllowedCurrencyAmount,
            (expectedSOTCurrencyAmount * 10 ** decimals) / sotPrice,
            (jotAllowedCurrencyAmount * 10 ** decimals) / jotPrice
        );
    }

    // get current individual asset for SOT tranche
    function getSOTTokenPrice(address securitizationPool) public view returns (uint256) {
        (, uint256 sotTokenPrice) = IPool(securitizationPool).calcTokenPrices();
        return sotTokenPrice;
    }

    function calcCorrespondingTotalAssetValue(address tokenAddress, address investor) public view returns (uint256) {
        return _calcCorrespondingAssetValue(tokenAddress, investor);
    }

    /// @dev Calculate SOT/JOT asset value belongs to an investor
    /// @param tokenAddress Address of SOT or JOT token
    /// @param investor Investor's wallet
    /// @return The value in pool's underlying currency
    function _calcCorrespondingAssetValue(address tokenAddress, address investor) internal view returns (uint256) {
        INoteToken notesToken = INoteToken(tokenAddress);
        uint256 tokenPrice = calcTokenPrice(notesToken.poolAddress(), tokenAddress);
        uint256 tokenBalance = notesToken.balanceOf(investor);

        return (tokenBalance * tokenPrice) / 10 ** notesToken.decimals();
    }

    /// @notice Calculate SOT/JOT asset value for multiple investors
    function calcCorrespondingAssetValue(
        address tokenAddress,
        address[] calldata investors
    ) external view returns (uint256[] memory values) {
        uint256 investorsLength = investors.length;
        values = new uint256[](investorsLength);

        for (uint256 i = 0; i < investorsLength; i = UntangledMath.uncheckedInc(i)) {
            values[i] = _calcCorrespondingAssetValue(tokenAddress, investors[i]);
        }
    }

    function calcTokenPrice(address pool, address tokenAddress) public view returns (uint256) {
        IPool securitizationPool = IPool(pool);
        (uint256 jotTokenPrice, uint256 sotTokenPrice) = IPool(pool).calcTokenPrices();
        if (tokenAddress == securitizationPool.sotToken()) return sotTokenPrice;
        if (tokenAddress == securitizationPool.jotToken()) return jotTokenPrice;
        return 0;
    }

    function getTokenPrices(
        address[] calldata pools,
        address[] calldata tokenAddresses
    ) public view returns (uint256[] memory tokenPrices) {
        tokenPrices = new uint256[](pools.length);

        for (uint i = 0; i < pools.length; i++) {
            tokenPrices[i] = calcTokenPrice(pools[i], tokenAddresses[i]);
        }

        return tokenPrices;
    }

    function getTokenValues(
        address[] calldata tokenAddresses,
        address[] calldata investors
    ) public view returns (uint256[] memory tokenValues) {
        tokenValues = new uint256[](investors.length);

        for (uint i = 0; i < investors.length; i++) {
            tokenValues[i] = _calcCorrespondingAssetValue(tokenAddresses[i], investors[i]);
        }

        return tokenValues;
    }

    function getJOTTokenPrice(address securitizationPool) public view returns (uint256) {
        (uint256 jotTokenPrice, ) = IPool(securitizationPool).calcTokenPrices();
        return jotTokenPrice;
    }

    function getCashBalance(address pool) external view returns (uint256) {
        return INoteToken(IPool(pool).underlyingCurrency()).balanceOf(IPool(pool).pot());
    }
}
