module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, get, execute, read } = deployments;
    const { deployer } = await getNamedAccounts();

    const registry = await get('Registry');
    const proxyAdmin = await get('DefaultProxyAdmin');

    const TokenGenerationEventFactory = await deploy('TokenGenerationEventFactory', {
        from: deployer,
        proxy: {
            execute: {
                init: {
                    methodName: 'initialize',
                    args: [registry.address, proxyAdmin.address],
                },
            },
            proxyContract: 'OpenZeppelinTransparentProxy',
        },
        log: true,
    });

    await execute(
        'Registry',
        { from: deployer, log: true },
        'setTokenGenerationEventFactory',
        TokenGenerationEventFactory.address
    );

    // if (currentVersion.toNumber() < 94) {

    // await execute('TokenGenerationEventFactory', {
    //     from: deployer,
    //     log: true,
    //   }, 'initialize', registry.address, proxyAdmin.address);
    //   // }
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['next', 'mainnet', 'TokenGenerationEventFactory'];
