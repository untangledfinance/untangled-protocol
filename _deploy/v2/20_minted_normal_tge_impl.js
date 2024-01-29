const { getChainId } = require('hardhat');
const { networks } = require('../../networks');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, execute, get } = deployments;
  const { deployer } = await getNamedAccounts();

  await deployments.deploy('MintedNormalTGE', {
    from: deployer,
    args: [],
    log: true,
  });
};

module.exports.dependencies = [];
module.exports.tags = ['mainnet', 'minted_normal_tge_impl'];
