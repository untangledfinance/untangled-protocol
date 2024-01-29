module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, execute, get } = deployments;
    const { deployer } = await getNamedAccounts();

    const registry = await deployments.get('Registry');

    const securitizationPoolValueService = await deploy('SecuritizationPoolValueService', {
        from: deployer,
        proxy: {
            proxyContract: 'OpenZeppelinTransparentProxy',
            // execute: {
            //     methodName: 'initialize',
            //     args: [registry.address],
            // },
            execute: {
                init: {
                    methodName: 'initialize',
                    args: [registry.address],
                },
            },
        },
        log: true,
    });

    await execute(
        'Registry',
        { from: deployer, log: true },
        'setSecuritizationPoolValueService',
        securitizationPoolValueService.address
    );
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['next', 'mainnet', 'SecuritizationPoolValueService'];
