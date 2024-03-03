// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IAccessControlUpgradeable} from '@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol';

import {UntangledBase} from '../../base/UntangledBase.sol';
import {IRequiresUID} from '../../interfaces/IRequiresUID.sol';
import {INoteToken} from '../../interfaces/INoteToken.sol';
import {Factory2} from '../../base/Factory2.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {INoteTokenFactory} from '../../interfaces/INoteTokenFactory.sol';
import {ISecuritizationManager} from '../../interfaces/ISecuritizationManager.sol';
import {IPool} from '../../interfaces/IPool.sol';
import {Registry} from '../../storage/Registry.sol';
import {Configuration} from '../../libraries/Configuration.sol';
import {POOL_ADMIN_ROLE, VALIDATOR_ROLE, OWNER_ROLE} from '../../libraries/DataTypes.sol';
import {IMintedNormalTGE} from '../../interfaces/IMintedNormalTGE.sol';
import {TokenGenerationEventFactory} from '../note-sale/fab/TokenGenerationEventFactory.sol';
import {DataTypes} from '../../libraries/DataTypes.sol';

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

        IPool poolInstance = IPool(poolAddress);

        isExistingPools[poolAddress] = true;
        pools.push(poolAddress);

        poolInstance.grantRole(OWNER_ROLE, poolOwner);
        poolInstance.grantRole(POOL_ADMIN_ROLE, _msgSender());
        poolInstance.renounceRole(DEFAULT_ADMIN_ROLE, address(this));

        emit NewPoolCreated(poolAddress);
        emit NewPoolDeployed(poolAddress, poolOwner, abi.decode(params, (DataTypes.NewPoolParams)));

        return poolAddress;
    }

    /// @inheritdoc ISecuritizationManager
    function registerPot(address pot) external override whenNotPaused {
        require(isExistingPools[_msgSender()], 'SecuritizationManager: Only SecuritizationPool');
        require(potToPool[pot] == address(0), 'SecuritizationManager: pot used for another pool');
        potToPool[pot] = _msgSender();

        emit UpdatePotToPool(pot, _msgSender());
    }

    function _initialTGEForSOT(
        address issuerTokenController,
        address pool,
        uint8 saleType,
        string memory ticker,
        uint256 openingTime
    ) internal whenNotPaused nonReentrant onlyPoolExisted(pool) doesSOTExist(pool) returns (address, address) {
        INoteTokenFactory noteTokenFactory = registry.getNoteTokenFactory();
        require(address(noteTokenFactory) != address(0), 'Note Token Factory was not registered');
        require(address(registry.getTokenGenerationEventFactory()) != address(0), 'TGE Factory was not registered');

        address underlyingCurrency = IPool(pool).underlyingCurrency();
        address sotToken = noteTokenFactory.createToken(
            pool,
            Configuration.NOTE_TOKEN_TYPE.SENIOR,
            INoteToken(underlyingCurrency).decimals(),
            ticker
        );
        require(sotToken != address(0), 'SOT token must be created');

        address tgeAddress = registry.getTokenGenerationEventFactory().createNewSaleInstance(
            issuerTokenController,
            sotToken,
            underlyingCurrency,
            saleType,
            openingTime
        );
        noteTokenFactory.changeMinterRole(sotToken, tgeAddress);

        IPool(pool).injectTGEAddress(tgeAddress, uint8(Configuration.NOTE_TOKEN_TYPE.SENIOR));

        isExistingTGEs[tgeAddress] = true;

        emit SotDeployed(sotToken, tgeAddress, address(pool));
        return (sotToken, tgeAddress);
    }

    /// @notice Sets up the token generation event (TGE) for the senior tranche (SOT) of a securitization pool with additional configuration parameters
    /// @param tgeParam Parameters for TGE
    /// @param interestRate Interest rate of the token
    function setUpTGEForSOT(TGEParam memory tgeParam, uint32 interestRate) public onlyIssuer(tgeParam.pool) {
        (address sotToken, address tgeAddress) = _initialTGEForSOT(
            tgeParam.issuerTokenController,
            tgeParam.pool,
            tgeParam.saleType,
            tgeParam.ticker,
            tgeParam.openingTime
        );
        IMintedNormalTGE tge = IMintedNormalTGE(tgeAddress);
        IPool pool = IPool(tgeParam.pool);
        pool.setInterestRateSOT(interestRate);
        tge.setTotalCap(tgeParam.totalCap);
        tge.setMinBidAmount(tgeParam.minBidAmount);

        emit SetupSot(sotToken, tgeAddress, tgeParam, interestRate);
    }

    /// @notice sets up the token generation event (TGE) for the junior tranche (JOT) of a securitization pool with additional configuration parameters
    /// @param tgeParam Parameters for TGE
    /// @param initialJOTAmount Minimum amount of JOT raised in currency before SOT can start
    function setUpTGEForJOT(TGEParam memory tgeParam, uint256 initialJOTAmount) public onlyIssuer(tgeParam.pool) {
        (address jotToken, address tgeAddress) = _initialTGEForJOT(
            tgeParam.issuerTokenController,
            tgeParam.pool,
            tgeParam.saleType,
            tgeParam.ticker,
            tgeParam.openingTime
        );
        IMintedNormalTGE tge = IMintedNormalTGE(tgeAddress);
        tge.setTotalCap(tgeParam.totalCap);
        tge.setHasStarted(true);
        tge.setMinBidAmount(tgeParam.minBidAmount);
        tge.setInitialAmount(initialJOTAmount);

        emit SetupJot(jotToken, tgeAddress, tgeParam, initialJOTAmount);
    }

    function _initialTGEForJOT(
        address issuerTokenController,
        address pool,
        uint8 saleType,
        string memory ticker,
        uint256 openingTime
    ) public whenNotPaused nonReentrant onlyPoolExisted(pool) doesJOTExist(pool) returns (address, address) {
        INoteTokenFactory noteTokenFactory = registry.getNoteTokenFactory();
        address underlyingCurrency = IPool(pool).underlyingCurrency();
        address jotToken = noteTokenFactory.createToken(
            address(pool),
            Configuration.NOTE_TOKEN_TYPE.JUNIOR,
            INoteToken(underlyingCurrency).decimals(),
            ticker
        );

        address tgeAddress = registry.getTokenGenerationEventFactory().createNewSaleInstance(
            issuerTokenController,
            jotToken,
            underlyingCurrency,
            saleType,
            openingTime
        );
        noteTokenFactory.changeMinterRole(jotToken, tgeAddress);

        IPool(pool).injectTGEAddress(tgeAddress, uint8(Configuration.NOTE_TOKEN_TYPE.JUNIOR));

        isExistingTGEs[tgeAddress] = true;

        emit JotDeployed(jotToken, tgeAddress, address(pool));
        return (jotToken, tgeAddress);
    }

    /// @notice Investor bid for SOT or JOT token
    /// @param tgeAddress SOT/JOT token sale instance
    /// @param currencyAmount Currency amount investor will pay
    function buyTokens(address tgeAddress, uint256 currencyAmount) external whenNotPaused nonReentrant {
        require(isExistingTGEs[tgeAddress], 'SMP: Note sale does not exist');
        require(hasAllowedUID(_msgSender()), 'Unauthorized. Must have correct UID');

        IMintedNormalTGE tge = IMintedNormalTGE(tgeAddress);
        address poolOfPot = potToPool[_msgSender()];
        uint256 tokenAmount = tge.buyTokens(
            _msgSender(),
            poolOfPot == address(0) ? _msgSender() : poolOfPot,
            currencyAmount
        );
        address pool = tge.pool();
        require(!registry.getNoteTokenVault().redeemDisabled(pool), 'SM: Buy token paused');

        address noteToken = tge.token();
        uint8 noteTokenType = INoteToken(noteToken).noteTokenType();
        if (noteTokenType == uint8(Configuration.NOTE_TOKEN_TYPE.JUNIOR)) {
            if (IMintedNormalTGE(tgeAddress).currencyRaised() >= IMintedNormalTGE(tgeAddress).initialAmount()) {
                // Currency Raised For JOT > initialJOTAmount => SOT sale start
                address sotTGEAddress = IPool(pool).tgeAddress();
                if (sotTGEAddress != address(0)) {
                    IMintedNormalTGE(sotTGEAddress).setHasStarted(true);
                }
            }
        }

        IPool(pool).increaseReserve(currencyAmount);

        if (poolOfPot != address(0)) {
            IPool(poolOfPot).collectERC20Asset(noteToken);
            IPool(poolOfPot).decreaseReserve(currencyAmount);
        }

        // rebase
        if (noteTokenType == uint8(Configuration.NOTE_TOKEN_TYPE.JUNIOR)) {
            IPool(pool).changeSeniorAsset(0, 0);
        } else {
            IPool(pool).changeSeniorAsset(currencyAmount, 0);
        }

        emit NoteTokenPurchased(_msgSender(), tgeAddress, address(pool), currencyAmount, tokenAmount);
    }

    function setAllowedUIDTypes(uint256[] calldata ids) external onlyRole(DEFAULT_ADMIN_ROLE) {
        allowedUIDTypes = ids;
        emit UpdateAllowedUIDTypes(ids);
    }

    /// @notice Check if an user has valid UID type
    function hasAllowedUID(address sender) public view override(IRequiresUID, ISecuritizationManager) returns (bool) {
        return registry.getGo().goOnlyIdTypes(sender, allowedUIDTypes);
    }

    function updateTgeInfo(TGEInfoParam[] calldata tgeInfos) public {
        for (uint i = 0; i < tgeInfos.length; i++) {
            require(
                IAccessControlUpgradeable(IMintedNormalTGE(tgeInfos[i].tgeAddress).pool()).hasRole(
                    OWNER_ROLE,
                    _msgSender()
                ),
                'SecuritizationManager: Not the controller of the project'
            );
            IMintedNormalTGE(tgeInfos[i].tgeAddress).setTotalCap(tgeInfos[i].totalCap);
            IMintedNormalTGE(tgeInfos[i].tgeAddress).setMinBidAmount(tgeInfos[i].minBidAmount);
        }

        emit UpdateTGEInfo(tgeInfos);
    }
}
