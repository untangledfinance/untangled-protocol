const { deployProxy } = require('../utils/deployHelper');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { execute } = deployments;
  const { deployer } = await getNamedAccounts();

  //deploy UniqueIdentity
  const uniqueIdentityProxy = await deployProxy({ getNamedAccounts, deployments }, 'UniqueIdentity', [deployer, '']);
  if (uniqueIdentityProxy.newlyDeployed) {
    await execute(
      'UniqueIdentity',
      { from: deployer, log: true },
      'setSupportedUIDTypes',
      [0, 1, 2, 3],
      [true, true, true, true]
    );
  }

  const goProxy = await deployProxy({ getNamedAccounts, deployments }, 'Go', [deployer, uniqueIdentityProxy.address]);
  if (goProxy.newlyDeployed) {
    await execute('Registry', { from: deployer, log: true }, 'setGo', goProxy.address);
  }
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['unique_identity_v1', 'core'];
