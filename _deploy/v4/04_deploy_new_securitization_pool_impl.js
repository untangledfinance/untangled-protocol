const { registrySet } = require('../v2/utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { readDotFile, deploy, execute, get, save } = deployments;
    const { deployer } = await getNamedAccounts();
    
    await deploy('SecuritizationPool', {
        from: deployer,
        args: [],
        log: true,
    });

    const pAccessControl = await deploy('SecuritizationAccessControl', {
        from: deployer,
        args: [],
        log: true
    });
    await execute('SecuritizationPool', { from: deployer, log: true }, 'registerExtension', pAccessControl.address);

    const pStorage = await deploy('SecuritizationPoolStorage', {
        from: deployer,
        args: [],
        log: true
    });
    await execute('SecuritizationPool', { from: deployer, log: true }, 'registerExtension', pStorage.address);

    const pTGE = await deploy('SecuritizationTGE', {
        from: deployer,
        args: [],
        log: true
    });
    await execute('SecuritizationPool', { from: deployer, log: true }, 'registerExtension', pTGE.address);

    const pAsset = await deploy('SecuritizationPoolAsset', {
        from: deployer,
        args: [],
        log: true
    });
    await execute('SecuritizationPool', { from: deployer, log: true }, 'registerExtension', pAsset.address);

    const pLockDistribution = await deploy('SecuritizationLockDistribution', {
        from: deployer,
        args: [],
        log: true
    });
    await execute('SecuritizationPool', { from: deployer, log: true }, 'registerExtension', pLockDistribution.address);

    const contracts = ['SecuritizationPool'];

    await registrySet(contracts);
};

module.exports.dependencies = [];
module.exports.tags = ['v4', 'mainnet', 'securitization_pool_new_deployment'];
