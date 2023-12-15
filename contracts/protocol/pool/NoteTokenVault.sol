// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import {ECDSAUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol';
import {ERC20BurnableUpgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
import {IERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol';

import {UntangledMath} from '../../libraries/UntangledMath.sol';
import {INoteTokenVault} from './INoteTokenVault.sol';
import {INoteToken} from '../../interfaces/INoteToken.sol';
import {ISecuritizationTGE} from './ISecuritizationTGE.sol';
import {BACKEND_ADMIN, SIGNER_ROLE} from './types.sol';
import '../../storage/Registry.sol';
import '../../libraries/ConfigHelper.sol';

/// @title NoteTokenVault
/// @author Untangled Team
/// @notice NoteToken redemption
contract NoteTokenVault is Initializable, PausableUpgradeable, AccessControlEnumerableUpgradeable, ReentrancyGuardUpgradeable, INoteTokenVault {
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
    
    /// @dev We include a nonce in every hashed message, and increment the nonce as part of a
    /// state-changing operation, so as to prevent replay attacks, i.e. the reuse of a signature.
    mapping(address => uint256) public nonces;


    /// @dev Checks if redeeming is allowed for a given pool.
    /// @param pool The address of the pool to check.
    modifier orderAllowed(address pool) {
        require(poolRedeemDisabled[pool] == false, 'redeem-not-allowed');
        _;
    }

    modifier incrementNonce(address account) {
        nonces[account] += 1;
        _;
    }

    modifier onlySigner(
        CancelOrderParam memory cancelParam,
        bytes calldata signature
    ) {
        require(block.timestamp <= cancelParam.maxTimestamp, 'Cancel request has expired');
        address usr = _msgSender();
        bytes32 hash = keccak256(
            abi.encodePacked(usr, cancelParam.pool, cancelParam.noteTokenAddress, cancelParam.maxTimestamp, nonces[usr], block.chainid)
        );
        bytes32 ethSignedMessage = ECDSAUpgradeable.toEthSignedMessageHash(hash);
        require(hasRole(SIGNER_ROLE, ECDSAUpgradeable.recover(ethSignedMessage, signature)), 'Invalid signer');
        _;
    }

    function initialize(Registry _registry) public initializer {
        __Pausable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __AccessControlEnumerable_init_unchained();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        registry = _registry;
    }

    /// @inheritdoc INoteTokenVault
    function redeemOrder(
        address pool,
        address noteTokenAddress,
        uint256 noteTokenRedeemAmount
    ) public orderAllowed(pool) {
        address jotTokenAddress = ISecuritizationTGE(pool).jotToken();
        address sotTokenAddress = ISecuritizationTGE(pool).sotToken();
        require(
            _isJotToken(noteTokenAddress, jotTokenAddress) || _isSotToken(noteTokenAddress, sotTokenAddress),
            'NoteTokenVault: Invalid token address'
        );
        address usr = _msgSender();

        uint256 noteTokenPrice;
        if (_isJotToken(noteTokenAddress, jotTokenAddress)) {
            uint256 currentRedeemAmount = poolUserRedeems[pool][usr].redeemJOTAmount;
            require(currentRedeemAmount == 0, 'NoteTokenVault: User already created redeem order');
            poolUserRedeems[pool][usr].redeemJOTAmount = noteTokenRedeemAmount;
            poolTotalJOTRedeem[pool] = poolTotalJOTRedeem[pool] + noteTokenRedeemAmount;
            noteTokenPrice = registry.getDistributionAssessor().getJOTTokenPrice(pool);
        } else {
            uint256 currentRedeemAmount = poolUserRedeems[pool][usr].redeemSOTAmount;
            require(currentRedeemAmount == 0, 'NoteTokenVault: User already created redeem order');
            poolUserRedeems[pool][usr].redeemSOTAmount = noteTokenRedeemAmount;
            poolTotalSOTRedeem[pool] = poolTotalSOTRedeem[pool] + noteTokenRedeemAmount;
            noteTokenPrice = registry.getDistributionAssessor().getJOTTokenPrice(pool);
        }

        require(
            INoteToken(noteTokenAddress).transferFrom(usr, address(this), noteTokenRedeemAmount),
            'token-transfer-to-pool-failed'
        );
        emit RedeemOrder(pool, noteTokenAddress, usr, noteTokenRedeemAmount, noteTokenPrice);
    }

    /// @inheritdoc INoteTokenVault
    function disburseAll(
        address pool,
        address noteTokenAddress,
        address[] memory toAddresses,
        uint256[] memory currencyAmounts,
        uint256[] memory redeemedNoteAmounts
    ) public onlyRole(BACKEND_ADMIN) nonReentrant {
        ISecuritizationTGE poolTGE = ISecuritizationTGE(pool);
        address jotTokenAddress = poolTGE.jotToken();
        address sotTokenAddress = poolTGE.sotToken();
        require(
            _isJotToken(noteTokenAddress, jotTokenAddress) || _isSotToken(noteTokenAddress, sotTokenAddress),
            'NoteTokenVault: Invalid token address'
        );

        uint256 totalCurrencyAmount = 0;
        uint256 userLength = toAddresses.length;

        uint256 totalNoteRedeemed = 0;
        for (uint256 i = 0; i < userLength; i = UntangledMath.uncheckedInc(i)) {
            totalCurrencyAmount += currencyAmounts[i];
            totalNoteRedeemed += redeemedNoteAmounts[i];
            poolTGE.disburse(toAddresses[i], currencyAmounts[i]);

            if (_isJotToken(noteTokenAddress, jotTokenAddress)) {
                poolUserRedeems[pool][toAddresses[i]].redeemJOTAmount -= redeemedNoteAmounts[i];
            } else {
                poolUserRedeems[pool][toAddresses[i]].redeemSOTAmount -= redeemedNoteAmounts[i];
            }

            ERC20BurnableUpgradeable(noteTokenAddress).burn(redeemedNoteAmounts[i]);
        }

        if (_isJotToken(noteTokenAddress, jotTokenAddress)) {
            poolTotalJOTRedeem[pool] -= totalNoteRedeemed;
        } else {
            poolTotalSOTRedeem[pool] -= totalNoteRedeemed;
        }

        poolTGE.decreaseReserve(totalCurrencyAmount);
        emit DisburseOrder(pool, noteTokenAddress, toAddresses, currencyAmounts, redeemedNoteAmounts);
    }

    function cancelOrder(CancelOrderParam memory cancelParam, bytes calldata signature) public onlySigner(cancelParam, signature) incrementNonce(_msgSender()) {
        address pool = cancelParam.pool;
        address jotTokenAddress = ISecuritizationTGE(pool).jotToken();
        address sotTokenAddress = ISecuritizationTGE(pool).sotToken();
        address noteTokenAddress = cancelParam.noteTokenAddress;
        address usr = _msgSender();

        require(
            _isJotToken(noteTokenAddress, jotTokenAddress) || _isSotToken(noteTokenAddress, sotTokenAddress),
            'NoteTokenVault: Invalid token address'
        );

        if (_isJotToken(noteTokenAddress, jotTokenAddress)) {
            uint256 currentRedeemAmount = poolUserRedeems[pool][usr].redeemJOTAmount;
            require(currentRedeemAmount > 0, 'NoteTokenVault: Redeem order not found');
            poolUserRedeems[pool][usr].redeemJOTAmount = 0;
            poolTotalJOTRedeem[pool] = poolTotalJOTRedeem[pool] - currentRedeemAmount;
            require(
                INoteToken(noteTokenAddress).transfer(usr, currentRedeemAmount),
                'token-transfer-from-pool-failed'
            );
            emit CancelOrder(pool, noteTokenAddress, usr, currentRedeemAmount);
        } else {
            uint256 currentRedeemAmount = poolUserRedeems[pool][usr].redeemSOTAmount;
            require(currentRedeemAmount > 0, 'NoteTokenVault: Redeem order not found');
            poolUserRedeems[pool][usr].redeemSOTAmount = 0;
            poolTotalSOTRedeem[pool] = poolTotalSOTRedeem[pool] - currentRedeemAmount;
            require(
                INoteToken(noteTokenAddress).transfer(usr, currentRedeemAmount),
                'token-transfer-from-pool-failed'
            );
            emit CancelOrder(pool, noteTokenAddress, usr, currentRedeemAmount);
        }
    }

    /// @inheritdoc INoteTokenVault
    function setRedeemDisabled(address pool, bool _redeemDisabled) public onlyRole(BACKEND_ADMIN) {
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

    function _isJotToken(address noteToken, address jotToken) internal pure returns (bool) {
        return noteToken == jotToken;
    }

    function _isSotToken(address noteToken, address sotToken) internal pure returns (bool) {
        return noteToken == sotToken;
    }

    uint256[49] private __gap;
}
