const { deployProxy } = require('../utils/deployHelper');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, execute, get, save } = deployments;
  const { deployer } = await getNamedAccounts();
  const registry = await get('Registry');
  const proxyAdmin = await get('DefaultProxyAdmin');

  //deploy MintedIncreasingInterestTGE
  const mintedIncreasingInterestTGEImpl = await deploy(`MintedIncreasingInterestTGEImpl`, {
    contract: 'MintedIncreasingInterestTGE',
    skipIfAlreadyDeployed: true,
    from: deployer,
    args: [],
    log: true,
  });
  // if (mintedIncreasingInterestTGEImpl.newlyDeployed) {
  //   const mintedIncreasingInterestTGE = mintedIncreasingInterestTGEImpl;
  //   mintedIncreasingInterestTGE.address = mintedIncreasingInterestTGEImpl.address;
  //   await save('MintedIncreasingInterestTGE', mintedIncreasingInterestTGE);
  //   await execute(
  //     'Registry',
  //     { from: deployer, log: true },
  //     'setMintedIncreasingInterestTGE',
  //     mintedIncreasingInterestTGEImpl.address
  //   );
  // }

  //deploy MintedNormalTGE
  // const mintedNormalTGEImpl = await deploy(`MintedNormalTGEImpl`, {
  //   contract: 'MintedNormalTGE',
  //   skipIfAlreadyDeployed: true,
  //   from: deployer,
  //   args: [],
  //   log: true,
  // });
  // if (mintedNormalTGEImpl.newlyDeployed) {
  //   const mintedNormalTGE = mintedNormalTGEImpl;
  //   mintedNormalTGE.address = mintedNormalTGEImpl.address;
  //   await save('MintedNormalTGE', mintedNormalTGE);
  //   await execute(
  //     'Registry',
  //     { from: deployer, log: true },
  //     'setMintedNormalTGE',
  //     mintedNormalTGEImpl.address
  //   );
  // }

  //deploy TokenGenerationEventFactory
  const tokenGenerationEventFactoryProxy = await deployProxy(
    { getNamedAccounts, deployments },
    'TokenGenerationEventFactory',
    [registry.address, proxyAdmin.address]
  );

  if (tokenGenerationEventFactoryProxy.newlyDeployed) {
    await execute(
      'Registry',
      { from: deployer, log: true },
      'setTokenGenerationEventFactory',
      tokenGenerationEventFactoryProxy.address
    );
  }
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['sale', 'core'];
