const { getChainId } = require('hardhat');
const { networks } = require('../../networks');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, execute, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const registry = await deployments.get('Registry');

  await deployments.deploy('LoanInterestTermsContract', {
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
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['mainnet', 'LoanInterestTermContract', 'v3'];
