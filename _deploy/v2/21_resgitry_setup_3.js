const { getChainId } = require('hardhat');
const { networks } = require('../../networks');
const { registrySet } = require('./utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const contracts = [
    'SecuritizationPool',
    // 'MintedIncreasingInterestTGE',
    // 'MintedNormalTGE',
    'SecuritizationManager',
    'NoteTokenFactory',
    'TokenGenerationEventFactory',
    'Go',
  ];

  await registrySet(contracts);
};

module.exports.dependencies = [
  'registry',
  'securitization_manager',
  'note_token_factory',
  'token_generation_event_factory',
  'go',
  'securitization_pool_impl',
  'minted_increasing_interest_tge_impl',
  'minted_normal_tge_impl',
];
module.exports.tags = ['mainnet', 'resgitry_setup_3'];
