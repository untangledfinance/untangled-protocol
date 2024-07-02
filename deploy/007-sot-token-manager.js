module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, get, execute } = deployments;
    const { deployer } = await getNamedAccounts();
    const registry = await get('Registry');

    const seniorTokenManager = await deploy('NoteTokenManager', {
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
    });

    await execute('Registry', { from: deployer, log: true }, 'setSeniorTokenManager', seniorTokenManager.address);
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['next', 'mainnet', 'SeniorTokenManager'];
