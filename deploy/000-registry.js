const { getChainId } = require('hardhat');

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    await deploy('Registry', {
        from: deployer,
        proxy: {
            proxyContract: 'OpenZeppelinTransparentProxy',
            execute: {
                init: {
                    methodName: 'initialize',
                    args: [],
                },
            },
        },
        log: true,
    });
};

module.exports.dependencies = [];
module.exports.tags = ['next', 'mainnet', 'Registry'];
