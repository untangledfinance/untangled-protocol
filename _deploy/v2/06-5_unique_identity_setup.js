const { getChainId } = require('hardhat');
const { networks } = require('../../networks');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { execute, get } = deployments;
  const { deployer } = await getNamedAccounts();

  await execute(
    'UniqueIdentity',
    {
      from: deployer,
      log: true,
    },
    'setSupportedUIDTypes',
    [0, 1, 2, 3],
    [true, true, true, true]
  );

  await execute(
    'SecuritizationManager',
    {
      from: deployer,
      log: true,
    },
    'setAllowedUIDTypes',
    [0, 1, 2, 3]
  );
};

module.exports.dependencies = ['registry', 'securitization_manager', 'unique_identity'];
module.exports.tags = ['mainnet', 'unique_identity_setup'];
