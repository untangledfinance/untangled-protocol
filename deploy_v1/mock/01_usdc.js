const { getChainId } = require('hardhat');
const { deployProxy } = require('../../utils/deployHelper');

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, execute, get } = deployments;
    const { deployer } = await getNamedAccounts();

    await deployProxy(
        { getNamedAccounts, deployments },
        'MockERC20Upgradeable',
        ['USDC', 'USDC', 6],
        'initialize(string,string,uint8)',
        'USDC'
    );
};

module.exports.dependencies = [];
module.exports.tags = ['mock', 'usdc'];
