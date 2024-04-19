const { deployProxy } = require('./deployHelper');

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, execute, get } = deployments;
    const { deployer } = await getNamedAccounts();

    const registry = await deployments.get('Registry');

    // const tokenURI = 'https://staging-api.untangled.finance/api/v3/assets/';
    // const tokenURI = 'https://test-api.untangled.finance/api/v3/assets/';
    const tokenURI = 'https://api.untangled.finance/api/v3/assets/';

    const loanAssetTokenProxy = await deployProxy(
        { getNamedAccounts, deployments },
        'LoanAssetToken',
        [registry.address, 'Loan Asset Token', 'LAT', tokenURI],
        'initialize(address,string,string,string)'
    );
    // const loanAssetTokenProxy = await deployments.get('LoanAssetToken');
    // console.log('loanAssetTokenProxy', loanAssetTokenProxy.address);
    // await execute(
    //     'LoanAssetToken',
    //     { from: deployer, log: true },
    //     'setBaseURI',
    //     tokenURI
    // );

    // const Token = await ethers.getContractFactory('LoanAssetToken');
    // const token = await Token.attach(loanAssetTokenProxy.address);
    // const tokenURI = await token.tokenURI(
    //     '84279236014946466549278681696182247184601533423077762990928557906082942176381'
    // );
    // console.log('tokenURI', tokenURI);

    await execute('Registry', { from: deployer, log: true }, 'setLoanAssetToken', loanAssetTokenProxy.address);
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['next', 'mainnet', 'LoanAssetToken'];
