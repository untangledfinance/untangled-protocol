const { expect } = require('chai');
const { networks } = require('../networks');

task('check-pool', 'Check pool values').setAction(async (taskArgs, hre) => {
    const { deployments, ethers } = hre;
    const { get, read } = deployments;
    const [deployer] = await ethers.getSigners();
    const poolAddress = '0x462918a5d282da81bf9545e6a8c1910a7852699b';

    const Registry = await ethers.getContractFactory('Registry');
    const registryContract = await get('Registry');
    const registry = await Registry.attach(registryContract.address);

    const SecuritizationPoolValueService = await ethers.getContractFactory('SecuritizationPoolValueService');
    const SecuritizationPoolValueServiceContract = await get('SecuritizationPoolValueService');
    const poolService = await SecuritizationPoolValueService.attach(SecuritizationPoolValueServiceContract.address);

    const PoolNAVLogic = await get('PoolNAVLogic');
    const PoolAssetLogic = await get('PoolAssetLogic');
    const TGELogic = await get('TGELogic');
    const RebaseLogic = await get('RebaseLogic');
    const SecuritizationPool = await ethers.getContractFactory('Pool', {
        libraries: {
            PoolAssetLogic: PoolAssetLogic.address,
            PoolNAVLogic: PoolNAVLogic.address,
            TGELogic: TGELogic.address,
            RebaseLogic: RebaseLogic.address,
        },
    });
    const pool = await SecuritizationPool.attach(poolAddress);

    const jotPrice = await poolService.getJOTTokenPrice(pool.address);

    console.log(jotPrice);
});
