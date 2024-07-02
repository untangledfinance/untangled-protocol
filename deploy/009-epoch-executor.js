module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, get, execute } = deployments;
    const { deployer } = await getNamedAccounts();

    const registry = await get('Registry');
    const EpochExecutor = await deploy('EpochExecutor', {
        from: deployer,
        proxy: {
            init: {
                methodName: 'initialize',
                args: [registry.address],
            },
        },
        log: true,
    });

    await execute('Registry', { from: deployer, log: true }, 'setEpochExecutor', EpochExecutor.address);
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['next', 'mainnet', 'EpochExecutor'];
