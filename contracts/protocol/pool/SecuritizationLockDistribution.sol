// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {PausableUpgradeable} from '../../base/PauseableUpgradeable.sol';
import {ERC165Upgradeable} from '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol';
import {ReentrancyGuardUpgradeable} from '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

import {ISecuritizationLockDistribution} from './ISecuritizationLockDistribution.sol';
import {Registry} from '../../storage/Registry.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {Configuration} from '../../libraries/Configuration.sol';
import {RegistryInjection} from './RegistryInjection.sol';

import {INoteToken} from '../../interfaces/INoteToken.sol';
import {ISecuritizationPoolExtension, SecuritizationPoolExtension} from './SecuritizationPoolExtension.sol';
import {SecuritizationAccessControl} from './SecuritizationAccessControl.sol';
import {SecuritizationPoolStorage} from './SecuritizationPoolStorage.sol';
import {ISecuritizationPoolStorage} from './ISecuritizationPoolStorage.sol';
import {ISecuritizationTranche} from './ISecuritizationTranche.sol';

// RegistryInjection,
// ERC165Upgradeable,
// PausableUpgradeable,
// SecuritizationPoolStorage,
// ISecuritizationLockDistribution

contract SecuritizationLockDistribution is
    ERC165Upgradeable,
    RegistryInjection,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    SecuritizationPoolExtension,
    SecuritizationPoolStorage,
    SecuritizationAccessControl,
    ISecuritizationLockDistribution,
    ISecuritizationTranche
{
    using ConfigHelper for Registry;

    function installExtension(
        bytes memory params
    ) public virtual override(ISecuritizationPoolExtension, SecuritizationAccessControl, SecuritizationPoolStorage) onlyCallInTargetPool {}

    function lockedDistributeBalances(address tokenAddress, address investor) public view override returns (uint256) {
        Storage storage $ = _getStorage();
        return $.lockedDistributeBalances[tokenAddress][investor];
    }

    function lockedRedeemBalances(address tokenAddress, address investor) public view override returns (uint256) {
        Storage storage $ = _getStorage();
        return $.lockedRedeemBalances[tokenAddress][investor];
    }

    function totalLockedRedeemBalances(address tokenAddress) public view override returns (uint256) {
        Storage storage $ = _getStorage();
        return $.totalLockedRedeemBalances[tokenAddress];
    }

    function totalLockedDistributeBalance() public view override returns (uint256) {
        Storage storage $ = _getStorage();
        return $.totalLockedDistributeBalance;
    }

    function totalRedeemedCurrency() public view override returns (uint256) {
        Storage storage $ = _getStorage();
        return $.totalRedeemedCurrency;
    }

    function totalJOTRedeem() public view override returns (uint256) {
        Storage storage $ = _getStorage();
        return $.totalJOTRedeem;
    }

    function totalSOTRedeem() public view override returns (uint256) {
        Storage storage $ = _getStorage();
        return $.totalSOTRedeem;
    }

    function userRedeemSOTOrder(address usr) public view override returns (uint256) {
        Storage storage $ = _getStorage();
        return $.userRedeems[usr].redeemSOTAmount;
    }

    function userRedeemJOTOrder(address usr) public view override returns (uint256) {
        Storage storage $ = _getStorage();
        return $.userRedeems[usr].redeemJOTAmount;
    }


    // // token address -> user -> locked
    // mapping(address => mapping(address => uint256)) public override lockedDistributeBalances;

    // uint256 public override totalLockedDistributeBalance;

    // mapping(address => mapping(address => uint256)) public override lockedRedeemBalances;
    // // token address -> total locked
    // mapping(address => uint256) public override totalLockedRedeemBalances;

    // uint256 public override totalRedeemedCurrency; // Total $ (cUSD) has been redeemed

    modifier orderAllowed() {
        Storage storage $ = _getStorage();
        require(
            $.redeemDisabled == false,
            "redeem-not-allowed"
        );
        _;
    }

    // Increase by value
    function increaseLockedDistributeBalance(
        address tokenAddress,
        address investor,
        uint256 currency,
        uint256 token
    ) external override whenNotPaused {
        registry().requireDistributionOperator(_msgSender());

        Storage storage $ = _getStorage();

        $.lockedDistributeBalances[tokenAddress][investor] =
            $.lockedDistributeBalances[tokenAddress][investor] +
            currency;
        $.lockedRedeemBalances[tokenAddress][investor] = $.lockedRedeemBalances[tokenAddress][investor] + token;

        $.totalLockedDistributeBalance = $.totalLockedDistributeBalance + currency;
        $.totalLockedRedeemBalances[tokenAddress] = $.totalLockedRedeemBalances[tokenAddress] + token;

        emit UpdateLockedDistributeBalance(
            tokenAddress,
            investor,
            $.lockedDistributeBalances[tokenAddress][investor],
            $.lockedRedeemBalances[tokenAddress][investor],
            $.totalLockedRedeemBalances[tokenAddress],
            $.totalLockedDistributeBalance
        );

        emit UpdateTotalRedeemedCurrency($.totalRedeemedCurrency, tokenAddress);
        emit UpdateTotalLockedDistributeBalance($.totalLockedDistributeBalance, tokenAddress);
    }

    function decreaseLockedDistributeBalance(
        address tokenAddress,
        address investor,
        uint256 currency,
        uint256 token
    ) external override whenNotPaused {
        registry().requireDistributionOperator(_msgSender());

        Storage storage $ = _getStorage();

        $.lockedDistributeBalances[tokenAddress][investor] =
            $.lockedDistributeBalances[tokenAddress][investor] -
            currency;
        $.lockedRedeemBalances[tokenAddress][investor] = $.lockedRedeemBalances[tokenAddress][investor] - token;

        $.totalLockedDistributeBalance = $.totalLockedDistributeBalance - currency;
        $.totalRedeemedCurrency = $.totalRedeemedCurrency + currency;
        $.totalLockedRedeemBalances[tokenAddress] = $.totalLockedRedeemBalances[tokenAddress] - token;

        emit UpdateLockedDistributeBalance(
            tokenAddress,
            investor,
            $.lockedDistributeBalances[tokenAddress][investor],
            $.lockedRedeemBalances[tokenAddress][investor],
            $.totalLockedRedeemBalances[tokenAddress],
            $.totalLockedDistributeBalance
        );

        emit UpdateTotalRedeemedCurrency($.totalRedeemedCurrency, tokenAddress);
        emit UpdateTotalLockedDistributeBalance($.totalLockedDistributeBalance, tokenAddress);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC165Upgradeable, SecuritizationAccessControl, SecuritizationPoolStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId) || type(ISecuritizationLockDistribution).interfaceId == interfaceId;
    }

    function pause() public virtual {
        registry().requirePoolAdminOrOwner(address(this), _msgSender());
        _pause();
    }

    function unpause() public virtual {
        registry().requirePoolAdminOrOwner(address(this), _msgSender());
        _unpause();
    }

    function setRedeemDisabled(bool _redeemDisabled) public {
        registry().requirePoolAdminOrOwner(address(this), _msgSender());
        Storage storage $ = _getStorage();
        $.redeemDisabled = _redeemDisabled;
    }
    function redeemSOTOrder(uint256 newRedeemAmount) public orderAllowed() {
        address usr = _msgSender();
        Storage storage $ = _getStorage();
        uint256 currentRedeemAmount = $.userRedeems[usr].redeemSOTAmount;
        $.userRedeems[usr].redeemSOTAmount = newRedeemAmount;
        $.totalSOTRedeem = $.totalSOTRedeem - currentRedeemAmount + newRedeemAmount;

        uint256 delta;
        if (newRedeemAmount > currentRedeemAmount) {
            delta = newRedeemAmount - currentRedeemAmount;
            require(INoteToken($.sotToken).transferFrom(usr, address(this), delta), "token-transfer-to-pool-failed");
            return;
        }

        delta = currentRedeemAmount - newRedeemAmount;
        if (delta > 0) {
            require(INoteToken($.sotToken).transfer(usr, delta), "token-transfer-out-failed");
        }
        emit RedeemSOTOrder(usr, newRedeemAmount);
    }

    function redeemJOTOrder(uint256 newRedeemAmount) public orderAllowed() {
        address usr = _msgSender();
        Storage storage $ = _getStorage();
        uint256 currentRedeemAmount = $.userRedeems[usr].redeemJOTAmount;
        $.userRedeems[usr].redeemJOTAmount = newRedeemAmount;
        $.totalJOTRedeem = $.totalJOTRedeem - currentRedeemAmount + newRedeemAmount;

        uint256 delta;
        if (newRedeemAmount > currentRedeemAmount) {
            delta = newRedeemAmount - currentRedeemAmount;
            require(INoteToken($.jotToken).transferFrom(usr, address(this), delta), "token-transfer-to-pool-failed");
            return;
        }

        delta = currentRedeemAmount - newRedeemAmount;
        if (delta > 0) {
            require(INoteToken($.jotToken).transfer(usr, delta), "token-transfer-out-failed");
        }

        emit RedeemJOTOrder(usr, newRedeemAmount);
    }

    function getFunctionSignatures()
        public
        view
        virtual
        override(ISecuritizationPoolExtension, SecuritizationAccessControl, SecuritizationPoolStorage)
        returns (bytes4[] memory)
    {
        bytes4[] memory _functionSignatures = new bytes4[](15);

        _functionSignatures[0] = this.totalRedeemedCurrency.selector;
        _functionSignatures[1] = this.lockedDistributeBalances.selector;
        _functionSignatures[2] = this.lockedRedeemBalances.selector;
        _functionSignatures[3] = this.totalLockedRedeemBalances.selector;
        _functionSignatures[4] = this.totalLockedDistributeBalance.selector;
        _functionSignatures[5] = this.increaseLockedDistributeBalance.selector;
        _functionSignatures[6] = this.decreaseLockedDistributeBalance.selector;
        _functionSignatures[7] = this.supportsInterface.selector;
        _functionSignatures[8] = this.redeemSOTOrder.selector;
        _functionSignatures[9] = this.redeemJOTOrder.selector;
        _functionSignatures[10] = this.setRedeemDisabled.selector;
        _functionSignatures[11] = this.totalJOTRedeem.selector;
        _functionSignatures[12] = this.totalSOTRedeem.selector;
        _functionSignatures[13] = this.userRedeemSOTOrder.selector;
        _functionSignatures[14] = this.userRedeemJOTOrder.selector;

        return _functionSignatures;
    }
}
