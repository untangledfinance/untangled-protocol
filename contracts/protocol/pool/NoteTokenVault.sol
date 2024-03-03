// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import {ECDSAUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol';
import {UntangledMath} from '../../libraries/UntangledMath.sol';
import {INoteTokenVault} from '../../interfaces/INoteTokenVault.sol';
import {INoteToken} from '../../interfaces/INoteToken.sol';
import {IMintedNormalTGE} from '../../interfaces/IMintedNormalTGE.sol';
import {BACKEND_ADMIN_ROLE, SIGNER_ROLE} from '../../libraries/DataTypes.sol';
import {IPool} from '../../interfaces/IPool.sol';
import {Configuration} from '../../libraries/Configuration.sol';
import '../../storage/Registry.sol';
import '../../libraries/ConfigHelper.sol';

/// @title NoteTokenVault
/// @author Untangled Team
/// @notice NoteToken redemption
contract NoteTokenVault is
    Initializable,
    PausableUpgradeable,
    AccessControlEnumerableUpgradeable,
    ReentrancyGuardUpgradeable,
    INoteTokenVault
{
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
        require(!poolRedeemDisabled[pool], 'redeem-not-allowed');
        _;
    }

    function _incrementNonce(address account) internal {
        nonces[account] += 1;
    }

    function initialize(Registry _registry) public initializer {
        __Pausable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __AccessControlEnumerable_init_unchained();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        registry = _registry;
    }

    function hasAllowedUID(address sender) public view returns (bool) {
        return registry.getSecuritizationManager().hasAllowedUID(sender);
    }

    function _validateRedeemParam(RedeemOrderParam calldata redeemParam, bytes calldata signature) internal view {
        address usr = _msgSender();
        bytes32 hash = keccak256(
            abi.encodePacked(
                usr,
                redeemParam.pool,
                redeemParam.noteTokenAddress,
                redeemParam.noteTokenRedeemAmount,
                block.chainid
            )
        );
        bytes32 ethSignedMessage = ECDSAUpgradeable.toEthSignedMessageHash(hash);
        require(hasRole(SIGNER_ROLE, ECDSAUpgradeable.recover(ethSignedMessage, signature)), 'Invalid signer');
    }

    /// @inheritdoc INoteTokenVault
    function redeemOrder(
        RedeemOrderParam calldata redeemParam,
        bytes calldata signature
    ) public orderAllowed(redeemParam.pool) nonReentrant {
        _validateRedeemParam(redeemParam, signature);

        address pool = redeemParam.pool;
        address noteTokenAddress = redeemParam.noteTokenAddress;
        uint256 noteTokenRedeemAmount = redeemParam.noteTokenRedeemAmount;

        address jotTokenAddress = IPool(pool).jotToken();
        address sotTokenAddress = IPool(pool).sotToken();
        require(
            _isJotToken(noteTokenAddress, jotTokenAddress) || _isSotToken(noteTokenAddress, sotTokenAddress),
            'NoteTokenVault: Invalid token address'
        );
        address usr = _msgSender();
        require(hasAllowedUID(usr), 'Unauthorized. Must have correct UID');

        uint256 noteTokenPrice;
        if (_isJotToken(noteTokenAddress, jotTokenAddress)) {
            uint256 currentRedeemAmount = poolUserRedeems[pool][usr].redeemJOTAmount;
            require(currentRedeemAmount == 0, 'NoteTokenVault: User already created redeem order');
            poolUserRedeems[pool][usr].redeemJOTAmount = noteTokenRedeemAmount;
            poolTotalJOTRedeem[pool] = poolTotalJOTRedeem[pool] + noteTokenRedeemAmount;
            noteTokenPrice = registry.getSecuritizationPoolValueService().getJOTTokenPrice(pool);
        } else {
            uint256 currentRedeemAmount = poolUserRedeems[pool][usr].redeemSOTAmount;
            require(currentRedeemAmount == 0, 'NoteTokenVault: User already created redeem order');
            poolUserRedeems[pool][usr].redeemSOTAmount = noteTokenRedeemAmount;
            poolTotalSOTRedeem[pool] = poolTotalSOTRedeem[pool] + noteTokenRedeemAmount;
            noteTokenPrice = registry.getSecuritizationPoolValueService().getSOTTokenPrice(pool);
        }

        require(
            INoteToken(noteTokenAddress).transferFrom(usr, address(this), noteTokenRedeemAmount),
            'token-transfer-to-pool-failed'
        );
        emit RedeemOrder(pool, noteTokenAddress, usr, noteTokenRedeemAmount, noteTokenPrice);
    }

    function preDistribute(
        address poolAddress,
        uint256 totalCurrencyAmount,
        address[] calldata noteTokenAddresses,
        uint256[] calldata totalRedeemedNoteAmounts
    ) public onlyRole(BACKEND_ADMIN_ROLE) nonReentrant {
        IPool pool = IPool(poolAddress);

        (, uint256 sotTokenPrice) = pool.calcTokenPrices();
        uint256 totalSotRedeem;
        uint256 decimals;

        for (uint i = 0; i < noteTokenAddresses.length; i++) {
            INoteToken(noteTokenAddresses[i]).burn(totalRedeemedNoteAmounts[i]);
            if (INoteToken(noteTokenAddresses[i]).noteTokenType() == uint8(Configuration.NOTE_TOKEN_TYPE.SENIOR)) {
                totalSotRedeem += totalRedeemedNoteAmounts[i];
                decimals = INoteToken(noteTokenAddresses[i]).decimals();
            }
        }
        pool.decreaseReserve(totalCurrencyAmount);
        // rebase
        if (totalSotRedeem > 0) {
            pool.changeSeniorAsset(0, (sotTokenPrice * totalSotRedeem) / 10 ** decimals);
        }
        require(pool.isMinFirstLossValid(), 'NoteTokenVault: Exceeds MinFirstLoss');

        emit PreDistribute(poolAddress, totalCurrencyAmount, noteTokenAddresses, totalRedeemedNoteAmounts);
    }

    /// @inheritdoc INoteTokenVault
    function disburseAll(
        address pool,
        address noteTokenAddress,
        address[] memory toAddresses,
        uint256[] memory currencyAmounts,
        uint256[] memory redeemedNoteAmounts
    ) public onlyRole(BACKEND_ADMIN_ROLE) nonReentrant {
        IPool poolTGE = IPool(pool);
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

            // Update pot pool reserve in P2P investment
            address poolOfPot = registry.getSecuritizationManager().potToPool(toAddresses[i]);
            if (poolOfPot != address(0)) {
                IPool(poolOfPot).increaseReserve(currencyAmounts[i]);
            }
        }

        if (_isJotToken(noteTokenAddress, jotTokenAddress)) {
            poolTotalJOTRedeem[pool] -= totalNoteRedeemed;
            IMintedNormalTGE(IPool(pool).secondTGEAddress()).onRedeem(totalCurrencyAmount);
        } else {
            poolTotalSOTRedeem[pool] -= totalNoteRedeemed;
            IMintedNormalTGE(IPool(pool).tgeAddress()).onRedeem(totalCurrencyAmount);
        }

        emit DisburseOrder(pool, noteTokenAddress, toAddresses, currencyAmounts, redeemedNoteAmounts);
    }

    function _validateCancelParam(CancelOrderParam calldata cancelParam, bytes calldata signature) internal view {
        require(block.timestamp <= cancelParam.maxTimestamp, 'Cancel request has expired');
        address usr = _msgSender();
        bytes32 hash = keccak256(
            abi.encodePacked(
                usr,
                cancelParam.pool,
                cancelParam.noteTokenAddress,
                cancelParam.maxTimestamp,
                nonces[usr],
                block.chainid
            )
        );
        bytes32 ethSignedMessage = ECDSAUpgradeable.toEthSignedMessageHash(hash);
        require(hasRole(SIGNER_ROLE, ECDSAUpgradeable.recover(ethSignedMessage, signature)), 'Invalid signer');
    }

    function cancelOrder(CancelOrderParam calldata cancelParam, bytes calldata signature) public nonReentrant {
        address usr = _msgSender();

        _validateCancelParam(cancelParam, signature);
        _incrementNonce(usr);

        address pool = cancelParam.pool;
        address jotTokenAddress = IPool(pool).jotToken();
        address sotTokenAddress = IPool(pool).sotToken();
        address noteTokenAddress = cancelParam.noteTokenAddress;

        require(
            _isJotToken(noteTokenAddress, jotTokenAddress) || _isSotToken(noteTokenAddress, sotTokenAddress),
            'NoteTokenVault: Invalid token address'
        );

        uint256 currentRedeemAmount;

        if (_isJotToken(noteTokenAddress, jotTokenAddress)) {
            currentRedeemAmount = poolUserRedeems[pool][usr].redeemJOTAmount;
            poolUserRedeems[pool][usr].redeemJOTAmount = 0;
            poolTotalJOTRedeem[pool] = poolTotalJOTRedeem[pool] - currentRedeemAmount;
        } else {
            currentRedeemAmount = poolUserRedeems[pool][usr].redeemSOTAmount;
            poolUserRedeems[pool][usr].redeemSOTAmount = 0;
            poolTotalSOTRedeem[pool] = poolTotalSOTRedeem[pool] - currentRedeemAmount;
        }

        require(currentRedeemAmount > 0, 'NoteTokenVault: Redeem order not found');
        require(INoteToken(noteTokenAddress).transfer(usr, currentRedeemAmount), 'token-transfer-from-pool-failed');

        emit CancelOrder(pool, noteTokenAddress, usr, currentRedeemAmount);
    }

    /// @inheritdoc INoteTokenVault
    function setRedeemDisabled(address pool, bool _redeemDisabled) public onlyRole(BACKEND_ADMIN_ROLE) {
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
}
