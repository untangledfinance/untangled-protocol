// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {UntangledERC721} from '../../tokens/ERC721/UntangledERC721.sol';
import {IMintedNormalTGE} from '../../interfaces/IMintedNormalTGE.sol';
import {UntangledMath} from '../../libraries/UntangledMath.sol';
import {DataTypes, PRICE_DECIMAL, ONE, ONE_HUNDRED_PERCENT} from '../DataTypes.sol';
import {TransferHelper} from '../TransferHelper.sol';
import {GenericLogic} from './GenericLogic.sol';
import {TGELogic} from './TGELogic.sol';
import {Math} from '../Math.sol';

/**
 * @title Untangled's Rebase Logic
 * @notice Provides pool's rebase functions
 * @author Untangled Team
 */
library RebaseLogic {
    /// @notice accumulates the senior interest
    /// @return _seniorDebt the senior debt
    function dripSeniorDebt(DataTypes.Storage storage _poolStorage) public returns (uint256) {
        uint256 _seniorDebt = seniorDebt(_poolStorage);
        _poolStorage.seniorDebt = _seniorDebt;
        _poolStorage.lastUpdateSeniorInterest = uint64(block.timestamp);
        return _seniorDebt;
    }

    /// @notice returns the senior debt with up to date interest
    /// @return _seniorDebt senior debt
    function seniorDebt(DataTypes.Storage storage _poolStorage) public view returns (uint256 _seniorDebt) {
        uint256 lastUpdateSeniorInterest = uint256(_poolStorage.lastUpdateSeniorInterest);
        if (block.timestamp >= lastUpdateSeniorInterest) {
            uint256 convertedInterestRate = ONE +
                (_poolStorage.interestRateSOT * ONE) /
                (ONE_HUNDRED_PERCENT * 365 days);

            return
                GenericLogic.chargeInterest(_poolStorage.seniorDebt, convertedInterestRate, lastUpdateSeniorInterest);
        }
        return _poolStorage.seniorDebt;
    }

    function rebase(DataTypes.Storage storage _poolStorage, uint256 _nav, uint256 _reserve) public {
        (uint256 seniorDebt_, uint256 seniorBalance_) = _rebase(
            _nav,
            _reserve,
            calcExpectedSeniorAsset(_poolStorage.seniorBalance, dripSeniorDebt(_poolStorage))
        );
        _poolStorage.seniorDebt = seniorDebt_;
        _poolStorage.seniorBalance = seniorBalance_;
    }

    /// @notice changes the senior asset value based on new supply or redeems
    /// @param _seniorSupply senior supply amount
    /// @param _seniorRedeem senior redeem amount
    function changeSeniorAsset(
        DataTypes.Storage storage _poolStorage,
        uint256 _nav,
        uint256 _reserve,
        uint256 _seniorSupply,
        uint256 _seniorRedeem
    ) external {
        (uint256 seniorDebt_, uint256 seniorBalance_) = _rebase(
            _nav,
            _reserve,
            calcExpectedSeniorAsset(
                _seniorRedeem,
                _seniorSupply,
                _poolStorage.seniorBalance,
                dripSeniorDebt(_poolStorage)
            )
        );
        _poolStorage.seniorDebt = seniorDebt_;
        _poolStorage.seniorBalance = seniorBalance_;
    }

    /// @notice internal function for the rebalance of senior debt and balance
    /// @param _seniorAsset the expected senior asset value (senior debt + senior balance)
    function _rebase(uint256 _nav, uint256 _reserve, uint256 _seniorAsset) public pure returns (uint256, uint256) {
        // re-balancing according to new ratio

        uint256 seniorRatio_ = calcSeniorRatio(_seniorAsset, _nav, _reserve);

        // in that case the entire juniorAsset is lost
        // the senior would own everything that' left
        if (seniorRatio_ > ONE) {
            seniorRatio_ = ONE;
        }

        uint256 seniorBalance_;
        uint256 seniorDebt_ = Math.rmul(_nav, seniorRatio_);
        if (seniorDebt_ > _seniorAsset) {
            seniorDebt_ = _seniorAsset;
            seniorBalance_ = 0;
        } else {
            seniorBalance_ = Math.safeSub(_seniorAsset, seniorDebt_);
        }
        return (seniorDebt_, seniorBalance_);
    }

    /// @notice calculates the senior ratio
    /// @param seniorAsset the current senior asset value
    /// @param nav the current NAV
    /// @param reserve the current reserve
    /// @return seniorRatio the senior ratio
    function calcSeniorRatio(
        uint256 seniorAsset,
        uint256 nav,
        uint256 reserve
    ) public pure returns (uint256 seniorRatio) {
        // note: NAV + reserve == seniorAsset + juniorAsset (invariant: always true)
        uint256 assets = Math.safeAdd(nav, reserve);
        if (assets == 0) {
            return 0;
        }

        // if expectedSeniorAsset is passed ratio can be greater than ONE
        return Math.rdiv(seniorAsset, assets);
    }

    /// @notice expected senior return if no losses occur
    /// @param _seniorRedeem the senior redeem amount
    /// @param _seniorSupply the senior supply amount
    /// @param _seniorBalance the current senior balance
    /// @param _seniorDebt the current senior debt
    /// @return expectedSeniorAsset the expected senior asset value
    function calcExpectedSeniorAsset(
        uint256 _seniorRedeem,
        uint256 _seniorSupply,
        uint256 _seniorBalance,
        uint256 _seniorDebt
    ) public pure returns (uint256 expectedSeniorAsset) {
        return Math.safeSub(Math.safeAdd(Math.safeAdd(_seniorDebt, _seniorBalance), _seniorSupply), _seniorRedeem);
    }

    /// @notice calculates the expected Senior asset value
    /// @param _seniorDebt the current senior debt
    /// @param _seniorBalance the current senior balance
    /// @return seniorAsset returns the senior asset value
    function calcExpectedSeniorAsset(
        uint256 _seniorDebt,
        uint256 _seniorBalance
    ) public pure returns (uint256 seniorAsset) {
        return Math.safeAdd(_seniorDebt, _seniorBalance);
    }

    /// @notice calculates the senior token price
    /// @return seniorTokenPrice the senior token price in RAY decimal (10^27)
    function calcSeniorTokenPrice(
        uint256 _nav,
        uint256 _reserve,
        uint256 _seniorDebt,
        uint256 _seniorBalance,
        uint256 _sotTotalSupply
    ) external pure returns (uint256 seniorTokenPrice) {
        return _calcSeniorTokenPrice(_nav, _reserve, _seniorDebt, _seniorBalance, _sotTotalSupply);
    }

    /// @notice calculates the junior token price
    /// @return juniorTokenPrice the junior token price in RAY decimal (10^27)
    function calcJuniorTokenPrice(
        uint256 _nav,
        uint256 _reserve,
        uint256 _seniorDebt,
        uint256 _seniorBalance,
        uint256 _jotTotalSupply
    ) external pure returns (uint256 juniorTokenPrice) {
        return _calcJuniorTokenPrice(_nav, _reserve, _seniorDebt, _seniorBalance, _jotTotalSupply);
    }

    /// @notice calculates the senior and junior token price based on current NAV and reserve
    /// @return juniorTokenPrice the junior token price in RAY decimal (10^27)
    /// @return seniorTokenPrice the senior token price in RAY decimal (10^27)
    function calcTokenPrices(
        uint256 _nav,
        uint256 _reserve,
        uint256 _seniorDebt,
        uint256 _seniorBalance,
        uint256 _jotTotalSupply,
        uint256 _sotTotalSupply
    ) external pure returns (uint256 juniorTokenPrice, uint256 seniorTokenPrice) {
        return (
            _calcJuniorTokenPrice(_nav, _reserve, _seniorDebt, _seniorBalance, _jotTotalSupply),
            _calcSeniorTokenPrice(_nav, _reserve, _seniorDebt, _seniorBalance, _sotTotalSupply)
        );
    }

    /// @notice internal function to calculate the senior token price
    /// @param _nav the NAV
    /// @param _reserve the reserve
    /// @param _seniorDebt the senior debt
    /// @param _seniorBalance the senior balance
    /// @param _sotTotalSupply the token supply
    /// @return seniorTokenPrice the senior token price in RAY decimal (10^27)
    function _calcSeniorTokenPrice(
        uint256 _nav,
        uint256 _reserve,
        uint256 _seniorDebt,
        uint256 _seniorBalance,
        uint256 _sotTotalSupply
    ) internal pure returns (uint256 seniorTokenPrice) {
        // the coordinator interface will pass the reserveAvailable

        if ((_nav == 0 && _reserve == 0) || _sotTotalSupply <= 2) {
            // we are using a tolerance of 2 here, as there can be minimal supply leftovers after all redemptions due to rounding
            // initial token price at start 1.00
            return ONE;
        }

        uint256 poolValue = Math.safeAdd(_nav, _reserve);
        uint256 seniorAssetValue = calcExpectedSeniorAsset(_seniorDebt, _seniorBalance);

        if (poolValue < seniorAssetValue) {
            seniorAssetValue = poolValue;
        }
        return Math.rdiv(seniorAssetValue, _sotTotalSupply);
    }

    /// @notice internal function to calculate the junior token price
    /// @param _nav the NAV
    /// @param _reserve the reserve
    /// @param _seniorDebt the senior debt
    /// @param _seniorBalance the senior balance
    /// @param _jotTotalSupply the token supply
    /// @return juniorTokenPrice the junior token price in RAY decimal (10^27)
    function _calcJuniorTokenPrice(
        uint256 _nav,
        uint256 _reserve,
        uint256 _seniorDebt,
        uint256 _seniorBalance,
        uint256 _jotTotalSupply
    ) internal pure returns (uint256 juniorTokenPrice) {
        if ((_nav == 0 && _reserve == 0) || _jotTotalSupply <= 2) {
            // we are using a tolerance of 2 here, as there can be minimal supply leftovers after all redemptions due to rounding
            // initial token price at start 1.00
            return ONE;
        }
        // reserve includes creditline from maker
        uint256 poolValue = Math.safeAdd(_nav, _reserve);

        // includes creditline from mkr
        uint256 seniorAssetValue = calcExpectedSeniorAsset(_seniorDebt, _seniorBalance);

        if (poolValue < seniorAssetValue) {
            return 0;
        }

        return Math.rdiv(Math.safeSub(poolValue, seniorAssetValue), _jotTotalSupply);
    }

    /// @notice returns the current junior ratio protection in the Tinlake
    /// @return juniorRatio_ is denominated in RATE_SCALING_FACTOR
    function calcJuniorRatio(
        uint256 _nav,
        uint256 _reserve,
        uint256 _seniorDebt,
        uint256 _seniorBalance
    ) external pure returns (uint256 juniorRatio_) {
        uint256 seniorAsset_ = Math.safeAdd(_seniorDebt, _seniorBalance);
        uint256 assets_ = Math.safeAdd(_nav, _reserve);

        if (seniorAsset_ == 0 && assets_ == 0) {
            return 0;
        }

        if (seniorAsset_ == 0 && assets_ > 0) {
            return ONE_HUNDRED_PERCENT;
        }

        if (seniorAsset_ > assets_) {
            return 0;
        }

        return (Math.safeSub(ONE, Math.rdiv(seniorAsset_, assets_)) * ONE_HUNDRED_PERCENT) / ONE;
    }
}
