// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol';
import {ERC20BurnableUpgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
import {IERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol';

import {UntangledMath} from '../../libraries/UntangledMath.sol';
import {INoteTokenVault} from "./INoteTokenVault.sol";
import {INoteToken} from '../../interfaces/INoteToken.sol';
import {ISecuritizationTGE} from './ISecuritizationTGE.sol';
import { BACKEND_ADMIN } from './types.sol';
import "../../storage/Registry.sol";
import "../../libraries/ConfigHelper.sol";

/// @title NoteTokenVault
/// @author Untangled Team
/// @notice NoteToken redemption
contract NoteTokenVault is Initializable, PausableUpgradeable, AccessControlEnumerableUpgradeable, INoteTokenVault {
    using ConfigHelper for Registry;
    Registry public registry;

    /// @dev Pool redeem disabled value
    mapping(address => bool) public poolRedeemDisabled;
    /// @dev Pool total SOT redeem
    mapping(address => uint256) public poolTotalSOTRedeem;
    /// @dev Pool total JOT redeem
    mapping(address => uint256) public poolTotalJOTRedeem;
    /// @dev Pool user redeem order
    mapping(address => mapping(address => UserOrder)) public poolUserRedeems;

    /// @dev Checks if redeeming is allowed for a given pool.
    /// @param pool The address of the pool to check.
    modifier orderAllowed(address pool) {
        require(
            poolRedeemDisabled[pool] == false,
            "redeem-not-allowed"
        );
        _;
    }

    function initialize(Registry _registry) public initializer {
        __Pausable_init_unchained();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        registry = _registry;
    }

    /// @inheritdoc INoteTokenVault
    function redeemOrder(address pool, address noteTokenAddress, uint256 noteTokenRedeemAmount) public orderAllowed(pool) {
        address jotTokenAddress = ISecuritizationTGE(pool).jotToken();
        address sotTokenAddress = ISecuritizationTGE(pool).sotToken();
        require(noteTokenAddress == jotTokenAddress || noteTokenAddress == sotTokenAddress, "NoteTokenVault: Invalid token address");
        address usr = _msgSender();

        if (noteTokenAddress == jotTokenAddress) {
            uint256 currentRedeemAmount = poolUserRedeems[pool][usr].redeemJOTAmount;
            require(currentRedeemAmount == 0, "NoteTokenVault: User already created redeem order");
            poolUserRedeems[pool][usr].redeemJOTAmount = noteTokenRedeemAmount;
            poolTotalJOTRedeem[pool] = poolTotalJOTRedeem[pool] + noteTokenRedeemAmount;
            require(INoteToken(jotTokenAddress).transferFrom(usr, address(this), noteTokenRedeemAmount), "token-transfer-to-pool-failed");
            uint256 noteTokenPrice = registry.getDistributionAssessor().getJOTTokenPrice(pool);

            emit RedeemOrder(pool, noteTokenAddress, usr, noteTokenRedeemAmount, noteTokenPrice);
        } else if (noteTokenAddress == sotTokenAddress) {
            uint256 currentRedeemAmount = poolUserRedeems[pool][usr].redeemSOTAmount;
            require(currentRedeemAmount == 0, "NoteTokenVault: User already created redeem order");
            poolUserRedeems[pool][usr].redeemSOTAmount = noteTokenRedeemAmount;
            poolTotalSOTRedeem[pool] = poolTotalSOTRedeem[pool] + noteTokenRedeemAmount;
            require(INoteToken(sotTokenAddress).transferFrom(usr, address(this), noteTokenRedeemAmount), "token-transfer-to-pool-failed");
            uint256 noteTokenPrice = registry.getDistributionAssessor().getJOTTokenPrice(pool);

            emit RedeemOrder(pool, noteTokenAddress, usr, noteTokenRedeemAmount, noteTokenPrice);
        }
    }

    /// @inheritdoc INoteTokenVault
    function disburseAll(
        address pool,
        address noteTokenAddress,
        address[] memory toAddresses,
        uint256[] memory currencyAmounts,
        uint256[] memory redeemedNoteAmounts
    ) onlyRole(BACKEND_ADMIN) public {
        ISecuritizationTGE poolTGE = ISecuritizationTGE(pool);
        address jotTokenAddress = poolTGE.jotToken();
        address sotTokenAddress = poolTGE.sotToken();
        require(noteTokenAddress == jotTokenAddress || noteTokenAddress == sotTokenAddress, "NoteTokenVault: Invalid token address");

        uint256 totalCurrencyAmount = 0;
        uint256 userLength = toAddresses.length;

        if (noteTokenAddress == jotTokenAddress) {
            uint256 totalJOTRedeemed = 0;
            for (uint256 i = 0; i < userLength; i = UntangledMath.uncheckedInc(i)) {
                totalCurrencyAmount += currencyAmounts[i];
                totalJOTRedeemed += redeemedNoteAmounts[i];
                poolTGE.disburse(toAddresses[i], currencyAmounts[i]);
                poolUserRedeems[pool][toAddresses[i]].redeemJOTAmount -= redeemedNoteAmounts[i];
                ERC20BurnableUpgradeable(jotTokenAddress).burn(redeemedNoteAmounts[i]);
            }

            poolTotalJOTRedeem[pool] -= totalJOTRedeemed;
        } else if (noteTokenAddress == sotTokenAddress) {
            uint256 totalSOTRedeemed = 0;
            for (uint256 i = 0; i < userLength; i = UntangledMath.uncheckedInc(i)) {
                totalCurrencyAmount += currencyAmounts[i];
                totalSOTRedeemed += redeemedNoteAmounts[i];
                poolTGE.disburse(toAddresses[i], currencyAmounts[i]);
                poolUserRedeems[pool][toAddresses[i]].redeemSOTAmount -= redeemedNoteAmounts[i];
                ERC20BurnableUpgradeable(sotTokenAddress).burn(redeemedNoteAmounts[i]);
            }

            poolTotalSOTRedeem[pool] -= totalSOTRedeemed;
        }

        poolTGE.decreaseReserve(totalCurrencyAmount);
        emit DisburseOrder(pool, noteTokenAddress, toAddresses, currencyAmounts, redeemedNoteAmounts);
    }

    /// @inheritdoc INoteTokenVault
    function setRedeemDisabled(address pool, bool _redeemDisabled) onlyRole(BACKEND_ADMIN) public {
        poolRedeemDisabled[pool] = _redeemDisabled;
        emit SetRedeemDisabled(pool, _redeemDisabled);
    }

    /// @inheritdoc INoteTokenVault
    function redeemDisabled(address pool) public view returns (bool) {
        return poolRedeemDisabled[pool];
    }

    /// @inheritdoc INoteTokenVault
    function totalJOTRedeem(address pool) public view override returns (uint256) {
        return poolTotalJOTRedeem[pool];
    }

    /// @inheritdoc INoteTokenVault
    function totalSOTRedeem(address pool) public view override returns (uint256) {
        return poolTotalSOTRedeem[pool];
    }

    /// @inheritdoc INoteTokenVault
    function userRedeemJOTOrder(address pool, address usr) public view override returns (uint256) {
        return poolUserRedeems[pool][usr].redeemJOTAmount;
    }

    /// @inheritdoc INoteTokenVault
    function userRedeemSOTOrder(address pool, address usr) public view override returns (uint256) {
        return poolUserRedeems[pool][usr].redeemSOTAmount;
    }

    uint256[49] private __gap;
}
