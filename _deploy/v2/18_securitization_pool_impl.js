const { getChainId } = require('hardhat');
const { networks } = require('../../networks');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, execute, get } = deployments;
  const { deployer } = await getNamedAccounts();

  await deployments.deploy('SecuritizationPool', {
    from: deployer,
    args: [],
    log: true,
  });
};

module.exports.dependencies = [];
module.exports.tags = ['mainnet', 'securitization_pool_impl'];
