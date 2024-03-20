const { utils } = require('ethers');

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

    const beSigner = network.config.beSigner;
    const beAdmin = network.config.beAdmin;

    // const SIGNER_ROLE = utils.keccak256(Buffer.from('SIGNER_ROLE'));
    // await execute(
    //     'NoteTokenVault',
    //     {
    //         from: deployer,
    //         log: true,
    //     },
    //     'grantRole',
    //     SIGNER_ROLE,
    //     beSigner
    // );

    // console.log('beAdmin', beAdmin);
    // const BACKEND_ADMIN = utils.keccak256(Buffer.from('BACKEND_ADMIN'));
    // await execute(
    //     'NoteTokenVault',
    //     {
    //         from: deployer,
    //         log: true,
    //     },
    //     'grantRole',
    //     BACKEND_ADMIN,
    //     beAdmin
    // );
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['next', 'mainnet', 'NoteTokenVault'];
