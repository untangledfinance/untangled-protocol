const { getChainId } = require('hardhat');
const { registrySet } = require('./utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy,read, get } = deployments;
  const { deployer } = await getNamedAccounts();
  const proxyAdmin = await get('DefaultProxyAdmin');

  const registry = await get("Registry");

  await deployments.deploy('SecuritizationManager', {
    from: deployer,

    proxy: {
      proxyContract: "OpenZeppelinTransparentProxy",
    },
    log: true,
  });

  const currentVersion = await read('SecuritizationManager', {}, 'getInitializedVersion');
  if (currentVersion.toNumber() < 2) {
    await execute('SecuritizationManager', {
      from: deployer,
      log: true,
    }, 'initialize', registry.address, proxyAdmin.address);
  }

  await registrySet(['SecuritizationManager']);
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['v3', 'mainnet', 'SecuritizationManager'];
