const { registrySet } = require('./utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, get, execute, read } = deployments;
  const { deployer } = await getNamedAccounts();

  const registry = await deployments.get('Registry');
  const proxyAdmin = await get('DefaultProxyAdmin');

  await deployments.deploy('TokenGenerationEventFactory', {
    from: deployer,
    proxy: {
      // execute: {
      //   onUpgrade: {
      //     methodName: 'initializeV7',
      //     args: [registry.address, proxyAdmin.address],
      //   },
      // },
      proxyContract: "OpenZeppelinTransparentProxy",
    },
    log: true,
  });

  const currentVersion = await read('TokenGenerationEventFactory', {}, 'getInitializedVersion');
  console.log('current version:', currentVersion.toNumber());
  // if (currentVersion.toNumber() < 94) {

// await execute('TokenGenerationEventFactory', {
//     from: deployer,
//     log: true,
//   }, 'initialize', registry.address, proxyAdmin.address);
//   // }

  // await registrySet(['TokenGenerationEventFactory']);

};

module.exports.dependencies = ['registry'];
module.exports.tags = ['v3', 'mainnet', 'TokenGenerationEventFactory'];
