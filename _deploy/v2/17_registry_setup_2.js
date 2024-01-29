const { getChainId } = require('hardhat');
const { networks } = require('../../networks');
const { registrySet } = require('./utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const contracts = ['LoanAssetToken', 'AcceptedInvoiceToken'];

  await registrySet(contracts);
};

module.exports.dependencies = ['registry', 'loan_asset_token', 'accepted_invoice_token'];
module.exports.tags = ['mainnet', 'registry_setup_2'];
