const { networks } = require('../../networks');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { readDotFile, deploy, execute, get, save } = deployments;
  const { deployer } = await getNamedAccounts();

  await deployments.deploy('UntangledReceiver', {
    from: deployer,
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
    },
  });
};

module.exports.dependencies = [];
module.exports.tags = ['untangled_ccip_receiver_migration'];
