module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, execute } = deployments;
    const { deployer } = await getNamedAccounts();

    const securitizationPool = await deploy('SecuritizationPool', {
        from: deployer,
        args: [],
        log: true,
    });

    const pAccessControl = await deploy('SecuritizationAccessControl', {
        from: deployer,
        args: [],
        log: true,
    });
    await execute('SecuritizationPool', { from: deployer, log: true }, 'registerExtension', pAccessControl.address);

    const pStorage = await deploy('SecuritizationPoolStorage', {
        from: deployer,
        args: [],
        log: true,
    });
    await execute('SecuritizationPool', { from: deployer, log: true }, 'registerExtension', pStorage.address);

    const pTGE = await deploy('SecuritizationTGE', {
        from: deployer,
        args: [],
        log: true,
    });
    await execute('SecuritizationPool', { from: deployer, log: true }, 'registerExtension', pTGE.address);

    const pAsset = await deploy('SecuritizationPoolAsset', {
        from: deployer,
        args: [],
        log: true,
    });
    await execute('SecuritizationPool', { from: deployer, log: true }, 'registerExtension', pAsset.address);

    const pNAV = await deploy('SecuritizationPoolNAV', {
        from: deployer,
        args: [],
        log: true,
    });
    await execute('SecuritizationPool', { from: deployer, log: true }, 'registerExtension', pNAV.address);

    await execute('Registry', { from: deployer, log: true }, 'setSecuritizationPool', securitizationPool.address);
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['next', 'mainnet', 'SecuritizationPool'];
