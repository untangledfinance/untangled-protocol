module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, read, get, execute } = deployments;
    const { deployer } = await getNamedAccounts();
    const proxyAdmin = await get('DefaultProxyAdmin');

    const registry = await get('Registry');

    const SecuritizationManager = await deploy('SecuritizationManager', {
        from: deployer,

        proxy: {
            proxyContract: 'OpenZeppelinTransparentProxy',
        },
        log: true,
    });

    const currentVersion = await read('SecuritizationManager', {}, 'getInitializedVersion');
    if (currentVersion.toNumber() < 2) {
        await execute(
            'SecuritizationManager',
            {
                from: deployer,
                log: true,
            },
            'initialize',
            registry.address,
            proxyAdmin.address
        );
    }

    // await execute('Registry', { from: deployer, log: true }, 'setSecuritizationManager', SecuritizationManager.address);
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['next', 'mainnet', 'SecuritizationManager'];
