const { deployProxy } = require('../deploy_v1/deployHelper');

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { execute } = deployments;
    const { deployer } = await getNamedAccounts();

    const registry = await deployments.get('Registry');

    const tokenURI = 'https://staging-api.untangled.finance/api/v3/assets/';

    const loanAssetTokenProxy = await deployProxy(
        { getNamedAccounts, deployments },
        'LoanAssetToken',
        [registry.address, 'Loan Asset Token', 'LAT', tokenURI],
        'initialize(address,string,string,string)'
    );

    await execute('Registry', { from: deployer, log: true }, 'setLoanAssetToken', loanAssetTokenProxy.address);
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['next', 'mainnet', 'LoanAssetToken'];
