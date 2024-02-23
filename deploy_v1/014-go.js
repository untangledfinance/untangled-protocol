module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, execute, get } = deployments;
    const { deployer } = await getNamedAccounts();

    const uniqueIdentity = await get('UniqueIdentity');

    const deployResult = await deploy('Go', {
        from: deployer,
        proxy: {
            proxyContract: 'OpenZeppelinTransparentProxy',
            execute: {
                methodName: 'initialize',
                args: [deployer, uniqueIdentity.address],
            },
        },
        skipIfAlreadyDeployed: true,
        log: true,
    });

    await execute('Registry', { from: deployer, log: true }, 'setGo', deployResult.address);

    await execute(
        'UniqueIdentity',
        {
            from: deployer,
            log: true,
        },
        'setSupportedUIDTypes',
        [0, 1, 2, 3],
        [true, true, true, true]
    );

    await execute(
        'SecuritizationManager',
        {
            from: deployer,
            log: true,
        },
        'setAllowedUIDTypes',
        [0, 1, 2, 3]
    );
};

module.exports.dependencies = ['UniqueIdentity'];
module.exports.tags = ['mainnet', 'Go', 'next'];
