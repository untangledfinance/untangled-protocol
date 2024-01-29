module.exports = async ({ getNamedAccounts, deployments }) => {
  const { readDotFile, deploy, execute, get, save } = deployments;
  const { deployer } = await getNamedAccounts();

  await deployments.deploy('SecuritizationPool', {
    from: deployer,
    args: [],
    log: true,
  });
};

module.exports.dependencies = [];
module.exports.tags = ['securitization_pool_new_deployment'];
