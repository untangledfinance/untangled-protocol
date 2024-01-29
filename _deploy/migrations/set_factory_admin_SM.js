module.exports = async ({ getNamedAccounts, deployments }) => {
  const { readDotFile, deploy, execute, get, save } = deployments;
  const { deployer } = await getNamedAccounts();

  const proxyAdmin = await get('DefaultProxyAdmin');

  await execute(
    'SecuritizationManager',
    {
      from: deployer,
      log: true,
    },
    'setFactoryAdmin',
    proxyAdmin.address
  );
};

module.exports.dependencies = [];
module.exports.tags = ['set_factory_admin_SM'];
