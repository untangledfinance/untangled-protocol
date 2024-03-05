const { networks } = require('../networks');

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

    const SIGNER_ROLE = await read('UniqueIdentity', 'SIGNER_ROLE');
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
        '0x60e7b40B1f46971B800cd00200371fFd35c09Da9'
    );
};

module.exports.dependencies = [];
module.exports.tags = ['mainnet', 'UniqueIdentity', 'next'];
