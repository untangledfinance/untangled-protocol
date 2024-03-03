// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol';
import '../libraries/Configuration.sol';

/**
 * @title Untangled's SecuritizationPool contract
 * @notice Abstract contract that serves as a base contract for other contracts in the Untangled system.
 *  It provides functionalities for contract initialization, pausing, and access control.
 * @author Untangled Team
 */
abstract contract UntangledBase is
    Initializable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    AccessControlEnumerableUpgradeable
{
    bytes32 public constant OWNER_ROLE = keccak256('OWNER_ROLE');
    bytes32 public constant ORIGINATOR_ROLE = keccak256('ORIGINATOR_ROLE');
    bytes32 public constant POOL_ADMIN_ROLE = keccak256('POOL_CREATOR');
    bytes32 public constant BACKEND_ADMIN = keccak256('BACKEND_ADMIN');
    bytes32 public constant SIGNER_ROLE = keccak256('SIGNER_ROLE');
    bytes32 public constant SUPER_ADMIN = keccak256('SUPER_ADMIN');

    function isAdmin() public view virtual returns (bool) {
        return hasRole(OWNER_ROLE, _msgSender()) || hasRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    modifier onlyAdmin() {
        require(isAdmin(), 'UntangledBase: Must have admin role to perform this action');
        _;
    }

    function __UntangledBase__init(address owner) internal onlyInitializing {
        __Pausable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __AccessControlEnumerable_init_unchained();
        __UntangledBase__init_unchained(owner);
    }

    function __UntangledBase__init_unchained(address owner) internal onlyInitializing {
        if (owner == address(0)) owner = _msgSender();

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OWNER_ROLE, owner);

        _setRoleAdmin(ORIGINATOR_ROLE, OWNER_ROLE);
    }

    function getInitializedVersion() public view virtual returns (uint256) {
        return _getInitializedVersion();
    }

    function pause() public virtual onlyAdmin {
        _pause();
    }

    function unpause() public virtual onlyAdmin {
        _unpause();
    }

    function setRoleAdmin(bytes32 role, bytes32 adminRole) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setRoleAdmin(role, adminRole);
    }

    uint256[50] private __gap;
}
