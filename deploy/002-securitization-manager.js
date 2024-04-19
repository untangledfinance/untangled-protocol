const { utils } = require('ethers');

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, read, get, execute } = deployments;
    const { deployer } = await getNamedAccounts();
    const proxyAdmin = await get('DefaultProxyAdmin');

    const registry = await get('Registry');

    const SecuritizationManager = await deploy('SecuritizationManager', {
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

    await execute('Registry', { from: deployer, log: true }, 'setSecuritizationManager', SecuritizationManager.address);
    const superAdmin = network.config.superAdmin;

    const OWNER_ROLE = utils.keccak256(Buffer.from('OWNER_ROLE'));
    await execute(
        'SecuritizationManager',
        {
            from: deployer,
            log: true,
        },
        'grantRole',
        OWNER_ROLE,
        superAdmin
    );
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['next', 'mainnet', 'SecuritizationManager'];
