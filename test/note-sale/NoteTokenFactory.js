const { upgrades } = require('hardhat');
const { setup } = require('../setup');
const { expect, assert } = require('chai');
const { BigNumber } = require('ethers');

// const ONE_DAY = 86400;
// const DECIMAL = BigNumber.from(10).pow(18);
describe('NoteTokenFactory', () => {
    let registry;
    let noteTokenFactory;
    let SecuritizationPool;

    before('create fixture', async () => {
        await setup();
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

        SecuritizationPool = await ethers.getContractFactory('Pool', {
            libraries: {
                PoolAssetLogic: poolAssetLogic.address,
                PoolNAVLogic: poolNAVLogic.address,
                TGELogic: tgeLogic.address,
                RebaseLogic: rebaseLogic.address,
            },
        });

        const MintedNormalTGE = await ethers.getContractFactory('MintedNormalTGE');
        const NoteToken = await ethers.getContractFactory('NoteToken');
        const NoteTokenFactory = await ethers.getContractFactory('NoteTokenFactory');
        const Registry = await ethers.getContractFactory('Registry');

        registry = await upgrades.deployProxy(Registry, []);

        const admin = await upgrades.admin.getInstance();
        noteTokenFactory = await upgrades.deployProxy(NoteTokenFactory, [registry.address, admin.address]);

        const noteTokenImpl = await NoteToken.deploy();
        await noteTokenFactory.setNoteTokenImplementation(noteTokenImpl.address);
        // await registry.setNoteToken(noteTokenImpl.address);

        // await noteTokenFactory.initialize(registry.address, admin.address);
    });

    it('#createToken', async () => {
        const pool = await SecuritizationPool.deploy();

        const [deployer] = await ethers.getSigners();
        await registry.setSecuritizationManager(deployer.address);
        await noteTokenFactory.createToken(pool.address, 0, 2, 'TOKEN'); // SENIOR
    });

    it('#pauseUnpauseToken', async () => {
        const pool = await SecuritizationPool.deploy();
        const tx = await noteTokenFactory.createToken(pool.address, 0, 2, 'TOKEN'); // SENIOR
        const receipt = await tx.wait();

        const tokenAddress = receipt.events.find((x) => x.event == 'TokenCreated').args.token;

        await expect(noteTokenFactory.pauseUnpauseToken(tokenAddress)).to.not.be.reverted;
    });

    it('#pauseAllToken', async () => {
        const pool = await SecuritizationPool.deploy();
        await noteTokenFactory.createToken(pool.address, 0, 2, 'TOKEN'); // SENIOR
        await expect(noteTokenFactory.pauseAllTokens()).to.not.be.reverted;
    });

    it('#unPauseAllTokens', async () => {
        const pool = await SecuritizationPool.deploy();
        await noteTokenFactory.createToken(pool.address, 0, 2, 'TOKEN'); // SENIOR
        await expect(noteTokenFactory.unPauseAllTokens()).to.not.be.reverted;
    });
});
