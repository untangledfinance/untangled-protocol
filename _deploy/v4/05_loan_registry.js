//deploy LoanKernel

const { deployProxy } = require('../../utils/deployHelper');

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { get, execute } = deployments;
    const { deployer } = await getNamedAccounts();

    await deployments.deploy('LoanRegistry', {
        from: deployer,
        proxy: {
            proxyContract: 'OpenZeppelinTransparentProxy',
        },
        log: true,
    });
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['v4', 'mainnet', 'LoanRegistry'];
