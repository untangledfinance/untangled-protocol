const { getChainId } = require('hardhat');
const { deployProxy } = require('../utils/deployHelper');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { execute, deploy, readDotFile } = deployments;
  const { deployer } = await getNamedAccounts();

  const router = await readDotFile('.CHAINLINK_CCIP_ROUTER');
  const link = await readDotFile('.CHAINLINK_CCIP_LINK');

  const untangledSender = await deploy('UntangledSender', {
    args: [
      router,
      link
    ]
  });
};

module.exports.dependencies = [];
module.exports.tags = ['untangled_ccip_sender'];
