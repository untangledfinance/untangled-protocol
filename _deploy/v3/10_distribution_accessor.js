
module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, execute, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const registry = await get('Registry');

  const deployResult = await deploy('DistributionAssessor', {
    from: deployer,
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
      execute: {
        methodName: 'initialize',
        args: [registry.address],
      },
    },
    skipIfAlreadyDeployed: true,
    log: true,
  });

  await execute('Registry', { from: deployer, log: true }, 'setDistributionAssessor', deployResult.address);
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['mainnet', 'DistributionAccessor', 'next'];