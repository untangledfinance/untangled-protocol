// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '@openzeppelin/contracts/interfaces/IERC20.sol';
import './base/SecuritizationPoolServiceBase.sol';
import '../../interfaces/INoteToken.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';

import {IDistributionOperator} from './IDistributionOperator.sol';
import {IDistributionTranche} from './IDistributionTranche.sol';
import {ICrowdSale} from '../note-sale/crowdsale/ICrowdSale.sol';
import {UntangledMath} from '../../libraries/UntangledMath.sol';
import {ISecuritizationLockDistribution} from './ISecuritizationLockDistribution.sol';
import {ISecuritizationTGE} from './ISecuritizationTGE.sol';
import {ISecuritizationPoolStorage} from './ISecuritizationPoolStorage.sol';

/// @title DistributionOperator
/// @author Untangled Team
contract DistributionOperator is SecuritizationPoolServiceBase, IDistributionOperator {
    using ConfigHelper for Registry;

    enum SettlementType {
        FEE,
        REDEEM,
        PRINCIPAL_REDEEM,
        INTEREST_REDEEM
    }

    struct DistributePercent {
        address investor;
        uint256 currencyDistribute;
        uint256 tokenBurn;
        uint256 paidInterestAmount;
    }

    event TokensRedeemed(
        address indexed redeemer,
        address indexed tokenAddress,
        uint256 currencyAmount,
        uint256 tokenAmount
    );

    /// @dev Create a redemption request for note token
    /// @param noteToken SOT/JOT token address
    /// @param tokenAmount Amount of SOT/JOT token to be redeemed
    function _makeRedeemRequest(INoteToken noteToken, uint256 tokenAmount) internal {
        require(
            registry.getNoteTokenFactory().isExistingTokens(address(noteToken)),
            'DistributionOperator: Invalid NoteToken'
        );
        require(noteToken.balanceOf(_msgSender()) >= tokenAmount, 'DistributionOperator: Invalid token amount');

        address poolAddress = noteToken.poolAddress();
        ISecuritizationTGE securitizationPool = ISecuritizationTGE(poolAddress);

        require(
            securitizationPool.sotToken() != address(noteToken) || securitizationPool.jotToken() != address(noteToken),
            'DistributionOperator: invalid note token'
        );
        IDistributionTranche tranche = registry.getDistributionTranche();

        require(
            noteToken.allowance(_msgSender(), address(tranche)) >= tokenAmount,
            'DistributionOperator: Invalid token allowance'
        );

        uint256 tokenPrice = registry.getDistributionAssessor().calcTokenPrice(poolAddress, address(noteToken));
        uint256 decimals = noteToken.decimals();

        address pot = ISecuritizationPoolStorage(poolAddress).pot();
        uint256 tokenToBeRedeemed = Math.min(
            (INoteToken(securitizationPool.underlyingCurrency()).balanceOf(pot) * 10 ** decimals) / tokenPrice,
            tokenAmount
        );

        uint256 currencyAmtToBeDistributed = (tokenToBeRedeemed * tokenPrice) / 10 ** decimals;

        ISecuritizationLockDistribution securitizationLockDistribute = ISecuritizationLockDistribution(poolAddress);
        securitizationLockDistribute.increaseLockedDistributeBalance(
            address(noteToken),
            _msgSender(),
            currencyAmtToBeDistributed,
            tokenToBeRedeemed
        );

        tranche.redeemToken(address(noteToken), _msgSender(), tokenToBeRedeemed);
    }

    /// @notice Redeem SOT/JOT token and receive an amount of currency
    /// @dev Fulfill redeem request created
    /// @param redeemer Redeemer wallet address
    /// @param pool Pool address which issued note token
    /// @param tokenAddress Note token address
    function _redeem(address redeemer, address pool, address tokenAddress) private returns (uint256) {
        ISecuritizationLockDistribution securitizationPool = ISecuritizationLockDistribution(pool);

        uint256 currencyLocked = securitizationPool.lockedDistributeBalances(tokenAddress, redeemer);
        uint256 tokenRedeem = securitizationPool.lockedRedeemBalances(tokenAddress, redeemer);
        if (currencyLocked > 0) {
            _redeem(redeemer, pool, tokenAddress, tokenRedeem, currencyLocked, registry.getDistributionTranche(), pool);

            if (ISecuritizationTGE(pool).sotToken() == tokenAddress) {
                ICrowdSale(ISecuritizationPoolStorage(pool).tgeAddress()).onRedeem(currencyLocked);
            } else if (ISecuritizationTGE(pool).jotToken() == tokenAddress) {
                ICrowdSale(ISecuritizationPoolStorage(pool).secondTGEAddress()).onRedeem(currencyLocked);
            }
        }

        emit TokensRedeemed(redeemer, tokenAddress, currencyLocked, tokenRedeem);

        return currencyLocked;
    }

    /// @dev This calls make redeem request and redeem at once
    function makeRedeemRequestAndRedeem(
        address pool,
        INoteToken noteToken,
        uint256 tokenAmount
    ) public whenNotPaused nonReentrant returns (uint256) {
        _makeRedeemRequest(noteToken, tokenAmount);
        uint256 currencyLocked = _redeem(_msgSender(), pool, address(noteToken));
        address poolOfPot = registry.getSecuritizationManager().potToPool(_msgSender());
        if (poolOfPot != address(0)) {
            ISecuritizationTGE(poolOfPot).increaseReserve(currencyLocked);
        }
        return currencyLocked;
    }

    function makeRedeemRequestAndRedeemBatch(
        address[] calldata pools,
        INoteToken[] calldata noteTokens,
        uint256[] calldata tokenAmounts
    ) public whenNotPaused nonReentrant {
        address redeemer = _msgSender();
        for (uint256 i = 0; i < pools.length; i = UntangledMath.uncheckedInc(i)) {
            _makeRedeemRequest(noteTokens[i], tokenAmounts[i]);
            _redeem(redeemer, pools[i], address(noteTokens[i]));
        }
    }

    function _redeem(
        address redeemer,
        address pool,
        address tokenAddress,
        uint256 tokenAmount,
        uint256 currencyAmount,
        IDistributionTranche tranche,
        address securitizationPool
    ) internal {
        ISecuritizationLockDistribution(securitizationPool).decreaseLockedDistributeBalance(
            tokenAddress,
            redeemer,
            currencyAmount,
            tokenAmount
        );
        tranche.redeem(redeemer, pool, tokenAddress, currencyAmount, tokenAmount);
    }

    uint256[50] private __gap;
}
