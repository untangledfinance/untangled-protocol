const { getChainId } = require('hardhat');
const { registrySet } = require('../utils');

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
module.exports.tags = ['migration_mumbai', 'sp_value_service_mumbai_migration'];
