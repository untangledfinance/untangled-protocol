//deploy NoteTokenVault

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { get, execute, deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const registry = await get('Registry');

    const noteTokenVaultProxy = await deploy('NoteTokenVault', {
        from: deployer,
        proxy: {
            proxyContract: 'OpenZeppelinTransparentProxy',
            execute: {
                init: {
                    methodName: 'initialize',
                    args: [registry.address],
                },
            },
        },
        log: true,
    });

    await execute('Registry', { from: deployer, log: true }, 'setNoteTokenVault', noteTokenVaultProxy.address);
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['next', 'mainnet', 'NoteTokenVault'];
