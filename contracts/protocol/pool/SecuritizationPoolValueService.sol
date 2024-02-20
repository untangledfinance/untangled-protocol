// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import '@openzeppelin/contracts/utils/math/Math.sol';
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

        uint256 tokenAssetAddressesLength = securitizationPool.getTokenAssetAddressesLength();
        for (uint256 i = 0; i < tokenAssetAddressesLength; i = UntangledMath.uncheckedInc(i)) {
            address tokenAddress = securitizationPool.tokenAssetAddresses(i);
            expectedAssetsValue =
                expectedAssetsValue +
                calcCorrespondingTotalAssetValue(tokenAddress, poolAddress);
        }
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

    // @notice this function return value 90 in example
    function getBeginningSeniorAsset(address poolAddress) public view returns (uint256) {
        require(poolAddress != address(0), 'Invalid pool address');
        IPool securitizationPool = IPool(poolAddress);
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
        IPool securitizationPool = IPool(poolAddress);
        require(address(securitizationPool) != address(0), 'Pool was not deployed');

        uint256 navpoolValue = getExpectedAssetsValue(poolAddress);

        uint256 balancePool = IPool(poolAddress).reserve();
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
        IPool securitizationPool = IPool(poolAddress);
        require(address(securitizationPool) != address(0), 'Pool was not deployed');
        uint256 seniorInterestRate = IPool(poolAddress).interestRateSOT();
        uint256 openingTime = securitizationPool.openingBlockTimestamp();
        uint256 compoundingPeriods = block.timestamp - openingTime;
        uint256 oneYearInSeconds = YEAR_LENGTH_IN_SECONDS;

        uint256 seniorDebt = beginningSeniorDebt +
            (beginningSeniorDebt * seniorInterestRate * compoundingPeriods) /
            (ONE_HUNDRED_PERCENT * oneYearInSeconds);
        return seniorDebt;
    }

    // @notice get beginning senior asset, then calculate ratio reserve on pools.Finaly multiple them
    function getSeniorBalance(address poolAddress) public view returns (uint256) {
        (uint256 beginningSeniorDebt, uint256 beginningSeniorAsset) = _getBeginningSeniorDebt(poolAddress);
        return beginningSeniorAsset - beginningSeniorDebt;
    }

    function _getSeniorAsset(address poolAddress) internal view returns (uint256, uint256, uint256) {
        uint256 navpoolValue = getExpectedAssetsValue(poolAddress);
        uint256 balancePool = IPool(poolAddress).reserve();
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
        uint256 balancePool = IPool(poolAddress).reserve();
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
        IPool securitizationPool = IPool(poolAddress);
        address sotToken = securitizationPool.sotToken();
        address jotToken = securitizationPool.jotToken();
        uint256 reserve = securitizationPool.reserve();

        uint256 sotPrice = calcTokenPrice(poolAddress, sotToken);
        if (sotPrice == 0) {
            return (reserve, 0, 0);
        }
        uint256 expectedSOTCurrencyAmount = (sotRequest * sotPrice) / 10 ** INoteToken(sotToken).decimals();
        if (reserve <= expectedSOTCurrencyAmount) {
            return (reserve, (reserve * (10 ** INoteToken(sotToken).decimals())) / sotPrice, 0);
        }

        uint256 jotPrice = calcTokenPrice(poolAddress, jotToken);
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
        IPool securitizationPool = IPool(poolAddress);
        address sotToken = securitizationPool.sotToken();
        uint32 minFirstLossCushion = securitizationPool.minFirstLossCushion();
        uint64 openingBlockTimestamp = IPool(poolAddress).openingBlockTimestamp();

        uint256 poolValue = getPoolValue(poolAddress) - expectedSOTCurrencyAmount;
        uint256 nav = IPool(poolAddress).currentNAV();
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
                IPool(poolAddress).interestRateSOT() *
                (block.timestamp - openingBlockTimestamp)) /
            (ONE_HUNDRED_PERCENT * 365 days);
        uint256 delta = b ** 2 - (4 * c * maxSeniorRatio) / ONE_HUNDRED_PERCENT;
        uint256 x = ((b - delta.sqrt()) * ONE_HUNDRED_PERCENT) / (2 * maxSeniorRatio);
        return x;
    }

    function _getTokenPrice(
        address securitizationPool,
        INoteToken noteToken,
        uint256 asset
    ) private view returns (uint256) {
        require(address(securitizationPool) != address(0), 'DistributionAssessor: Invalid pool address');

        uint256 totalSupply = noteToken.totalSupply();
        uint256 decimals = noteToken.decimals();

        require(address(noteToken) != address(0), 'DistributionAssessor: Invalid note token address');
        // In initial state, SOT price = 1$
        if (noteToken.totalSupply() == 0) return 10 ** decimals;

        return (asset * 10 ** decimals) / totalSupply;
    }

    // get current individual asset for SOT tranche
    function getSOTTokenPrice(address securitizationPool) public view returns (uint256) {
        uint256 seniorAsset = getSeniorAsset(address(securitizationPool));
        return _getTokenPrice(securitizationPool, INoteToken(IPool(securitizationPool).sotToken()), seniorAsset);
    }

    function calcCorrespondingTotalAssetValue(
        address tokenAddress,
        address investor
    ) public view returns (uint256) {
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
        if (tokenAddress == securitizationPool.sotToken()) return getSOTTokenPrice(pool);
        if (tokenAddress == securitizationPool.jotToken()) return getJOTTokenPrice(pool);
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

    function getExternalTokenInfos(address poolAddress) public view returns (DataTypes.NoteToken[] memory noteTokens) {
        IPool securitizationPool = IPool(poolAddress);

        uint256 tokenAssetAddressesLength = securitizationPool.getTokenAssetAddressesLength();
        noteTokens = new DataTypes.NoteToken[](tokenAssetAddressesLength);
        for (uint256 i = 0; i < tokenAssetAddressesLength; i = UntangledMath.uncheckedInc(i)) {
            address tokenAddress = securitizationPool.tokenAssetAddresses(i);
            INoteToken noteToken = INoteToken(tokenAddress);
            IPool notePool = IPool(noteToken.poolAddress());

            uint256 apy;

            if (tokenAddress == IPool(noteToken.poolAddress()).sotToken()) {
                apy = IMintedNormalTGE(notePool.tgeAddress()).getInterest();
            } else {
                apy = IMintedNormalTGE(notePool.secondTGEAddress()).getInterest();
            }

            noteTokens[i] = DataTypes.NoteToken({
                poolAddress: address(notePool),
                noteTokenAddress: tokenAddress,
                balance: noteToken.balanceOf(poolAddress),
                apy: apy
            });
        }

        return noteTokens;
    }

    function getJOTTokenPrice(address securitizationPool) public view returns (uint256) {
        uint256 juniorrAsset = getJuniorAsset(address(securitizationPool));
        return _getTokenPrice(securitizationPool, INoteToken(IPool(securitizationPool).jotToken()), juniorrAsset);
    }

    function getCashBalance(address pool) public view returns (uint256) {
        return INoteToken(IPool(pool).underlyingCurrency()).balanceOf(IPool(pool).pot());
    }
}
