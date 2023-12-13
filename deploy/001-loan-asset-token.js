const { deployProxy } = require('./deployHelper');

// module.exports = async ({ getNamedAccounts, deployments }) => {
//     const { get, execute, deploy } = deployments;
//     const { deployer } = await getNamedAccounts();

//     const registry = await get('Registry');

//     const loanAssetToken = await deploy('LoanAssetToken', {
//         from: deployer,
//         proxy: {
//             proxyContract: 'OpenZeppelinTransparentProxy',
//             args: [registry.address, 'Loan Asset Token', 'LAT', ''],
//         },
//         log: true,
//     });

//     await execute('Registry', { from: deployer, log: true }, 'setLoanAssetToken', loanAssetToken.address);
// };

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, execute, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const registry = await deployments.get('Registry');

  const loanAssetToken = await deploy('LoanAssetToken', {
    from: deployer,
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
      execute: {
        init: {
          methodName: 'init',
          args: [registry.address, 'Loan Asset Token', 'LAT', ''],
        }
      },
    },
    log: true,
  });

  // const loanAssetTokenProxy = await deployProxy(
  //     { getNamedAccounts, deployments },
  //     'LoanAssetToken',
  //     [registry.address, 'Loan Asset Token', 'LAT', ''],
  //     'initialize(address,string,string,string)'
  // );

  console.log('loanAssetTokenProxy', loanAssetToken.address);

  await execute('Registry', { from: deployer, log: true }, 'setLoanAssetToken', loanAssetToken.address);
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['next', 'mainnet', 'LoanAssetToken'];
