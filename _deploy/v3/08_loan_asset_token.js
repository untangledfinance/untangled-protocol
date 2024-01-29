const { deployProxy } = require('../../utils/deployHelper');
const { registrySet } = require('./utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { get, execute } = deployments;
  const { deployer } = await getNamedAccounts();

  const registry = await get('Registry');

  const loanAssetTokenProxy = await deployProxy(
    { getNamedAccounts, deployments },
    'LoanAssetToken',
    [registry.address, 'Loan Asset Token', 'LAT', ''],
    'initialize(address,string,string,string)'
  );

  if (loanAssetTokenProxy.newlyDeployed) {
    await execute('Registry', { from: deployer, log: true }, 'setLoanAssetToken', loanAssetTokenProxy.address);
  }
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['v3', 'mainnet', 'LoanAssetToken'];
