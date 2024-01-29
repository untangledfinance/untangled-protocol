const { getChainId } = require('hardhat');

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    await deployments.deploy('Registry', {
        from: deployer,
        proxy: {
            proxyContract: 'OpenZeppelinTransparentProxy',
        },
        log: true,
    });
};

module.exports.dependencies = [];
module.exports.tags = ['v4', 'mainnet', 'registry'];
