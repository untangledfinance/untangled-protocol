const { getChainId } = require('hardhat');
const { networks } = require('../../networks');
const { deployProxy } = require('../../utils/deployHelper');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, execute, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const registry = await deployments.get('Registry');

  const token = await deployProxy(
    { getNamedAccounts, deployments },
    'AcceptedInvoiceToken',
    [registry.address, 'Accepted Invoice Token', 'AIT', ''],
    'initialize(address,string,string,string)'
  );

  await execute('Registry', { from: deployer, log: true }, 'setAcceptedInvoiceToken', token.address);
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['mainnet', 'AcceptedInvoiceToken', 'v3'];
