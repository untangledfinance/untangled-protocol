const { getChainId } = require('hardhat');
const { networks } = require('../../networks');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, execute, get } = deployments;
  const { deployer } = await getNamedAccounts();

  await deployments.deploy('MintedIncreasingInterestTGE', {
    from: deployer,
    args: [],
    log: true,
  });
};

module.exports.dependencies = [];
module.exports.tags = ['mainnet', 'minted_increasing_interest_tge_impl'];
