const { networks } = require('../networks');
const { utils } = require('ethers');
module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, execute, get, read } = deployments;
    const { deployer } = await getNamedAccounts();

    await deploy('UniqueIdentity', {
        from: deployer,
        proxy: {
            proxyContract: 'OpenZeppelinTransparentProxy',
            execute: {
                init: {
                    methodName: 'initialize',
                    args: [deployer, ''],
                },
            },
        },
        // skipIfAlreadyDeployed: true,
        log: true,
    });

    const kycAdmin = network.config.kycAdmin;
    const superAdmin = network.config.superAdmin;
    const SIGNER_ROLE = utils.keccak256(Buffer.from('SIGNER_ROLE'));

    await execute(
        'UniqueIdentity',
        {
            from: deployer,
            log: true,
        },
        'grantRole',
        SIGNER_ROLE,
        kycAdmin
    );

    await execute(
        'UniqueIdentity',
        {
            from: deployer,
            log: true,
        },
        'addSuperAdmin',
        superAdmin
    );
};

module.exports.dependencies = [];
module.exports.tags = ['mainnet', 'UniqueIdentity', 'next'];
