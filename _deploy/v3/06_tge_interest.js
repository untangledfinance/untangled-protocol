const { registrySet } = require('./utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { get, execute, read } = deployments;
  const { deployer } = await getNamedAccounts();

  const tgeInterest = await deployments.deploy('MintedIncreasingInterestTGE', {
    from: deployer,
    log: true,
  });

  // // if (tgeInterest.newlyDeployed) {
  await execute('TokenGenerationEventFactory', {
    from: deployer,
    log: true,
  }, 'setTGEImplAddress', 0, tgeInterest.address);
  // // }
};

module.exports.dependencies = ['registry', 'TokenGenerationEventFactory'];
module.exports.tags = ['v3', 'mainnet', 'MintedIncreasingInterestTGE'];
