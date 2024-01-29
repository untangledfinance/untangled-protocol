const { getChainId } = require('hardhat');
const { registrySet } = require('./utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, get, execute } = deployments;
  const { deployer } = await getNamedAccounts();

  // const deployResult = await deploy('NoteToken', {
  //   from: deployer,
  //   skipIfAlreadyDeployed: true,
  //   args: [],
  //   log: true,
  // });

  const NoteToken = await get('NoteToken');
  // if (deployResult.newlyDeployed) {
    await execute(
      'NoteTokenFactory',
      {
        from: deployer,
        log: true,
      },
      `setNoteTokenImplementation`,
      NoteToken.address,
    );

    const contracts = ['NoteTokenFactory'];
    await registrySet(contracts);
  // }
};

module.exports.dependencies = ['registry', 'NoteTokenFactory'];
module.exports.tags = ['v3', 'mainnet', 'NoteToken'];
