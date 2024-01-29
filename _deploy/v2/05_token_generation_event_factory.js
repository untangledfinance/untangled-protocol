const { getChainId } = require('hardhat');
const { networks } = require('../../networks');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, execute, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const registry = await deployments.get('Registry');
  const proxyAdmin = await get('DefaultProxyAdmin');

  await deployments.deploy('TokenGenerationEventFactory', {
    from: deployer,
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
      execute: {
        methodName: 'initialize',
        args: [registry.address, proxyAdmin.address],
      },
    },
    skipIfAlreadyDeployed: true,
    log: true,
  });
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['mainnet', 'token_generation_event_factory'];
