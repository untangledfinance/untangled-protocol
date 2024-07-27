const { utils } = require('ethers');

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, read, get, execute } = deployments;
    const { deployer } = await getNamedAccounts();
    const proxyAdmin = await get('DefaultProxyAdmin');

    // const securitizationManager = await get('SecuritizationManager');

    const POOL_ADMIN_ROLE = utils.keccak256(Buffer.from('POOL_CREATOR'));
    const poolAdminAddress = '0xEc4cF98e56DC7f84342D08587a624e9421071aF0';
    await execute(
        'SecuritizationManager',
        {
            from: deployer,
            log: true,
        },
        'grantRole',
        POOL_ADMIN_ROLE,
        poolAdminAddress
    );
};

module.exports.dependencies = ['SecuritizationManager'];
module.exports.tags = ['SetPoolAdmin'];
