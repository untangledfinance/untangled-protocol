module.exports = async ({ getNamedAccounts, deployments }) => {
  const { readDotFile, deploy, execute, get, save } = deployments;
  const { deployer } = await getNamedAccounts();

  const contractDeployment = await get('SecuritizationPool');

  await execute(
    'DefaultProxyAdmin',
    {
      from: deployer,
      log: true,
    },
    'upgrade',
    '0x_securitization_pool_proxy',
    contractDeployment.address
  );
};

module.exports.dependencies = [];
module.exports.tags = ['securitization_pool_migration'];
