const { getChainId } = require('hardhat');
const { deployProxy } = require('../../../utils/deployHelper');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, execute, get } = deployments;
  const { deployer } = await getNamedAccounts();

  await deployProxy(
    { getNamedAccounts, deployments },
    'MockERC20Upgradeable',
    ['cUSD', 'cUSD', 18],
    'initialize(string,string,uint8)',
    'cUSD'
  );
};

module.exports.dependencies = [];
module.exports.tags = ['mock', 'cusd'];
