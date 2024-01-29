const { getChainId } = require('hardhat');
const { registrySet } = require('../utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const contracts = ['SecuritizationPool', 'MintedIncreasingInterestTGE', 'MintedNormalTGE'];

  await registrySet(contracts);
};

module.exports.dependencies = [
  'registry',
  'securitization_pool_impl',
  'minted_increasing_interest_tge_impl',
  'minted_normal_tge_impl',
];
module.exports.tags = ['migration_mumbai', 'resgitry_setup_3_mumbai_migration'];
