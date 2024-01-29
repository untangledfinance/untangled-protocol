const { getChainId } = require('hardhat');
const { networks } = require('../../networks');

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, execute, get } = deployments;
    const { deployer } = await getNamedAccounts();

    const registry = await deployments.get('Registry');

    await deployments.deploy('SecuritizationPoolValueService', {
        from: deployer,
        proxy: {
            proxyContract: 'OpenZeppelinTransparentProxy',
        },
        log: true,
    });
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['v4', 'mainnet', 'securitization_pool_value_service'];
