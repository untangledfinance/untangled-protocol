// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

import './base/SecuritizationPoolServiceBase.sol';
import '../../interfaces/INoteToken.sol';

import {UntangledMath} from '../../libraries/UntangledMath.sol';
import {IDistributionAssessor} from './IDistributionAssessor.sol';
import {ISecuritizationPoolValueService} from './ISecuritizationPoolValueService.sol';
import {ISecuritizationTGE} from './ISecuritizationTGE.sol';
import {ISecuritizationPoolStorage} from './ISecuritizationPoolStorage.sol';
import {IMintedTGE} from '../note-sale/IMintedTGE.sol';

/// @title DistributionAssessor
/// @author Untangled Team
/// @notice Calculate values in a pool
contract DistributionAssessor is SecuritizationPoolServiceBase, IDistributionAssessor {
    using ConfigHelper for Registry;

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
    /// @inheritdoc IDistributionAssessor
    function getSOTTokenPrice(address securitizationPool) public view override returns (uint256) {
        ISecuritizationPoolValueService poolService = registry.getSecuritizationPoolValueService();
        uint256 seniorAsset = poolService.getSeniorAsset(address(securitizationPool));
        return
            _getTokenPrice(
                securitizationPool,
                INoteToken(ISecuritizationTGE(securitizationPool).sotToken()),
                seniorAsset
            );
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

    /// @inheritdoc IDistributionAssessor
    function calcTokenPrice(address pool, address tokenAddress) public view override returns (uint256) {
        ISecuritizationTGE securitizationPool = ISecuritizationTGE(pool);
        if (tokenAddress == securitizationPool.sotToken()) return getSOTTokenPrice(pool);
        if (tokenAddress == securitizationPool.jotToken()) return getJOTTokenPrice(pool);
        return 0;
    }

    function getTokenPrices(
        address[] calldata pools,
        address[] calldata tokenAddresses
    ) public view override returns (uint256[] memory tokenPrices) {
        tokenPrices = new uint256[](pools.length);

        for (uint i = 0; i < pools.length; i++) {
            tokenPrices[i] = calcTokenPrice(pools[i], tokenAddresses[i]);
        }

        return tokenPrices;
    }

    function getTokenValues(
        address[] calldata tokenAddresses,
        address[] calldata investors
    ) public view override returns (uint256[] memory tokenValues) {
        tokenValues = new uint256[](investors.length);

        for (uint i = 0; i < investors.length; i++) {
            tokenValues[i] = _calcCorrespondingAssetValue(tokenAddresses[i], investors[i]);
        }

        return tokenValues;
    }

    function getExternalTokenInfos(address poolAddress) public view override returns (NoteToken[] memory noteTokens) {
        ISecuritizationPool securitizationPool = ISecuritizationPool(poolAddress);

        uint256 tokenAssetAddressesLength = securitizationPool.getTokenAssetAddressesLength();
        noteTokens = new NoteToken[](tokenAssetAddressesLength);
        for (uint256 i = 0; i < tokenAssetAddressesLength; i = UntangledMath.uncheckedInc(i)) {
            address tokenAddress = securitizationPool.tokenAssetAddresses(i);
            INoteToken noteToken = INoteToken(tokenAddress);
            ISecuritizationPoolStorage notePool = ISecuritizationPoolStorage(noteToken.poolAddress());

            uint256 apy;

            if (tokenAddress == ISecuritizationTGE(noteToken.poolAddress()).sotToken()) {
                apy = IMintedTGE(notePool.tgeAddress()).getInterest();
            } else {
                apy = IMintedTGE(notePool.secondTGEAddress()).getInterest();
            }

            noteTokens[i] = NoteToken({
                poolAddress: address(notePool),
                noteTokenAddress: tokenAddress,
                balance: noteToken.balanceOf(poolAddress),
                apy: apy
            });
        }

        return noteTokens;
    }

    /// @inheritdoc IDistributionAssessor
    function getJOTTokenPrice(address securitizationPool) public view override returns (uint256) {
        ISecuritizationPoolValueService poolService = registry.getSecuritizationPoolValueService();
        uint256 juniorrAsset = poolService.getJuniorAsset(address(securitizationPool));
        return
            _getTokenPrice(
                securitizationPool,
                INoteToken(ISecuritizationTGE(securitizationPool).jotToken()),
                juniorrAsset
            );
    }

    /// @inheritdoc IDistributionAssessor
    function getCashBalance(address pool) public view override returns (uint256) {
        return
            INoteToken(ISecuritizationTGE(pool).underlyingCurrency()).balanceOf(ISecuritizationPoolStorage(pool).pot());
    }

    uint256[50] private __gap;
}
