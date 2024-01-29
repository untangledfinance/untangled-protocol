//deploy LoanKernel




const { deployProxy } = require('../../utils/deployHelper');
const { registrySet } = require('./utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { get, execute } = deployments;
  const { deployer } = await getNamedAccounts();

  const registry = await get('Registry');

  const loanKernelProxy = await deployments.deploy('LoanKernel', {
    from: deployer,
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
      execute: {
        init: {
          methodName: 'initialize',
          args: [registry.address],
        }
      },
    },
    skipIfAlreadyDeployed: true,
    log: true,
  });

  if (loanKernelProxy.newlyDeployed) {
    await execute('Registry', { from: deployer, log: true }, 'setLoanKernel', loanKernelProxy.address);
  }
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['v3', 'mainnet', 'LoanKernel'];
