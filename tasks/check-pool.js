const { expect } = require('chai');
const { networks } = require('../networks');

task('check-pool', 'Check pool values').setAction(async (taskArgs, hre) => {
    const { deployments, ethers } = hre;
    const { get, read } = deployments;
    const [deployer] = await ethers.getSigners();
    const poolAddress = '0xd79396a9E1c85bE663B7A5f0F80Ce19c7390bBA0';

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

    const getApprovedReserved = await poolService.getApprovedReserved(pool.address);
    console.log('getApprovedReserved', getApprovedReserved);
    const sotToken = await pool.sotToken();
    console.log('sotToken', sotToken);
    const jotToken = await pool.jotToken();
    console.log('jotToken', jotToken);
    const calcTokenPrices = await pool.calcTokenPrices();
    console.log('calcTokenPrices', calcTokenPrices);
    const reserve = await pool.reserve();
    console.log('reserve', reserve);
    const currentNAV = await pool.currentNAV();
    console.log('currentNAV', currentNAV);

    const getMaxAvailableReserve = await poolService.getMaxAvailableReserve(pool.address, 10000000000);
    console.log('getMaxAvailableReserve', getMaxAvailableReserve);
});
