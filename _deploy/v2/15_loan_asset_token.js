const { getChainId } = require('hardhat');
const { networks } = require('../../networks');
const { deployProxy } = require('../../utils/deployHelper');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, execute, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const registry = await deployments.get('Registry');

  const loanAssetTokenProxy = await deployProxy(
    { getNamedAccounts, deployments },
    'LoanAssetToken',
    [registry.address, 'Loan Asset Token', 'LAT', ''],
    'initialize(address,string,string,string)'
  );
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['mainnet', 'loan_asset_token'];
