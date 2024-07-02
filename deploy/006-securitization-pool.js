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

    const genericLogic = await deploy('GenericLogic', {
        from: deployer,
        args: [],
        log: true,
    });

    const rebaseLogic = await deploy('RebaseLogic', {
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
            GenericLogic: genericLogic.address,
            RebaseLogic: rebaseLogic.address,
        },
        log: true,
    });

    await execute('Registry', { from: deployer, log: true }, 'setSecuritizationPool', securitizationPool.address);
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['next', 'mainnet', 'SecuritizationPool'];
