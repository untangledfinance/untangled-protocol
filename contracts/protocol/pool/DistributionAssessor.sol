// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

import './base/SecuritizationPoolServiceBase.sol';
import '../../interfaces/INoteToken.sol';

import {UntangledMath} from '../../libraries/UntangledMath.sol';
import {IDistributionAssessor} from './IDistributionAssessor.sol';
import {ISecuritizationPoolValueService} from './ISecuritizationPoolValueService.sol';

/// @title DistributionAssessor
/// @author Untangled Team
/// @notice Calculate values in a pool
contract DistributionAssessor is SecuritizationPoolServiceBase, IDistributionAssessor {
    using ConfigHelper for Registry;

    function _getTokenPrice(
        ISecuritizationPool securitizationPool,
        ERC20 noteToken,
        uint256 asset
    ) private view returns (uint256) {
        require(address(securitizationPool) != address(0), 'DistributionAssessor: Invalid pool address');

        uint256 totalSupply = noteToken.totalSupply();
        uint256 decimals = noteToken.decimals();

        require(address(noteToken) != address(0), 'DistributionAssessor: Invalid note token address');
        // In initial state, SOT price = 1$
        if (noteToken.totalSupply() == 0)
            return 10 ** (ERC20(securitizationPool.underlyingCurrency()).decimals() - decimals);

        return asset / totalSupply;
    }

    // get current individual asset for SOT tranche
    /// @inheritdoc IDistributionAssessor
    function getSOTTokenPrice(ISecuritizationPool securitizationPool) public view override returns (uint256) {
        ISecuritizationPoolValueService poolService = registry.getSecuritizationPoolValueService();
        uint256 seniorAsset = poolService.getSeniorAsset(address(securitizationPool));
        return _getTokenPrice(securitizationPool, ERC20(securitizationPool.sotToken()), seniorAsset);
    }

    /// @inheritdoc IDistributionAssessor
    function calcCorrespondingTotalAssetValue(
        address tokenAddress,
        address investor
    ) external view override returns (uint256) {
        return _calcCorrespondingAssetValue(tokenAddress, investor);
    }

    /// @dev Calculate SOT/JOT asset value belongs to an investor
    /// @param tokenAddress Address of SOT or JOT token
    /// @param investor Investor's wallet
    /// @return The value in pool's underlying currency
    function _calcCorrespondingAssetValue(address tokenAddress, address investor) internal view returns (uint256) {
        INoteToken notesToken = INoteToken(tokenAddress);
        ISecuritizationPool securitizationPool = ISecuritizationPool(notesToken.poolAddress());

        // if (Configuration.NOTE_TOKEN_TYPE(notesToken.noteTokenType()) == Configuration.NOTE_TOKEN_TYPE.SENIOR) {
        //     tokenPrice = getSOTTokenPrice(securitizationPool);
        // } else {
        //     tokenPrice = getJOTTokenPrice(securitizationPool);
        // }

        uint256 tokenPrice = calcTokenPrice(address(securitizationPool), tokenAddress);

        uint256 tokenRedeem = securitizationPool.lockedRedeemBalances(tokenAddress, investor);
        uint256 tokenBalance = notesToken.balanceOf(investor) - tokenRedeem;
        return tokenBalance * tokenPrice;
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

    /// @inheritdoc IDistributionAssessor
    function calcTokenPrice(address pool, address tokenAddress) public view override returns (uint256) {
        ISecuritizationPool securitizationPool = ISecuritizationPool(pool);
        if (tokenAddress == securitizationPool.sotToken()) return getSOTTokenPrice(securitizationPool);
        if (tokenAddress == securitizationPool.jotToken()) return getJOTTokenPrice(securitizationPool);
        return 0;
    }

    /// @inheritdoc IDistributionAssessor
    function getJOTTokenPrice(ISecuritizationPool securitizationPool) public view override returns (uint256) {
        ISecuritizationPoolValueService poolService = registry.getSecuritizationPoolValueService();
        uint256 seniorAsset = poolService.getJuniorAsset(address(securitizationPool));
        return _getTokenPrice(securitizationPool, ERC20(securitizationPool.jotToken()), seniorAsset);
    }

    /// @inheritdoc IDistributionAssessor
    function getCashBalance(address pool) public view override returns (uint256) {
        ISecuritizationPool securitizationPool = ISecuritizationPool(pool);
        return
            IERC20(securitizationPool.underlyingCurrency()).balanceOf(securitizationPool.pot()) -
            securitizationPool.totalLockedDistributeBalance();
    }

    uint256[50] private __gap;
}
