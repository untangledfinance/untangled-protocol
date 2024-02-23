module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, execute } = deployments;
    const { deployer } = await getNamedAccounts();

    const poolNAVLogic = await deploy('PoolNAVLogic', {
        from: deployer,
        args: [],
        log: true,
    });

    const poolAssetLogic = await deploy('PoolAssetLogic', {
        from: deployer,
        args: [],
        libraries: {
            PoolNAVLogic: poolNAVLogic.address,
        },
        log: true,
    });

    const tgeLogic = await deploy('TGELogic', {
        from: deployer,
        args: [],
        log: true,
    });

    const securitizationPool = await deploy('Pool', {
        from: deployer,
        args: [],
        libraries: {
            PoolAssetLogic: poolAssetLogic.address,
            PoolNAVLogic: poolNAVLogic.address,
            TGELogic: tgeLogic.address,
        },
        log: true,
    });

    await execute('Registry', { from: deployer, log: true }, 'setSecuritizationPool', securitizationPool.address);
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['next', 'mainnet', 'SecuritizationPool'];
