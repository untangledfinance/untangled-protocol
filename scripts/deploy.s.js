const { ethers, upgrades } = require('hardhat');
const { OWNER_ROLE, POOL_ADMIN_ROLE } = require('../test/constants');
const { LAT_BASE_URI } = require('../test/shared/constants');
async function main() {
    const [deployer] = await ethers.getSigners();
    const Registry = await ethers.getContractFactory('Registry');
    const registry = await upgrades.deployProxy(Registry, []);

    const admin = await upgrades.admin.getInstance();
    const factoryAdmin = await ethers.getContractAt('ProxyAdmin', admin.address);

    const SecuritizationManager = await ethers.getContractFactory('SecuritizationManager');
    const securitizationManager = await upgrades.deployProxy(SecuritizationManager);
    await securitizationManager.grantRole(POOL_ADMIN_ROLE, deployer.address);
    await registry.setSecuritizationManager(securitizationManager.address);

    // setup NoteTokenFatory
    const NoteTokenFactory = await ethers.getContractFactory('NoteTokenFactory');
    const noteTokenFactory = await upgrades.deployProxy(NoteTokenFactory, [registry.address, factoryAdmin.address]);

    const NoteToken = await ethers.getContractFactory('NoteToken');
    const noteTokenImpl = await NoteToken.deploy();
    await noteTokenFactory.setNoteTokenImplementation(noteTokenImpl.address);
    await registry.setNoteTokenFactory(noteTokenFactory.address);

    // setup TokenGenerationEventFactory
    const TokenGenerationEventFactory = await ethers.getContractFactory('TokenGenerationEventFactory');
    const tokenGenerationEventFactory = await upgrades.deployProxy(TokenGenerationEventFactory, [
        registry.address,
        factoryAdmin.address,
    ]);

    const MintedNormalTGE = await ethers.getContractFactory('MintedNormalTGE');
    const mintedNormalTGEImpl = await MintedNormalTGE.deploy();

    await tokenGenerationEventFactory.setTGEImplAddress(0, mintedNormalTGEImpl.address);

    await tokenGenerationEventFactory.setTGEImplAddress(1, mintedNormalTGEImpl.address);

    await registry.setTokenGenerationEventFactory(tokenGenerationEventFactory.address);

    // setup Pool
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
    const TGELogic = await ethers.getContractFactory('TGELogic');
    const tgeLogic = await TGELogic.deploy();
    await tgeLogic.deployed();

    const RebaseLogic = await ethers.getContractFactory('RebaseLogic');
    const rebaseLogic = await RebaseLogic.deploy();
    await rebaseLogic.deployed();

    const SecuritizationPool = await ethers.getContractFactory('Pool', {
        libraries: {
            PoolAssetLogic: poolAssetLogic.address,
            PoolNAVLogic: poolNAVLogic.address,
            TGELogic: tgeLogic.address,
            RebaseLogic: rebaseLogic.address,
        },
    });
    const securitizationPoolImpl = await SecuritizationPool.deploy();
    await securitizationPoolImpl.deployed();
    await registry.setSecuritizationPool(securitizationPoolImpl.address);

    const UniqueIdentity = await ethers.getContractFactory('UniqueIdentity');
    const uniqueIdentity = await upgrades.deployProxy(UniqueIdentity, [deployer.address, '']);
    await uniqueIdentity.setSupportedUIDTypes([0, 1, 2, 3], [true, true, true, true]);
    await securitizationManager.setAllowedUIDTypes([0, 1, 2, 3]);

    const Go = await ethers.getContractFactory('Go');
    const go = await upgrades.deployProxy(Go, [deployer.address, uniqueIdentity.address]);
    await registry.setGo(go.address);

    const LoanKernel = await ethers.getContractFactory('LoanKernel');
    const loanKernel = await upgrades.deployProxy(LoanKernel, [registry.address]);
    await registry.setLoanKernel(loanKernel.address);

    const NoteTokenVault = await ethers.getContractFactory('NoteTokenVault');
    const noteTokenVault = await upgrades.deployProxy(NoteTokenVault, [registry.address]);
    await registry.setNoteTokenVault(noteTokenVault.address);

    const LoanAssetToken = await ethers.getContractFactory('LoanAssetToken');
    const loanAssetTokenContract = await upgrades.deployProxy(
        LoanAssetToken,
        [registry.address, 'TEST', 'TST', LAT_BASE_URI],
        {
            initializer: 'initialize(address,string,string,string)',
        }
    );
    await registry.setLoanAssetToken(loanAssetTokenContract.address);

    await securitizationManager.grantRole(OWNER_ROLE, deployer.address);

    console.log();
}
main();
