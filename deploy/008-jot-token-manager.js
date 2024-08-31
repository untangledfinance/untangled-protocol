module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, get, execute } = deployments;
    const { deployer } = await getNamedAccounts();
    const registry = await get('Registry');

    const juniorTokenManager = await deploy('NoteTokenManager', {
        from: deployer,
        proxy: {
            proxyContract: 'OpenZeppelinTransparentProxy',
            execute: {
                init: {
                    methodName: 'initialize',
                    args: [registry.address, [0, 1, 2, 3]],
                },
            },
        },
        log: true,
        skipIfAlreadyDeployed: false,
    });

    await execute('Registry', { from: deployer, log: true }, 'setJuniorTokenManager', juniorTokenManager.address);
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['next', 'mainnet', 'JuniorTokenManager'];
