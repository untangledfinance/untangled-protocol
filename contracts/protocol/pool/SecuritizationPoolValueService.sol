// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol';
import {IERC20MetadataUpgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC20MetadataUpgradeable.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';

import {INoteToken} from '../../interfaces/INoteToken.sol';
import {IUntangledERC721} from '../../interfaces/IUntangledERC721.sol';
import {ICrowdSale} from '../../interfaces/ICrowdSale.sol';
import {ISecuritizationPool} from './ISecuritizationPool.sol';
import {ISecuritizationPoolValueService} from './ISecuritizationPoolValueService.sol';
import {IDistributionAssessor} from './IDistributionAssessor.sol';
import {SecuritizationPoolServiceBase} from './base/SecuritizationPoolServiceBase.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {Registry} from '../../storage/Registry.sol';
import {Configuration} from '../../libraries/Configuration.sol';
import {UntangledMath} from '../../libraries/UntangledMath.sol';
import {ISecuritizationPoolNAV} from './ISecuritizationPoolNAV.sol';
import {ISecuritizationPoolStorage} from './ISecuritizationPoolStorage.sol';
import {ISecuritizationTGE} from './ISecuritizationTGE.sol';
import {RiskScore} from './base/types.sol';
import {ONE_HUNDRED_PERCENT} from './types.sol';

/// @title SecuritizationPoolValueService
/// @author Untangled Team
/// @dev Calculate pool's values
contract SecuritizationPoolValueService is SecuritizationPoolServiceBase, ISecuritizationPoolValueService {
    using ConfigHelper for Registry;
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
        uint256 interestRate = ISecuritizationPoolNAV(poolAddress).getAsset(tokenId).interestRate;

        return interestRate;
    }

    function getAssetRiskScores(
        address poolAddress,
        bytes32[] calldata tokenIds
    ) public view returns (uint256[] memory) {
        uint256 tokenIdsLength = tokenIds.length;
        uint256[] memory riskScores = new uint256[](tokenIdsLength);

        ISecuritizationPoolNAV poolNAV = ISecuritizationPoolNAV(poolAddress);
        for (uint256 i; i < tokenIdsLength; i++) {
            riskScores[i] = poolNAV.risk(tokenIds[i]);
        }
        return riskScores;
    }

    function getExpectedLATAssetValue(address poolAddress) public view returns (uint256) {
        return ISecuritizationPoolNAV(poolAddress).currentNAV();
    }

    function getExpectedAssetValue(address poolAddress, bytes32 tokenId) public view returns (uint256) {
        ISecuritizationPoolNAV poolNav = ISecuritizationPoolNAV(poolAddress);
        return poolNav.currentNAVAsset(tokenId);
    }

    function getExpectedAssetValues(
        address poolAddress,
        bytes32[] calldata tokenIds
    ) public view returns (uint256[] memory expectedAssetsValues) {
        expectedAssetsValues = new uint256[](tokenIds.length);
        ISecuritizationPoolNAV poolNav = ISecuritizationPoolNAV(poolAddress);
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
        ISecuritizationPoolNAV poolNav = ISecuritizationPoolNAV(poolAddress);
        for (uint i = 0; i < tokenIds.length; i++) {
            debtAssetsValues[i] = poolNav.debt(uint256(tokenIds[i]));
        }

        return debtAssetsValues;
    }

    /// @inheritdoc ISecuritizationPoolValueService
    function getExpectedAssetsValue(address poolAddress) public view returns (uint256 expectedAssetsValue) {
        expectedAssetsValue = 0;
        ISecuritizationPool securitizationPool = ISecuritizationPool(poolAddress);

        expectedAssetsValue = expectedAssetsValue + getExpectedLATAssetValue(poolAddress);

        uint256 tokenAssetAddressesLength = securitizationPool.getTokenAssetAddressesLength();
        for (uint256 i = 0; i < tokenAssetAddressesLength; i = UntangledMath.uncheckedInc(i)) {
            address tokenAddress = securitizationPool.tokenAssetAddresses(i);
            expectedAssetsValue =
                expectedAssetsValue +
                registry.getDistributionAssessor().calcCorrespondingTotalAssetValue(tokenAddress, poolAddress);
        }
    }

    function getPoolValue(address poolAddress) public view returns (uint256) {
        ISecuritizationPool securitizationPool = ISecuritizationPool(poolAddress);
        require(address(securitizationPool) != address(0), 'Pool was not deployed');
        uint256 nAVpoolValue = getExpectedAssetsValue(poolAddress);

        // use reserve variable instead
        uint256 balancePool = ISecuritizationTGE(poolAddress).reserve();
        uint256 poolValue = balancePool + nAVpoolValue;

        return poolValue;
    }

    // @notice this function return value 90 in example
    function getBeginningSeniorAsset(address poolAddress) public view returns (uint256) {
        require(poolAddress != address(0), 'Invalid pool address');
        ISecuritizationTGE securitizationPool = ISecuritizationTGE(poolAddress);
        address sotToken = securitizationPool.sotToken();
        if (sotToken == address(0)) {
            return 0;
        }
        uint256 tokenSupply = INoteToken(sotToken).totalSupply();
        return tokenSupply;
    }

    // @notice this function will return 72 in example
    function getBeginningSeniorDebt(address poolAddress) public view returns (uint256) {
        (uint256 beginningSeniorDebt, ) = _getBeginningSeniorDebt(poolAddress);

        return beginningSeniorDebt;
    }

    function _getBeginningSeniorDebt(address poolAddress) public view returns (uint256, uint256) {
        ISecuritizationPool securitizationPool = ISecuritizationPool(poolAddress);
        require(address(securitizationPool) != address(0), 'Pool was not deployed');

        uint256 navpoolValue = getExpectedAssetsValue(poolAddress);

        uint256 balancePool = ISecuritizationTGE(poolAddress).reserve();
        uint256 poolValue = balancePool + navpoolValue;
        if (poolValue == 0) return (0, 0);

        uint256 beginningSeniorAsset = getBeginningSeniorAsset(poolAddress);

        return ((beginningSeniorAsset * navpoolValue) / poolValue, beginningSeniorAsset);
    }

    // @notice get beginning of senior debt, get interest of this debt over number of interval
    function getSeniorDebt(address poolAddress) public view returns (uint256) {
        uint256 beginningSeniorDebt = getBeginningSeniorDebt(poolAddress);
        if (beginningSeniorDebt == 0) return 0;

        return _getSeniorDebt(poolAddress, beginningSeniorDebt);
    }

    function _getSeniorDebt(address poolAddress, uint256 beginningSeniorDebt) internal view returns (uint256) {
        ISecuritizationPoolStorage securitizationPool = ISecuritizationPoolStorage(poolAddress);
        require(address(securitizationPool) != address(0), 'Pool was not deployed');
        uint256 seniorInterestRate = ISecuritizationTGE(poolAddress).interestRateSOT();
        uint256 openingTime = securitizationPool.openingBlockTimestamp();
        uint256 compoundingPeriods = block.timestamp - openingTime;
        uint256 oneYearInSeconds = YEAR_LENGTH_IN_SECONDS;

        uint256 seniorDebt = beginningSeniorDebt +
            (beginningSeniorDebt * seniorInterestRate * compoundingPeriods) /
            (RATE_SCALING_FACTOR * oneYearInSeconds);
        return seniorDebt;
    }

    // @notice get beginning senior asset, then calculate ratio reserve on pools.Finaly multiple them
    function getSeniorBalance(address poolAddress) public view returns (uint256) {
        (uint256 beginningSeniorDebt, uint256 beginningSeniorAsset) = _getBeginningSeniorDebt(poolAddress);
        return beginningSeniorAsset - beginningSeniorDebt;
    }

    function _getSeniorAsset(address poolAddress) internal view returns (uint256, uint256, uint256) {
        uint256 navpoolValue = getExpectedAssetsValue(poolAddress);
        uint256 balancePool = ISecuritizationTGE(poolAddress).reserve();
        uint256 poolValue = balancePool + navpoolValue;

        if (poolValue == 0) {
            return (0, 0, navpoolValue);
        }

        uint256 seniorAsset;
        uint256 beginningSeniorAsset = getBeginningSeniorAsset(poolAddress);
        uint256 beginningSeniorDebt = (beginningSeniorAsset * navpoolValue) / poolValue;
        uint256 seniorDebt = _getSeniorDebt(poolAddress, beginningSeniorDebt);

        uint256 seniorBalance = beginningSeniorAsset - beginningSeniorDebt;
        uint256 expectedSeniorAsset = seniorDebt + seniorBalance;

        if (poolValue > expectedSeniorAsset) {
            seniorAsset = expectedSeniorAsset;
        } else {
            seniorAsset = poolValue;
        }

        return (seniorAsset, poolValue, navpoolValue);
    }

    /// @inheritdoc ISecuritizationPoolValueService
    function getSeniorAsset(address poolAddress) public view returns (uint256) {
        (uint256 seniorAsset, , ) = _getSeniorAsset(poolAddress);
        return seniorAsset;
    }

    /// @inheritdoc ISecuritizationPoolValueService
    function getJuniorAsset(address poolAddress) public view returns (uint256) {
        (uint256 seniorAsset, uint256 poolValue, ) = _getSeniorAsset(poolAddress);

        uint256 juniorAsset = 0;
        if (poolValue >= seniorAsset) {
            juniorAsset = poolValue - seniorAsset;
        }

        return juniorAsset;
    }

    /// @inheritdoc ISecuritizationPoolValueService
    function getJuniorRatio(address poolAddress) public view returns (uint256) {
        uint256 rateSenior = getSeniorRatio(poolAddress);
        require(rateSenior <= 100 * RATE_SCALING_FACTOR, 'securitizationPool.rateSenior >100');

        return 100 * RATE_SCALING_FACTOR - rateSenior;
    }

    function getSeniorRatio(address poolAddress) public view returns (uint256) {
        (uint256 seniorAsset, uint256 poolValue, ) = _getSeniorAsset(poolAddress);
        if (poolValue == 0) {
            return 0;
        }

        return (seniorAsset * 100 * RATE_SCALING_FACTOR) / poolValue;
    }

    function getExpectedSeniorAssets(address poolAddress) public view returns (uint256) {
        uint256 navpoolValue = getExpectedAssetsValue(poolAddress);
        uint256 balancePool = ISecuritizationTGE(poolAddress).reserve();
        uint256 poolValue = balancePool + navpoolValue;

        if (poolValue == 0) {
            return 0;
        }

        uint256 beginningSeniorAsset = getBeginningSeniorAsset(poolAddress);

        uint256 seniorBalance = (beginningSeniorAsset * navpoolValue) / poolValue;
        uint256 seniorDebt = _getSeniorDebt(poolAddress, seniorBalance);

        return seniorDebt + seniorBalance;
    }

    function getMaxAvailableReserve(
        address poolAddress,
        uint256 sotRequest
    ) public view returns (uint256, uint256, uint256) {
        ISecuritizationTGE securitizationPool = ISecuritizationTGE(poolAddress);
        address sotToken = securitizationPool.sotToken();
        address jotToken = securitizationPool.jotToken();
        uint256 reserve = securitizationPool.reserve();

        uint256 sotPrice = registry.getDistributionAssessor().calcTokenPrice(poolAddress, sotToken);
        if (sotPrice == 0) {
            return (reserve, 0, 0);
        }
        uint256 expectedSOTCurrencyAmount = (sotRequest * sotPrice) / 10 ** INoteToken(sotToken).decimals();
        if (reserve <= expectedSOTCurrencyAmount) {
            return (reserve, (reserve * (10 ** INoteToken(sotToken).decimals())) / sotPrice, 0);
        }

        uint256 jotPrice = registry.getDistributionAssessor().calcTokenPrice(poolAddress, jotToken);
        uint256 x = solveReserveEquation(poolAddress, expectedSOTCurrencyAmount, sotRequest);
        if (jotPrice == 0) {
            return (x + expectedSOTCurrencyAmount, sotRequest, 0);
        }
        uint256 maxJOTRedeem = (x * 10 ** INoteToken(jotToken).decimals()) / jotPrice;

        return (x + expectedSOTCurrencyAmount, sotRequest, maxJOTRedeem);
    }

    function solveReserveEquation(
        address poolAddress,
        uint256 expectedSOTCurrencyAmount,
        uint256 sotRequest
    ) public view returns (uint256) {
        ISecuritizationTGE securitizationPool = ISecuritizationTGE(poolAddress);
        address sotToken = securitizationPool.sotToken();
        uint32 minFirstLossCushion = securitizationPool.minFirstLossCushion();
        uint64 openingBlockTimestamp = ISecuritizationPoolStorage(poolAddress).openingBlockTimestamp();

        uint256 poolValue = getPoolValue(poolAddress) - expectedSOTCurrencyAmount;
        uint256 nav = ISecuritizationPoolNAV(poolAddress).currentNAV();
        uint256 maxSeniorRatio = ONE_HUNDRED_PERCENT - minFirstLossCushion; // a = maxSeniorRatio / ONE_HUNDRED_PERCENT

        if (maxSeniorRatio == 0) {
            return 0;
        }

        uint256 remainingSOTSupply = INoteToken(sotToken).totalSupply() - sotRequest;

        uint256 b = (2 * poolValue * maxSeniorRatio) / ONE_HUNDRED_PERCENT - remainingSOTSupply;
        uint256 c = ((poolValue ** 2) * maxSeniorRatio) /
            ONE_HUNDRED_PERCENT -
            remainingSOTSupply *
            poolValue -
            (remainingSOTSupply *
                nav *
                ISecuritizationTGE(poolAddress).interestRateSOT() *
                (block.timestamp - openingBlockTimestamp)) /
            (ONE_HUNDRED_PERCENT * 365 days);
        uint256 delta = b ** 2 - (4 * c * maxSeniorRatio) / ONE_HUNDRED_PERCENT;
        uint256 x = ((b - delta.sqrt()) * ONE_HUNDRED_PERCENT) / (2 * maxSeniorRatio);
        return x;
    }

    uint256[50] private __gap;
}
