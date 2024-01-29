const { registrySet } = require('./utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { get, execute } = deployments;
  const { deployer } = await getNamedAccounts();

  const tgeNormal = await deployments.deploy('MintedNormalTGE', {
    from: deployer,
    log: true,
  });

  // if (tgeNormal.newlyDeployed) {
  await execute('TokenGenerationEventFactory', {
    from: deployer,
    log: true,
  }, 'setTGEImplAddress', 1, tgeNormal.address);

  await execute('TokenGenerationEventFactory', {
    from: deployer,
    log: true,
  }, 'setTGEImplAddress', 2, tgeNormal.address);
  // }
};

module.exports.dependencies = ['registry', 'TokenGenerationEventFactory'];
module.exports.tags = ['v3', 'mainnet', 'MintedNormalTGE'];
