const { getChainId } = require('hardhat');
const { registrySet } = require('../utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, execute, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const registry = await get('Registry');

  const contracts = [
    'LoanInterestTermsContract',
    'LoanRegistry',
    'LoanKernel',
    'LoanRepaymentRouter',
    'DistributionAssessor',
    'DistributionOperator',
    'DistributionTranche',
    'SecuritizationPoolValueService',
    'LoanAssetToken',
    'AcceptedInvoiceToken',
    'SecuritizationPool',
    'MintedIncreasingInterestTGE',
    'MintedNormalTGE',
    'SecuritizationManager',
    'NoteTokenFactory',
    'TokenGenerationEventFactory',
    'Go',
  ];

  await registrySet(contracts);
};

module.exports.dependencies = [];
module.exports.tags = ['migration_mumbai', 'registry_setup_mumbai_migration'];
