const { getChainId } = require('hardhat');
const { deployProxy } = require('../utils/deployHelper');
const { networks } = require('../networks');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { readDotFile, deploy, execute, get, save } = deployments;
  const { deployer } = await getNamedAccounts();

  if (['sepolia', 'ether'].includes(network.name)) {
    await deployments.deploy('UntangledSender', {
      from: deployer,
      proxy: {
        proxyContract: 'OpenZeppelinTransparentProxy',
        execute: {
          methodName: 'initialize',
          args: [networks[network.name].router, networks[network.name].linkToken],
        },
      },
    });
  }
};

module.exports.dependencies = [];
module.exports.tags = ['untangled_ccip_sender'];
