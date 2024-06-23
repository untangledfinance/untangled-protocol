const { ethers, upgrades, deployments } = require('hardhat');
const { OWNER_ROLE, POOL_ADMIN_ROLE } = require('../constants');
const { LAT_BASE_URI } = require('../shared/constants');

const setUpLoanAssetToken = async (registry, securitizationManager) => {
    const LoanAssetToken = await ethers.getContractFactory('LoanAssetToken');
    const loanAssetToken = await upgrades.deployProxy(
        LoanAssetToken,
        [registry.address, 'TEST', 'TLAT', LAT_BASE_URI],
        {
            initializer: 'initialize(address,string,string,string)',
        }
    );
    await registry.setLoanAssetToken(loanAssetToken.address);
    const [poolAdmin, defaultLoanAssetTokenValidator] = await ethers.getSigners();
    await securitizationManager.grantRole(OWNER_ROLE, poolAdmin.address);

    return {
        loanAssetToken,
        defaultLoanAssetTokenValidator,
    };
};

const setUpNoteTokenFactory = async (registry, factoryAdmin) => {
    const NoteTokenFactory = await ethers.getContractFactory('NoteTokenFactory');
    const noteTokenFactory = await upgrades.deployProxy(NoteTokenFactory, [registry.address, factoryAdmin.address]);

    const NoteToken = await ethers.getContractFactory('NoteToken');
    const noteTokenImpl = await NoteToken.deploy();
    await noteTokenFactory.setNoteTokenImplementation(noteTokenImpl.address);

    await registry.setNoteTokenFactory(noteTokenFactory.address);
    return { noteTokenFactory };
};

const setUpPoolImpl = async (registry) => {
    const PoolNAVLogic = await ethers.getContractFactory('PoolNAVLogic');
    const poolNAVLogic = await PoolNAVLogic.deploy();
    await poolNAVLogic.deployed();

    const PoolAssetLogic = await ethers.getContractFactory('PoolAssetLogic', {
        libraries: {
            PoolNAVLogic: poolNAVLogic.address,
        },
    });
    const poolAssetLogic = await PoolAssetLogic.deploy();
    await poolAssetLogic.deployed();

    const RebaseLogic = await ethers.getContractFactory('RebaseLogic');
    const rebaseLogic = await RebaseLogic.deploy();
    await rebaseLogic.deployed();

    const GenericLogic = await ethers.getContractFactory('GenericLogic');
    const genericLogic = await GenericLogic.deploy();
    await genericLogic.deployed();

    const SecuritizationPool = await ethers.getContractFactory('Pool', {
        libraries: {
            PoolAssetLogic: poolAssetLogic.address,
            PoolNAVLogic: poolNAVLogic.address,
            RebaseLogic: rebaseLogic.address,
            GenericLogic: genericLogic.address,
        },
    });

    const securitizationPoolImpl = await SecuritizationPool.deploy();
    await securitizationPoolImpl.deployed();
    await registry.setSecuritizationPool(securitizationPoolImpl.address);

    return securitizationPoolImpl;
};

const setup = async () => {
    await deployments.fixture(['all']);

    let stableCoin;
    let registry;
    let loanKernel;
    let securitizationManager;
    let securitizationPoolValueService;
    let go;
    let uniqueIdentity;
    let sotTokenManager;
    let jotTokenManager;
    let epochExecutor;
    let factoryAdmin;

    const [adminSigner] = await ethers.getSigners();

    const tokenFactory = await ethers.getContractFactory('TestERC20');
    stableCoin = await tokenFactory.deploy('USDC', 'USDC', ethers.utils.parseEther('10000000'));

    const Registry = await ethers.getContractFactory('Registry');
    registry = await upgrades.deployProxy(Registry, []);

    const admin = await upgrades.admin.getInstance();

    factoryAdmin = await ethers.getContractAt('ProxyAdmin', admin.address);

    const SecuritizationManager = await ethers.getContractFactory('SecuritizationManager');
    securitizationManager = await upgrades.deployProxy(SecuritizationManager, [registry.address, factoryAdmin.address]);
    await securitizationManager.grantRole(POOL_ADMIN_ROLE, adminSigner.address);
    await registry.setSecuritizationManager(securitizationManager.address);

    const SecuritizationPoolValueService = await ethers.getContractFactory('SecuritizationPoolValueService');
    securitizationPoolValueService = await upgrades.deployProxy(SecuritizationPoolValueService, [registry.address]);

    const securitizationPoolImpl = await setUpPoolImpl(registry);

    const { noteTokenFactory } = await setUpNoteTokenFactory(registry, factoryAdmin);

    const UniqueIdentity = await ethers.getContractFactory('UniqueIdentity');
    uniqueIdentity = await upgrades.deployProxy(UniqueIdentity, [adminSigner.address, '']);
    await uniqueIdentity.setSupportedUIDTypes([0, 1, 2, 3], [true, true, true, true]);
    await securitizationManager.setAllowedUIDTypes([0, 1, 2, 3]);

    const Go = await ethers.getContractFactory('Go');
    go = await upgrades.deployProxy(Go, [adminSigner.address, uniqueIdentity.address]);
    await registry.setGo(go.address);

    const LoanKernel = await ethers.getContractFactory('LoanKernel');
    loanKernel = await upgrades.deployProxy(LoanKernel, [registry.address]);
    await registry.setLoanKernel(loanKernel.address);

    const NoteTokenManager = await ethers.getContractFactory('NoteTokenManager');
    sotTokenManager = await upgrades.deployProxy(NoteTokenManager, [
        registry.address,
        stableCoin.address,
        [0, 1, 2, 3],
    ]);
    jotTokenManager = await upgrades.deployProxy(NoteTokenManager, [
        registry.address,
        stableCoin.address,
        [0, 1, 2, 3],
    ]);
    await registry.setSeniorTokenManager(sotTokenManager.address);
    await registry.setJuniorTokenManager(jotTokenManager.address);

    const EpochExecutor = await ethers.getContractFactory('EpochExecutor');
    epochExecutor = await upgrades.deployProxy(EpochExecutor, [registry.address]);
    await registry.setEpochExecutor(epochExecutor.address);

    await epochExecutor.setUpNoteTokenManger();
    await sotTokenManager.setUpEpochExecutor();
    await jotTokenManager.setUpEpochExecutor();

    const { loanAssetToken, defaultLoanAssetTokenValidator } = await setUpLoanAssetToken(
        registry,
        securitizationManager
    );
    return {
        stableCoin,
        registry,
        loanAssetToken,
        defaultLoanAssetTokenValidator,
        loanKernel,
        securitizationManager,
        securitizationPoolValueService,
        securitizationPoolImpl,
        go,
        uniqueIdentity,
        noteTokenFactory,
        epochExecutor,
        sotTokenManager,
        jotTokenManager,
        factoryAdmin,
        adminSigner,
    };
};

module.exports = {
    setup,
};
