// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IAccessControlUpgradeable} from '@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol';

import {UntangledBase} from '../../base/UntangledBase.sol';

import {IRequiresUID} from '../../interfaces/IRequiresUID.sol';
import {INoteToken} from '../../interfaces/INoteToken.sol';

import {Factory2} from '../../base/Factory2.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {INoteTokenFactory} from '../note-sale/fab/INoteTokenFactory.sol';
import {ISecuritizationManager} from './ISecuritizationManager.sol';
import {ISecuritizationPool} from './ISecuritizationPool.sol';
import {ICrowdSale} from '../note-sale/crowdsale/ICrowdSale.sol';
import {Registry} from '../../storage/Registry.sol';
import {Configuration} from '../../libraries/Configuration.sol';
import {POOL_ADMIN} from './types.sol';
import {VALIDATOR_ROLE} from '../../tokens/ERC721/types.sol';
import {MintedNormalTGE} from '../note-sale/MintedNormalTGE.sol';
import {MintedIncreasingInterestTGE} from '../note-sale/MintedIncreasingInterestTGE.sol';
import {TokenGenerationEventFactory} from '../note-sale/fab/TokenGenerationEventFactory.sol';
import {ITokenGenerationEventFactory} from '../note-sale/fab/ITokenGenerationEventFactory.sol';
import {ISecuritizationTGE} from './ISecuritizationTGE.sol';

import {SecuritizationAccessControl} from './SecuritizationAccessControl.sol';
import {ISecuritizationPoolStorage} from './ISecuritizationPoolStorage.sol';

import 'hardhat/console.sol';

abstract contract SecuritizationManagerBase is ISecuritizationManager {
    Registry public override registry;

    mapping(address => bool) public override isExistingPools;
    address[] public override pools;

    // mapping(address => address) public poolToSOT;
    // mapping(address => address) public poolToJOT;
    mapping(address => address) public override potToPool;

    mapping(address => bool) public override isExistingTGEs;

    uint256[44] private __gap;
}

/// @title SecuritizationManager
/// @author Untangled Team
/// @notice You can use this contract for creating new pool, setting up note toke sale, buying note token
contract SecuritizationManager is UntangledBase, Factory2, SecuritizationManagerBase, IRequiresUID {
    using ConfigHelper for Registry;

    event UpdateAllowedUIDTypes(uint256[] uids);

    bytes4 public constant POOL_INIT_FUNC_SELECTOR = bytes4(keccak256('initialize(address,bytes)'));

    uint256[] public allowedUIDTypes;

    struct NewRoundSaleParam {
        uint256 openingTime;
        uint256 closingTime;
        uint256 rate;
        uint256 cap;
    }
    struct TGEParam {
        address issuerTokenController;
        address pool;
        uint256 minBidAmount;
        bool longSale;
        string ticker;
        uint8[] saleTypeAndDecimal;
    }

    struct IncreasingInterestParam {
        uint32 _initialInterest;
        uint32 _finalInterest;
        uint32 _timeInterval;
        uint32 _amountChangeEachInterval;
    }

    function initialize(Registry _registry, address _factoryAdmin) public reinitializer(2) {
        __UntangledBase__init(_msgSender());
        __Factory__init(_factoryAdmin);
        _setRoleAdmin(POOL_ADMIN, OWNER_ROLE);

        registry = _registry;
    }

    //noteSaleAddress, investor, amount, tokenAmount
    event TokensPurchased(address indexed investor, address indexed tgeAddress, uint256 amount, uint256 tokenAmount);

    modifier onlyPoolExisted(address pool) {
        require(isExistingPools[pool], 'SecuritizationManager: Pool does not exist');
        _;
    }

    modifier onlyManager(address pool) {
        require(
            // pool.hasRole(pool.OWNER_ROLE(), _msgSender()) ||
            hasRole(POOL_ADMIN, _msgSender()),
            'SecuritizationManager: Not the controller of the project'
        );
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
        require(ISecuritizationTGE(pool).sotToken() == address(0), 'SecuritizationManager: Already exists SOT token');
        _;
    }

    modifier doesJOTExist(address pool) {
        require(ISecuritizationTGE(pool).jotToken() == address(0), 'SecuritizationManager: Already exists JOT token');
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
    )
        external
        // address currency,
        // uint32 minFirstLossCushion,
        whenNotPaused
        onlyRole(POOL_ADMIN)
        returns (address)
    {
        // impl from eip1987
        // _implementation
        address poolImplAddress = address(registry.getSecuritizationPool());

        bytes memory _initialData = abi.encodeWithSelector(
            POOL_INIT_FUNC_SELECTOR,
            registry,
            params
            // currency,
            // minFirstLossCushion
        );

        address poolAddress = _deployInstance(poolImplAddress, _initialData, salt);
        SecuritizationAccessControl poolInstance = SecuritizationAccessControl(poolAddress);

        isExistingPools[poolAddress] = true;
        pools.push(poolAddress);

        // ...
        poolInstance.grantRole(OWNER_ROLE, poolOwner);
        poolInstance.renounceRole(OWNER_ROLE, address(this));
        ISecuritizationTGE(poolAddress).setUpPoolNAV();

        emit NewPoolCreated(poolAddress);

        return poolAddress;
    }

    /// @inheritdoc ISecuritizationManager
    function registerPot(address pot) external override whenNotPaused {
        require(isExistingPools[_msgSender()], 'SecuritizationManager: Only SecuritizationPool');
        require(potToPool[pot] == address(0), 'SecuritizationManager: pot used for another pool');
        potToPool[pot] = _msgSender();

        emit UpdatePotToPool(pot, _msgSender());
    }

    /// @notice sets up the initial token generation event (TGE) for the junior tranche (SOT) of a securitization pool
    /// @param issuerTokenController who acts as owner of note sale
    /// @param pool SecuritizationPool address where this sale belongs to
    /// @param saleTypeAndDecimal Contains sale type parameter and decimal value of note token
    /// @param longSale Define this sale is long sale. Default true
    /// @param ticker Prefix for note token symbol name. Ex: Saff_SOT
    function initialTGEForSOT(
        address issuerTokenController,
        address pool,
        uint8[] memory saleTypeAndDecimal,
        bool longSale,
        string memory ticker
    ) public onlyManager(pool) returns (address) {
        return _initialTGEForSOT(issuerTokenController, pool, saleTypeAndDecimal, longSale, ticker);
    }

    function _initialTGEForSOT(
        address issuerTokenController,
        address pool,
        uint8[] memory saleTypeAndDecimal,
        bool longSale,
        string memory ticker
    ) internal whenNotPaused nonReentrant onlyPoolExisted(pool) doesSOTExist(pool) returns (address) {
        INoteTokenFactory noteTokenFactory = registry.getNoteTokenFactory();
        require(address(noteTokenFactory) != address(0), 'Note Token Factory was not registered');
        require(address(registry.getTokenGenerationEventFactory()) != address(0), 'TGE Factory was not registered');

        address sotToken = noteTokenFactory.createToken(
            pool,
            Configuration.NOTE_TOKEN_TYPE.SENIOR,
            saleTypeAndDecimal[1],
            ticker
        );
        // poolToSOT[pool] = sotToken;
        require(sotToken != address(0), 'SOT token must be created');

        address tgeAddress = registry.getTokenGenerationEventFactory().createNewSaleInstance(
            issuerTokenController,
            // pool,
            sotToken,
            ISecuritizationTGE(pool).underlyingCurrency(),
            saleTypeAndDecimal[0],
            longSale
        );
        noteTokenFactory.changeMinterRole(sotToken, tgeAddress);

        ISecuritizationTGE(pool).injectTGEAddress(tgeAddress, Configuration.NOTE_TOKEN_TYPE.SENIOR);

        isExistingTGEs[tgeAddress] = true;

        emit NewTGECreated(tgeAddress);
        emit NewNotesTokenCreated(sotToken);
        return tgeAddress;
    }

    /// @notice Sets up the token generation event (TGE) for the senior tranche (SOT) of a securitization pool with additional configuration parameters
    /// @param increasingInterestParam Increasing interest parameters
    /// @param tgeParam TGE parameters
    /// @param saleParam Some parameters for new round token sale. Ex: openingTime, closeTime, totalCap...
    function setUpTGEForSOT(
        IncreasingInterestParam memory increasingInterestParam,
        TGEParam memory tgeParam,
        NewRoundSaleParam memory saleParam
    ) public onlyIssuer(tgeParam.pool) {
        address tgeAddress = _initialTGEForSOT(tgeParam.issuerTokenController, tgeParam.pool, tgeParam.saleTypeAndDecimal, tgeParam.longSale, tgeParam.ticker);
        MintedIncreasingInterestTGE tge = MintedIncreasingInterestTGE(tgeAddress);
        uint8 saleType = tgeParam.saleTypeAndDecimal[0];
        if (saleType == uint8(ITokenGenerationEventFactory.SaleType.MINTED_INCREASING_INTEREST_SOT)) {
            tge.setInterestRange(increasingInterestParam._initialInterest, increasingInterestParam._finalInterest, increasingInterestParam._timeInterval, increasingInterestParam._amountChangeEachInterval);
        }
        tge.startNewRoundSale(saleParam.openingTime, saleParam.closingTime, saleParam.rate, saleParam.cap);
        tge.setMinBidAmount(tgeParam.minBidAmount);
    }

    /// @notice sets up the token generation event (TGE) for the junior tranche (JOT) of a securitization pool with additional configuration parameters
    /// @param tgeParam Parameters for TGE
    /// @param initialJOTAmount Minimum amount of JOT raised in currency before SOT can start
    /// @param saleParam Some parameters for new round token sale. Ex: openingTime, closeTime, totalCap...
    function setUpTGEForJOT(
        uint256 initialJOTAmount,
        TGEParam memory tgeParam,
        NewRoundSaleParam memory saleParam
    ) public onlyIssuer(tgeParam.pool) {
        address tgeAddress = _initialTGEForJOT(tgeParam.issuerTokenController, tgeParam.pool, tgeParam.saleTypeAndDecimal, tgeParam.longSale, tgeParam.ticker);
        MintedNormalTGE tge = MintedNormalTGE(tgeAddress);
        tge.startNewRoundSale(saleParam.openingTime, saleParam.closingTime, saleParam.rate, saleParam.cap);
        tge.setHasStarted(true);
        tge.setMinBidAmount(tgeParam.minBidAmount);
        tge.setInitialAmount(initialJOTAmount);
    }

    function _initialTGEForJOT(
        address issuerTokenController,
        address pool,
        uint8[] memory saleTypeAndDecimal,
        bool longSale,
        string memory ticker
    ) public whenNotPaused nonReentrant onlyPoolExisted(pool) doesJOTExist(pool) returns (address) {
        INoteTokenFactory noteTokenFactory = registry.getNoteTokenFactory();

        address jotToken = noteTokenFactory.createToken(
            address(pool),
            Configuration.NOTE_TOKEN_TYPE.JUNIOR,
            saleTypeAndDecimal[1],
            ticker
        );

        // poolToJOT[pool] = jotToken;

        address tgeAddress = registry.getTokenGenerationEventFactory().createNewSaleInstance(
            issuerTokenController,
            // pool,
            jotToken,
            ISecuritizationTGE(pool).underlyingCurrency(),
            saleTypeAndDecimal[0],
            longSale
        );
        noteTokenFactory.changeMinterRole(jotToken, tgeAddress);

        ISecuritizationTGE(pool).injectTGEAddress(tgeAddress, Configuration.NOTE_TOKEN_TYPE.JUNIOR);

        isExistingTGEs[tgeAddress] = true;

        emit NewTGECreated(tgeAddress);
        emit NewNotesTokenCreated(jotToken);
        return tgeAddress;
    }

    /// @notice sets up the initial token generation event (TGE) for the junior tranche (JOT) of a securitization pool
    /// @param issuerTokenController who acts as owner of note sale
    /// @param pool SecuritizationPool address where this sale belongs to
    /// @param saleTypeAndDecimal Contains sale type parameter and decimal value of note token
    /// @param longSale Define this sale is long sale. Default true
    /// @param ticker Prefix for note token symbol name. Ex: Saff_JOT
    function initialTGEForJOT(
        address issuerTokenController,
        address pool,
        uint8[] memory saleTypeAndDecimal,
        bool longSale,
        string memory ticker
    ) public onlyManager(pool) returns (address) {
        return _initialTGEForJOT(issuerTokenController, pool, saleTypeAndDecimal, longSale, ticker);
    }

    /// @notice Investor bid for SOT or JOT token
    /// @param tgeAddress SOT/JOT token sale instance
    /// @param currencyAmount Currency amount investor will pay
    function buyTokens(address tgeAddress, uint256 currencyAmount) external whenNotPaused nonReentrant {
        require(isExistingTGEs[tgeAddress], 'SMP: Note sale does not exist');
        require(hasAllowedUID(_msgSender()), 'Unauthorized. Must have correct UID');

        ICrowdSale tge = ICrowdSale(tgeAddress);
        uint256 tokenAmount = tge.buyTokens(_msgSender(), _msgSender(), currencyAmount);

        if (INoteToken(tge.token()).noteTokenType() == uint8(Configuration.NOTE_TOKEN_TYPE.JUNIOR)) {
            if (MintedNormalTGE(tgeAddress).currencyRaised() >= MintedNormalTGE(tgeAddress).initialAmount()) {
                // Currency Raised For JOT > initialJOTAmount => SOT sale start
                address sotTGEAddress = ISecuritizationPoolStorage(tge.pool()).tgeAddress();
                if (sotTGEAddress != address(0)) {
                    ICrowdSale(sotTGEAddress).setHasStarted(true);
                }
            }
        }

        ISecuritizationTGE(tge.pool()).increaseReserve(currencyAmount);
        address poolOfPot = registry.getSecuritizationManager().potToPool(_msgSender());
        if (poolOfPot != address(0)) {
            ISecuritizationTGE(poolOfPot).decreaseReserve(currencyAmount);
        }

        // emit TokensPurchased(_msgSender(), tgeAddress, currencyAmount, tokenAmount);
    }

    function setAllowedUIDTypes(uint256[] calldata ids) external onlyRole(DEFAULT_ADMIN_ROLE) {
        allowedUIDTypes = ids;
        emit UpdateAllowedUIDTypes(ids);
    }

    /// @notice Check if an user has valid UID type
    function hasAllowedUID(address sender) public view override returns (bool) {
        return registry.getGo().goOnlyIdTypes(sender, allowedUIDTypes);
    }

    // function pausePool(address poolAddress) external whenNotPaused nonReentrant onlyRole(POOL_ADMIN) {
    //     require(isExistingPools[poolAddress], 'SecuritizationManager: pool does not exist');
    //     ISecuritizationPool pool = ISecuritizationPool(poolAddress);
    //     pool.pause();
    // }

    // function unpausePool(address poolAddress) external whenNotPaused nonReentrant onlyRole(POOL_ADMIN) {
    //     require(isExistingPools[poolAddress], 'SecuritizationManager: pool does not exist');
    //     ISecuritizationPool pool = ISecuritizationPool(poolAddress);
    //     pool.unpause();
    // }

    // function pauseAllPools() external whenNotPaused nonReentrant onlyRole(POOL_ADMIN) {
    //     uint256 poolsLength = pools.length;
    //     for (uint256 i = 0; i < poolsLength; i = UntangledMath.uncheckedInc(i)) {
    //         pools[i].pause();
    //     }
    // }

    // function unpauseAllPools() external whenNotPaused nonReentrant onlyRole(POOL_ADMIN) {
    //     uint256 poolsLength = pools.length;
    //     for (uint256 i = 0; i < poolsLength; i = UntangledMath.uncheckedInc(i)) {
    //         pools[i].unpause();
    //     }
    // }

    function registerValidator(address validator) public onlyRole(POOL_ADMIN) {
        require(validator != address(0), 'SecuritizationManager: Invalid validator address');
        IAccessControlUpgradeable(address(registry.getLoanAssetToken())).grantRole(VALIDATOR_ROLE, validator);
    }

    function unregisterValidator(address validator) public onlyRole(POOL_ADMIN) {
        IAccessControlUpgradeable(address(registry.getLoanAssetToken())).revokeRole(VALIDATOR_ROLE, validator);
    }

    uint256[49] private __gap;
}
