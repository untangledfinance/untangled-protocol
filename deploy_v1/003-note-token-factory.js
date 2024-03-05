module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, read, execute, get } = deployments;
    const { deployer } = await getNamedAccounts();
    const proxyAdmin = await get('DefaultProxyAdmin');

    const registry = await get('Registry');

    const noteTokenFactory = await deploy('NoteTokenFactory', {
        from: deployer,
        proxy: {
            proxyContract: 'OpenZeppelinTransparentProxy',

            execute: {
                init: {
                    methodName: 'initialize',
                    args: [registry.address, proxyAdmin.address],
                },
            },
        },
        log: true,
    });

    // const currentVersion = await read('NoteTokenFactory', {}, 'getInitializedVersion');
    // if (currentVersion.toNumber() < 3) {
    //   await execute('NoteTokenFactory', {
    //     from: deployer,
    //     log: true,
    //   }, 'initialize', registry.address, proxyAdmin.address);
    // }

    // await execute('NoteTokenFactory', {
    //   from: deployer,
    //   log: true,
    // }, 'initialize', registry.address, proxyAdmin.address);
    await execute('Registry', { from: deployer, log: true }, 'setNoteTokenFactory', noteTokenFactory.address);
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['next', 'mainnet', 'NoteTokenFactory'];
