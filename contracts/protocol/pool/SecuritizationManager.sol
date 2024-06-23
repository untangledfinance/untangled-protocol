// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IAccessControlUpgradeable} from '@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {UntangledBase} from '../../base/UntangledBase.sol';
import {IRequiresUID} from '../../interfaces/IRequiresUID.sol';
import {Factory2} from '../../base/Factory2.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {ISecuritizationManager} from '../../interfaces/ISecuritizationManager.sol';
import {IPool} from '../../interfaces/IPool.sol';
import {INoteTokenFactory} from '../../interfaces/INoteTokenFactory.sol';
import {INoteTokenManager} from '../../interfaces/INoteTokenManager.sol';
import {Registry} from '../../storage/Registry.sol';
import {Configuration} from '../../libraries/Configuration.sol';
import {POOL_ADMIN_ROLE, OWNER_ROLE} from '../../libraries/DataTypes.sol';
import {DataTypes} from '../../libraries/DataTypes.sol';

import 'hardhat/console.sol';

abstract contract SecuritizationManagerBase is ISecuritizationManager {
    Registry public override registry;

    mapping(address => bool) public override isExistingPools;
    address[] public override pools;

    mapping(address => address) public override potToPool;

    mapping(address => bool) public override isExistingTGEs;

    uint256[45] private __gap;
}

/// @title SecuritizationManager
/// @author Untangled Team
/// @notice You can use this contract for creating new pool, setting up note toke sale, buying note token
contract SecuritizationManager is UntangledBase, Factory2, SecuritizationManagerBase, IRequiresUID {
    using ConfigHelper for Registry;
    event NewTokenCreated(address pool, address tokenAddress, string tokenType);

    bytes4 public constant POOL_INIT_FUNC_SELECTOR = bytes4(keccak256('initialize(address,bytes)'));

    uint256[] public allowedUIDTypes;

    function initialize(Registry _registry, address _factoryAdmin) public initializer {
        __UntangledBase__init(_msgSender());
        __Factory__init(_factoryAdmin);
        _setRoleAdmin(POOL_ADMIN_ROLE, OWNER_ROLE);

        registry = _registry;
    }

    modifier onlyPoolExisted(address pool) {
        require(isExistingPools[pool], 'SecuritizationManager: Pool does not exist');
        _;
    }

    modifier onlyIssuer(address pool) {
        require(
            IAccessControlUpgradeable(pool).hasRole(OWNER_ROLE, _msgSender()),
            'SecuritizationManager: Not the controller of the project'
        );
        _;
    }

    modifier doesSOTExist(address pool) {
        require(IPool(pool).sotToken() == address(0), 'SecuritizationManager: Already exists SOT token');
        _;
    }

    modifier doesJOTExist(address pool) {
        require(IPool(pool).jotToken() == address(0), 'SecuritizationManager: Already exists JOT token');
        _;
    }

    function setFactoryAdmin(address _factoryAdmin) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setFactoryAdmin(_factoryAdmin);
    }

    function getPoolsLength() public view returns (uint256) {
        return pools.length;
    }

    /// @notice Creates a new securitization pool
    /// @param params params data of the securitization pool
    /// @dev Creates a new instance of a securitization pool. Set msg sender as owner of the new pool
    function newPoolInstance(
        bytes32 salt,
        address poolOwner,
        bytes memory params
    ) external whenNotPaused onlyRole(POOL_ADMIN_ROLE) returns (address) {
        address poolImplAddress = address(registry.getSecuritizationPool());

        bytes memory _initialData = abi.encodeWithSelector(POOL_INIT_FUNC_SELECTOR, registry, params);

        address poolAddress = _deployInstance(poolImplAddress, _initialData, salt);

        IAccessControlUpgradeable poolInstance = IAccessControlUpgradeable(poolAddress);

        isExistingPools[poolAddress] = true;
        pools.push(poolAddress);

        poolInstance.grantRole(OWNER_ROLE, poolOwner);
        poolInstance.grantRole(POOL_ADMIN_ROLE, _msgSender());
        poolInstance.renounceRole(DEFAULT_ADMIN_ROLE, address(this));

        emit NewPoolCreated(poolAddress);
        emit NewPoolDeployed(poolAddress, poolOwner, abi.decode(params, (DataTypes.NewPoolParams)));

        return poolAddress;
    }

    //setup note token sale
    function setupNoteTokenSale(
        address pool,
        Configuration.NOTE_TOKEN_TYPE tokenType,
        uint256 minBidAmount,
        uint32 interestRate,
        string calldata ticker
    ) external whenNotPaused onlyIssuer(pool) {
        INoteTokenFactory tokenFactory = registry.getNoteTokenFactory();
        require(address(tokenFactory) != address(0), 'SecuritizationManager: Note Token Factory was not registered');

        address currency = IPool(pool).underlyingCurrency();
        address tokenAddress = tokenFactory.createToken(pool, tokenType, ERC20(currency).decimals(), ticker);
        require(tokenAddress != address(0), 'SecuritizationManager: token must be created');

        if (tokenType == Configuration.NOTE_TOKEN_TYPE.SENIOR) {
            INoteTokenManager sotManager = registry.getSeniorTokenManager();
            sotManager.setupNewToken(pool, tokenAddress, minBidAmount);
            IPool(pool).setInterestRateSOT(interestRate);

            // tokenFactory.changeMinterRole(tokenAddress, address(sotManager));
            emit NewTokenCreated(pool, tokenAddress, 'SENIOR');
        }

        if (tokenType == Configuration.NOTE_TOKEN_TYPE.JUNIOR) {
            INoteTokenManager jotManager = registry.getJuniorTokenManager();
            jotManager.setupNewToken(pool, tokenAddress, minBidAmount);

            // tokenFactory.changeMinterRole(tokenAddress, address(jotManager));
            emit NewTokenCreated(pool, tokenAddress, 'JUNIOR');
        }
    }

    /// @inheritdoc ISecuritizationManager
    function registerPot(address pot) external override whenNotPaused {
        require(isExistingPools[_msgSender()], 'SecuritizationManager: Only SecuritizationPool');
        require(potToPool[pot] == address(0), 'SecuritizationManager: pot used for another pool');
        potToPool[pot] = _msgSender();

        emit UpdatePotToPool(pot, _msgSender());
    }

    function setAllowedUIDTypes(uint256[] calldata ids) external onlyRole(DEFAULT_ADMIN_ROLE) {
        allowedUIDTypes = ids;
        emit UpdateAllowedUIDTypes(ids);
    }

    /// @notice Check if an user has valid UID type
    function hasAllowedUID(address sender) public view override(IRequiresUID, ISecuritizationManager) returns (bool) {
        return registry.getGo().goOnlyIdTypes(sender, allowedUIDTypes);
    }
}
