const { getChainId } = require('hardhat');
const { deployProxy } = require('../utils/deployHelper');
const { networks } = require('../networks');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { readDotFile, deploy, execute, get, save } = deployments;
  const { deployer } = await getNamedAccounts();

  if (['mumbai', 'polygon'].includes(network.name)) {
    let tx = await deployments.deploy('UntangledBridgeRouter', {
      from: deployer,
      proxy: {
        proxyContract: 'OpenZeppelinTransparentProxy',
        execute: {
          methodName: 'initialize',
          args: [deployer],
        },
      },
    });

    const untangledBridgeRouter = await deployments.get('UntangledBridgeRouter');

    await deployments.deploy('UntangledReceiver', {
      from: deployer,
      proxy: {
        proxyContract: 'OpenZeppelinTransparentProxy',
        execute: {
          methodName: 'initialize',
          args: [networks[network.name].router, untangledBridgeRouter.address],
        },
      },
      gasLimit: 2000000,
    });

    const untangledReceiver = await deployments.get('UntangledReceiver');

    const CCIP_RECEIVER_ROLE = await deployments.read('UntangledBridgeRouter', 'CCIP_RECEIVER_ROLE');
    await deployments.execute(
      'UntangledBridgeRouter',
      {
        from: deployer,
        gasLimit: 2000000,
      },
      'grantRole',
      CCIP_RECEIVER_ROLE,
      untangledReceiver.address
    );
  }
};

module.exports.dependencies = [];
module.exports.tags = ['untangled_ccip_receiver'];
