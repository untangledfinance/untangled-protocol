//deploy LoanKernel

const { deployProxy } = require('../../utils/deployHelper');

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { get, execute } = deployments;
    const { deployer } = await getNamedAccounts();

    const registry = await get('Registry');
    const loanAssetTokenProxy = await deployProxy(
        { getNamedAccounts, deployments },
        'LoanAssetToken',
        [registry.address, 'Loan Asset Token', 'LAT', ''],
        'initialize(address,string,string,string)'
    );
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['v4', 'mainnet', 'LoanAssetToken'];
