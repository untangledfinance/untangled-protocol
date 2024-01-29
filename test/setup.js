const { ethers, upgrades } = require('hardhat');
const { deployments } = require('hardhat');
const { OWNER_ROLE, POOL_ADMIN_ROLE, VALIDATOR_ADMIN_ROLE } = require('./constants');
const { LAT_BASE_URI } = require('./shared/constants');

const { parseEther } = ethers.utils;

const setUpLoanAssetToken = async (registry, securitizationManager) => {
    const LoanAssetToken = await ethers.getContractFactory('LoanAssetToken');
    const loanAssetTokenContract = await upgrades.deployProxy(
        LoanAssetToken,
        [registry.address, 'TEST', 'TST', LAT_BASE_URI],
        {
            initializer: 'initialize(address,string,string,string)',
        }
    );
    await registry.setLoanAssetToken(loanAssetTokenContract.address);

    const [poolAdmin, defaultLoanAssetTokenValidator] = await ethers.getSigners();

    await loanAssetTokenContract.grantRole(VALIDATOR_ADMIN_ROLE, securitizationManager.address);
    await securitizationManager.grantRole(OWNER_ROLE, poolAdmin.address);

    await securitizationManager.connect(poolAdmin).registerValidator(defaultLoanAssetTokenValidator.address);

    return {
        loanAssetTokenContract,
        defaultLoanAssetTokenValidator,
    };
};

const setUpTokenGenerationEventFactory = async (registry, factoryAdmin) => {
    const TokenGenerationEventFactory = await ethers.getContractFactory('TokenGenerationEventFactory');
    const tokenGenerationEventFactory = await upgrades.deployProxy(TokenGenerationEventFactory, [
        registry.address,
        factoryAdmin.address,
    ]);

    const MintedIncreasingInterestTGE = await ethers.getContractFactory('MintedIncreasingInterestTGE');
    const mintedIncreasingInterestTGEImpl = await MintedIncreasingInterestTGE.deploy();
    const MintedNormalTGE = await ethers.getContractFactory('MintedNormalTGE');
    const mintedNormalTGEImpl = await MintedNormalTGE.deploy();

    await tokenGenerationEventFactory.setTGEImplAddress(0, mintedIncreasingInterestTGEImpl.address);

    await tokenGenerationEventFactory.setTGEImplAddress(1, mintedNormalTGEImpl.address);

    await tokenGenerationEventFactory.setTGEImplAddress(2, mintedNormalTGEImpl.address);

    await registry.setTokenGenerationEventFactory(tokenGenerationEventFactory.address);

    return { tokenGenerationEventFactory };
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

const initPool = async (securitizationPoolImpl) => {
    // SecuritizationAccessControl,
    // SecuritizationPoolStorage,
    // SecuritizationTGE,
    // SecuritizationPoolAsset,
    // SecuritizationPoolNAV
    const SecuritizationAccessControl = await ethers.getContractFactory('SecuritizationAccessControl');
    const securitizationAccessControlImpl = await SecuritizationAccessControl.deploy();
    await securitizationPoolImpl.registerExtension(securitizationAccessControlImpl.address);

    const SecuritizationPoolStorage = await ethers.getContractFactory('SecuritizationPoolStorage');
    const securitizationPoolStorageImpl = await SecuritizationPoolStorage.deploy();
    await securitizationPoolImpl.registerExtension(securitizationPoolStorageImpl.address);

    const SecuritizationPoolTGE = await ethers.getContractFactory('SecuritizationTGE');
    const securitizationPoolTGEImpl = await SecuritizationPoolTGE.deploy();
    await securitizationPoolImpl.registerExtension(securitizationPoolTGEImpl.address);

    const SecuritizationPoolAsset = await ethers.getContractFactory('SecuritizationPoolAsset');
    const securitizationPoolAssetImpl = await SecuritizationPoolAsset.deploy();
    await securitizationPoolImpl.registerExtension(securitizationPoolAssetImpl.address);

    const SecuritizationPoolNAV = await ethers.getContractFactory('SecuritizationPoolNAV');
    const securitizationPoolNAVImpl = await SecuritizationPoolNAV.deploy();
    await securitizationPoolImpl.registerExtension(securitizationPoolNAVImpl.address);

    return securitizationPoolImpl;
};

const setUpSecuritizationPoolImpl = async (registry) => {
    const SecuritizationPool = await ethers.getContractFactory('SecuritizationPool');
    const securitizationPoolImpl = await SecuritizationPool.deploy();
    await registry.setSecuritizationPool(securitizationPoolImpl.address);

    await initPool(securitizationPoolImpl);

    return securitizationPoolImpl;
};

async function setup() {
    await deployments.fixture(['all']);

    let stableCoin;
    let registry;

    let loanKernel;
    let loanRepaymentRouter;
    let securitizationManager;
    let securitizationPoolValueService;
    let go;
    let uniqueIdentity;
    let distributionAssessor;
    let distributionOperator;
    let distributionTranche;
    let noteTokenVault;
    let factoryAdmin;

    const [untangledAdminSigner] = await ethers.getSigners();

    const tokenFactory = await ethers.getContractFactory('TestERC20');
    stableCoin = await tokenFactory.deploy('cUSD', 'cUSD', parseEther('100000'));

    const Registry = await ethers.getContractFactory('Registry');
    registry = await upgrades.deployProxy(Registry, []);

    const admin = await upgrades.admin.getInstance();

    factoryAdmin = await ethers.getContractAt('ProxyAdmin', admin.address);

    const SecuritizationManager = await ethers.getContractFactory('SecuritizationManager');
    securitizationManager = await upgrades.deployProxy(SecuritizationManager, [registry.address, factoryAdmin.address]);
    await securitizationManager.grantRole(POOL_ADMIN_ROLE, untangledAdminSigner.address);

    const SecuritizationPoolValueService = await ethers.getContractFactory('SecuritizationPoolValueService');
    securitizationPoolValueService = await upgrades.deployProxy(SecuritizationPoolValueService, [registry.address]);

    const { noteTokenFactory } = await setUpNoteTokenFactory(registry, factoryAdmin);
    const { tokenGenerationEventFactory } = await setUpTokenGenerationEventFactory(registry, factoryAdmin);

    const UniqueIdentity = await ethers.getContractFactory('UniqueIdentity');
    uniqueIdentity = await upgrades.deployProxy(UniqueIdentity, [untangledAdminSigner.address, '']);
    await uniqueIdentity.setSupportedUIDTypes([0, 1, 2, 3], [true, true, true, true]);
    await securitizationManager.setAllowedUIDTypes([0, 1, 2, 3]);

    const Go = await ethers.getContractFactory('Go');
    go = await upgrades.deployProxy(Go, [untangledAdminSigner.address, uniqueIdentity.address]);
    await registry.setGo(go.address);

    const LoanKernel = await ethers.getContractFactory('LoanKernel');
    loanKernel = await upgrades.deployProxy(LoanKernel, [registry.address]);
    const LoanRepaymentRouter = await ethers.getContractFactory('LoanRepaymentRouter');
    loanRepaymentRouter = await upgrades.deployProxy(LoanRepaymentRouter, [registry.address]);
    const DistributionAssessor = await ethers.getContractFactory('DistributionAssessor');
    distributionAssessor = await upgrades.deployProxy(DistributionAssessor, [registry.address]);

    const NoteTokenVault = await ethers.getContractFactory('NoteTokenVault');
    noteTokenVault = await upgrades.deployProxy(NoteTokenVault, [registry.address]);

    await registry.setSecuritizationManager(securitizationManager.address);
    await registry.setLoanKernel(loanKernel.address);
    await registry.setLoanRepaymentRouter(loanRepaymentRouter.address);
    await registry.setSecuritizationPoolValueService(securitizationPoolValueService.address);
    await registry.setDistributionAssessor(distributionAssessor.address);
    await registry.setNoteTokenVault(noteTokenVault.address);

    const { loanAssetTokenContract, defaultLoanAssetTokenValidator } = await setUpLoanAssetToken(
        registry,
        securitizationManager
    );

    const securitizationPoolImpl = await setUpSecuritizationPoolImpl(registry);

    return {
        stableCoin,
        registry,
        loanAssetTokenContract,
        defaultLoanAssetTokenValidator,

        loanKernel,
        loanRepaymentRouter,
        securitizationManager,
        securitizationPoolValueService,
        securitizationPoolImpl,
        go,
        uniqueIdentity,
        noteTokenFactory,
        tokenGenerationEventFactory,
        distributionOperator,
        distributionAssessor,
        distributionTranche,
        noteTokenVault,
        factoryAdmin,
        untangledAdminSigner,
    };
}

module.exports = {
    setup,
};
