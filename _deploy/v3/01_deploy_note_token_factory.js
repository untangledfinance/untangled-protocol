const { getChainId } = require('hardhat');
const { registrySet } = require('./utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, read, execute, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const registry = await deployments.get('Registry');
  const proxyAdmin = await get('DefaultProxyAdmin');

  await deployments.deploy('NoteTokenFactory', {
    from: deployer,
    proxy: {
      proxyContract: "OpenZeppelinTransparentProxy",
    },
    log: true,
  });

  const currentVersion = await read('NoteTokenFactory', {}, 'getInitializedVersion');
  if (currentVersion.toNumber() < 3) {
    await execute('NoteTokenFactory', {
      from: deployer,
      log: true,
    }, 'initialize', registry.address, proxyAdmin.address);
  }

  // await execute('NoteTokenFactory', {
  //   from: deployer,
  //   log: true,
  // }, 'initialize', registry.address, proxyAdmin.address);

  await registrySet(['NoteTokenFactory']);

};

module.exports.dependencies = ['registry'];
module.exports.tags = ['v3', 'NoteTokenFactory'];
