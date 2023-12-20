// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol';
import {IERC20MetadataUpgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC20MetadataUpgradeable.sol';

import {INoteToken} from '../../interfaces/INoteToken.sol';
import {IUntangledERC721} from '../../interfaces/IUntangledERC721.sol';
import {ICrowdSale} from '../../interfaces/ICrowdSale.sol';
import {ILoanRegistry} from '../../interfaces/ILoanRegistry.sol';

import {ISecuritizationPool} from './ISecuritizationPool.sol';
import {ISecuritizationPoolValueService} from './ISecuritizationPoolValueService.sol';
import {IDistributionAssessor} from './IDistributionAssessor.sol';

import {NAVCalculation} from './base/NAVCalculation.sol';
import {SecuritizationPoolServiceBase} from './base/SecuritizationPoolServiceBase.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {Registry} from '../../storage/Registry.sol';
import {Configuration} from '../../libraries/Configuration.sol';
import {UntangledMath} from '../../libraries/UntangledMath.sol';
import {IPoolNAV} from './IPoolNAV.sol';
import {ISecuritizationPoolStorage} from './ISecuritizationPoolStorage.sol';

import {ISecuritizationTGE} from './ISecuritizationTGE.sol';

import {RiskScore} from './base/types.sol';

/// @title SecuritizationPoolValueService
/// @author Untangled Team
/// @dev Calculate pool's values
contract SecuritizationPoolValueService is
    SecuritizationPoolServiceBase,
    NAVCalculation,
    ISecuritizationPoolValueService
{
    using ConfigHelper for Registry;

    uint256 public constant RATE_SCALING_FACTOR = 10 ** 4;

    function getPresentValueWithNAVCalculation(
        address poolAddress,
        uint256 principalAmount,
        uint256 expectTimeEarnInterest,
        uint256 interestRate,
        uint256 riskScoreIdx, // riskScoreIdx should be reduced 1 to be able to use because 0 means no specific riskScore
        uint256 overdue,
        uint256 secondTillCashFlow
    ) private view returns (uint256) {
        uint256 riskScoresLength = ISecuritizationPool(poolAddress).getRiskScoresLength();
        bool hasValidRiskScore = riskScoresLength > 0;
        if (hasValidRiskScore) {
            if (riskScoreIdx == 0) (hasValidRiskScore, riskScoreIdx) = getAssetRiskScoreIdx(poolAddress, overdue);
            else riskScoreIdx = riskScoreIdx > riskScoresLength ? riskScoresLength - 1 : riskScoreIdx - 1;
        }
        if (!hasValidRiskScore) {
            return
                (principalAmount *
                    UntangledMath.rpow(
                        UntangledMath.ONE +
                            ((interestRate * UntangledMath.ONE) / INTEREST_RATE_SCALING_FACTOR_PERCENT / 100) /
                            YEAR_LENGTH_IN_SECONDS,
                        expectTimeEarnInterest,
                        UntangledMath.ONE
                    )) / UntangledMath.ONE;
        }
        RiskScore memory riskscore = ISecuritizationPool(poolAddress).riskScores(riskScoreIdx);
        uint256 result = _calculateAssetValue(
            principalAmount,
            expectTimeEarnInterest,
            interestRate,
            overdue,
            secondTillCashFlow,
            riskscore
        );
        return result;
    }

    function getAssetInterestRate(
        address poolAddress,
        address tokenAddress,
        uint256 tokenId,
        uint256 timestamp
    ) public view returns (uint256) {
        IUntangledERC721 loanAssetToken = IUntangledERC721(tokenAddress);
        uint256 interestRate = loanAssetToken.getInterestRate(tokenId);

        uint256 riskScoresLength = ISecuritizationPool(poolAddress).getRiskScoresLength();

        bool hasValidRiskScore = riskScoresLength > 0;
        if (hasValidRiskScore) {
            uint256 riskScoreIdx = loanAssetToken.getRiskScore(tokenId);

            if (riskScoreIdx == 0) {
                uint256 expirationTimestamp = loanAssetToken.getExpirationTimestamp(tokenId);
                uint256 overdue = timestamp > expirationTimestamp ? timestamp - expirationTimestamp : 0;
                (hasValidRiskScore, riskScoreIdx) = getAssetRiskScoreIdx(poolAddress, overdue);
            } else riskScoreIdx = riskScoreIdx > riskScoresLength ? riskScoresLength - 1 : riskScoreIdx - 1;

            if (hasValidRiskScore) {
                RiskScore memory riskscore = ISecuritizationPool(poolAddress).riskScores(riskScoreIdx);
                return riskscore.interestRate;
            }
        }

        return interestRate;
    }

    function getAssetInterestRates(
        address poolAddress,
        address[] calldata tokenAddresses,
        uint256[] calldata tokenIds,
        uint256 timestamp
    ) external view returns (uint256[] memory) {
        uint256 tokenIdsLength = tokenIds.length;
        uint256[] memory interestRates = new uint256[](tokenIdsLength);
        for (uint256 i; i < tokenIdsLength; i++) {
            interestRates[i] = getAssetInterestRate(poolAddress, tokenAddresses[i], tokenIds[i], timestamp);
        }
        return interestRates;
    }

    function getExpectedLATAssetValue(address poolAddress) public view returns (uint256) {
        return IPoolNAV(ISecuritizationPoolStorage(poolAddress).poolNAV()).currentNAV();
    }

    function getExpectedERC20AssetValue(
        address poolAddress,
        address assetPoolAddress,
        address tokenAddress,
        uint256 interestRate,
        uint256 timestamp
    ) public view returns (uint256) {
        uint256 expirationTimestamp = ISecuritizationPoolStorage(assetPoolAddress).openingBlockTimestamp() +
            ISecuritizationTGE(assetPoolAddress).termLengthInSeconds();

        uint256 overdue = timestamp > expirationTimestamp ? timestamp - expirationTimestamp : 0;
        uint256 secondTillCashflow = expirationTimestamp > timestamp ? expirationTimestamp - timestamp : 0;

        uint256 totalDebt = registry.getDistributionAssessor().calcCorrespondingTotalAssetValue(
            tokenAddress,
            poolAddress
        );

        uint256 presentValue = getPresentValueWithNAVCalculation(
            poolAddress,
            totalDebt,
            0,
            interestRate,
            0,
            overdue,
            secondTillCashflow
        );

        if (timestamp < expirationTimestamp) {
            totalDebt = registry.getDistributionAssessor().calcCorrespondingTotalAssetValue(tokenAddress, poolAddress);
        }

        return presentValue < totalDebt ? presentValue : totalDebt;
    }

    function getExpectedAssetValue(address poolAddress, bytes32 tokenId) public view returns (uint256) {
        IPoolNAV poolNav = IPoolNAV(ISecuritizationPoolStorage(poolAddress).poolNAV());
        return poolNav.currentNAVAsset(tokenId);
    }

    function getExpectedAssetValues(
        address poolAddress,
        bytes32[] calldata tokenIds
    ) public view returns (uint256[] memory expectedAssetsValues) {
        expectedAssetsValues = new uint256[](tokenIds.length);
        IPoolNAV poolNav = IPoolNAV(ISecuritizationPoolStorage(poolAddress).poolNAV());
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
        IPoolNAV poolNav = IPoolNAV(ISecuritizationPoolStorage(poolAddress).poolNAV());
        for (uint i = 0; i < tokenIds.length; i++) {
            debtAssetsValues[i] = poolNav.debt(uint256(tokenIds[i]));
        }

        return debtAssetsValues;
    }

    /// @inheritdoc ISecuritizationPoolValueService
    function getExpectedAssetsValue(
        address poolAddress,
        uint256 timestamp
    ) external view returns (uint256 expectedAssetsValue) {
        expectedAssetsValue = 0;
        ISecuritizationPool securitizationPool = ISecuritizationPool(poolAddress);

        expectedAssetsValue =
            expectedAssetsValue +
            IPoolNAV(ISecuritizationPoolStorage(poolAddress).poolNAV()).currentNAV();

        uint256 tokenAssetAddressesLength = securitizationPool.getTokenAssetAddressesLength();
        for (uint256 i = 0; i < tokenAssetAddressesLength; i = UntangledMath.uncheckedInc(i)) {
            address tokenAddress = securitizationPool.tokenAssetAddresses(i);
            INoteToken notesToken = INoteToken(tokenAddress);
            if (notesToken.balanceOf(poolAddress) > 0) {
                expectedAssetsValue =
                    expectedAssetsValue +
                    getExpectedERC20AssetValue(
                        poolAddress,
                        notesToken.poolAddress(),
                        tokenAddress,
                        Configuration.NOTE_TOKEN_TYPE(notesToken.noteTokenType()) ==
                            Configuration.NOTE_TOKEN_TYPE.SENIOR
                            ? ISecuritizationTGE(notesToken.poolAddress()).interestRateSOT()
                            : 0,
                        timestamp
                    );
            }
        }
    }

    function getAssetRiskScoreIdx(
        address poolAddress,
        uint256 overdue
    ) public view returns (bool hasValidRiskScore, uint256 riskScoreIdx) {
        ISecuritizationPool securitizationPool = ISecuritizationPool(poolAddress);
        uint256 riskScoresLength = securitizationPool.getRiskScoresLength();
        for (riskScoreIdx = 0; riskScoreIdx < riskScoresLength; riskScoreIdx++) {
            uint32 daysPastDue = getDaysPastDueByIdx(securitizationPool, riskScoreIdx);
            if (overdue < daysPastDue) return (false, 0);
            else if (riskScoreIdx == riskScoresLength - 1) {
                return (true, riskScoreIdx);
            } else {
                uint32 nextDaysPastDue = getDaysPastDueByIdx(securitizationPool, riskScoreIdx + 1);
                if (overdue < nextDaysPastDue) return (true, riskScoreIdx);
            }
        }
    }

    function getDaysPastDueByIdx(ISecuritizationPool securitizationPool, uint256 idx) private view returns (uint32) {
        // (uint32 daysPastDue, , , , , , , , , , ) = securitizationPool.riskScores(idx);
        return securitizationPool.riskScores(idx).daysPastDue;
    }

    /// @inheritdoc ISecuritizationPoolValueService
    function getOutstandingPrincipalCurrencyByInvestor(address pool, address investor) public view returns (uint256) {
        ISecuritizationPoolStorage securitizationPool = ISecuritizationPoolStorage(pool);
        ICrowdSale crowdsale = ICrowdSale(securitizationPool.tgeAddress());

        return
            crowdsale.currencyRaisedByInvestor(investor) -
            ISecuritizationTGE(pool).paidPrincipalAmountSOTByInvestor(investor);
    }

    function getPoolValue(address poolAddress) external view returns (uint256) {
        ISecuritizationPool securitizationPool = ISecuritizationPool(poolAddress);
        require(address(securitizationPool) != address(0), 'Pool was not deployed');
        uint256 currentTimestamp = block.timestamp;
        uint256 nAVpoolValue = this.getExpectedAssetsValue(poolAddress, currentTimestamp);

        // use reserve variable instead
        uint256 balancePool = ISecuritizationTGE(poolAddress).reserve();
        uint256 poolValue = balancePool +
            nAVpoolValue -
            ISecuritizationPoolStorage(poolAddress).amountOwedToOriginator();

        return poolValue;
    }

    // @notice this function return value 90 in example
    function getBeginningSeniorAsset(address poolAddress) external view returns (uint256) {
        require(poolAddress != address(0), 'Invalid pool address');
        ISecuritizationTGE securitizationPool = ISecuritizationTGE(poolAddress);
        address sotToken = securitizationPool.sotToken();
        require(sotToken != address(0), 'Invalid sot address');
        uint256 tokenSupply = INoteToken(sotToken).totalSupply();
        uint256 tokenDecimals = INoteToken(sotToken).decimals();
        return
            tokenSupply *
            10 ** (IERC20MetadataUpgradeable(securitizationPool.underlyingCurrency()).decimals() - tokenDecimals);
    }

    // @notice this function will return 72 in example
    function getBeginningSeniorDebt(address poolAddress) external view returns (uint256) {
        uint256 poolValue = this.getPoolValue(poolAddress);
        if (poolValue == 0) return 0;
        // require(poolValue > 0, 'Pool value is 0');
        uint256 beginningSeniorAsset = this.getBeginningSeniorAsset(poolAddress);
        uint256 currentTimestamp = block.timestamp;
        uint256 nAVpoolValue = this.getExpectedAssetsValue(poolAddress, currentTimestamp);
        if (nAVpoolValue > poolValue) {
            return beginningSeniorAsset;
        }
        return (beginningSeniorAsset * nAVpoolValue) / poolValue;
    }

    // @notice get beginning of senior debt, get interest of this debt over number of interval
    function getSeniorDebt(address poolAddress) external view returns (uint256) {
        uint256 beginningSeniorDebt = this.getBeginningSeniorDebt(poolAddress);
        if (beginningSeniorDebt == 0) return 0;
        ISecuritizationPoolStorage securitizationPool = ISecuritizationPoolStorage(poolAddress);
        require(address(securitizationPool) != address(0), 'Pool was not deployed');
        uint256 seniorInterestRate = ISecuritizationTGE(poolAddress).interestRateSOT();
        uint256 openingTime = securitizationPool.openingBlockTimestamp();
        uint256 compoundingPeriods = block.timestamp - openingTime;
        uint256 oneYearInSeconds = NAVCalculation.YEAR_LENGTH_IN_SECONDS;

        uint256 seniorDebt = beginningSeniorDebt +
            (beginningSeniorDebt * seniorInterestRate * compoundingPeriods) /
            (RATE_SCALING_FACTOR * oneYearInSeconds);
        return seniorDebt;
    }

    // @notice get beginning senior asset, then calculate ratio reserve on pools.Finaly multiple them
    function getSeniorBalance(address poolAddress) external view returns (uint256) {
        return this.getBeginningSeniorAsset(poolAddress) - this.getBeginningSeniorDebt(poolAddress);
    }

    /// @inheritdoc ISecuritizationPoolValueService
    function getSeniorAsset(address poolAddress) external view returns (uint256) {
        // we need to change this value with interest rate by time
        uint256 seniorAsset;
        uint256 poolValue = this.getPoolValue(poolAddress);
        uint256 expectedSeniorAsset = this.getExpectedSeniorAssets(poolAddress);

        if (poolValue > expectedSeniorAsset) {
            seniorAsset = expectedSeniorAsset;
        } else {
            // case of default
            seniorAsset = poolValue;
        }

        return seniorAsset;
    }

    /// @inheritdoc ISecuritizationPoolValueService
    function getJuniorAsset(address poolAddress) external view returns (uint256) {
        uint256 poolValue = this.getPoolValue(poolAddress);
        uint256 seniorAsset = this.getSeniorAsset(poolAddress);
        uint256 juniorAsset = 0;
        if (poolValue >= seniorAsset) {
            juniorAsset = poolValue - seniorAsset;
        }

        return juniorAsset;
    }

    /// @inheritdoc ISecuritizationPoolValueService
    function getJuniorRatio(address poolAddress) external view returns (uint256) {
        uint256 rateSenior = this.getSeniorRatio(poolAddress);
        require(rateSenior <= 100 * RATE_SCALING_FACTOR, 'securitizationPool.rateSenior >100');

        return 100 * RATE_SCALING_FACTOR - rateSenior;
    }

    function getSeniorRatio(address poolAddress) external view returns (uint256) {
        uint256 seniorAsset = this.getSeniorAsset(poolAddress);
        uint256 poolValue = this.getPoolValue(poolAddress);
        if (poolValue == 0) {
            return 0;
        }

        return (seniorAsset * 100 * RATE_SCALING_FACTOR) / poolValue;
    }

    function getExpectedSeniorAssets(address poolAddress) external view returns (uint256) {
        uint256 senorDebt = this.getSeniorDebt(poolAddress);
        uint256 seniorBalance = this.getSeniorBalance(poolAddress);
        return senorDebt + seniorBalance;
    }

    uint256[50] private __gap;
}
