//deploy LoanKernel

const { deployProxy } = require('../../utils/deployHelper');
const { registrySet } = require('../v2/utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { get, execute } = deployments;
    const { deployer } = await getNamedAccounts();

    const registry = await get('Registry');

    const loanKernelProxy = await deployments.deploy('LoanKernel', {
        from: deployer,
        proxy: {
            proxyContract: 'OpenZeppelinTransparentProxy',
        },
        skipIfAlreadyDeployed: true,
        log: true,
    });
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['v4', 'mainnet', 'LoanKernel'];
