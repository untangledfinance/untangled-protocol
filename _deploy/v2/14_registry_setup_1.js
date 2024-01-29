const { getChainId } = require('hardhat');
const { networks } = require('../../networks');
const { registrySet } = require('./utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const contracts = [
    'LoanInterestTermsContract',
    'LoanRegistry',
    'LoanKernel',
    'LoanRepaymentRouter',
    'DistributionAssessor',
    'DistributionOperator',
    'DistributionTranche',
    'SecuritizationPoolValueService',
  ];

  await registrySet(contracts);
};

module.exports.dependencies = [
  'registry',
  'securitization_pool_value_service',
  'loan_interest_term_contract',
  'loan_kernel',
  'loan_registry',
  'loan_repayment_router',
  'distribution_accessor',
  'distribution_operator',
  'distribution_tranche',
];
module.exports.tags = ['mainnet', 'registry_setup_1'];
