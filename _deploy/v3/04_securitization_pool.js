const { registrySet } = require('./utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, get } = deployments;
  const { deployer } = await getNamedAccounts();

  await deployments.deploy('SecuritizationPool', {
    from: deployer,
    // proxy: {
    //   // execute: {
    //   //   onUpgrade: {
    //   //     methodName: 'initializeV7',
    //   //     args: [registry.address, proxyAdmin.address],
    //   //   },
    //   // },
    //   proxyContract: "OpenZeppelinTransparentProxy",
    // },
    log: true,
  });

  await registrySet(['SecuritizationPool']);
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['v3', 'mainnet', 'SecuritizationPool'];
