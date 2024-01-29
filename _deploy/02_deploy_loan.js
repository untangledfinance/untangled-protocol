const { deployProxy } = require('../utils/deployHelper');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, execute, get, save } = deployments;
  const { deployer, invoiceOperator } = await getNamedAccounts();
  const registry = await get('Registry');

  //deploy AcceptedInvoiceToken
  const acceptedInvoiceTokenProxy = await deployProxy(
    { getNamedAccounts, deployments },
    'AcceptedInvoiceToken',
    [registry.address, 'Accepted Invoice Token', 'AIT', ''],
    'initialize(address,string,string,string)'
  );
  if (acceptedInvoiceTokenProxy.newlyDeployed) {
    await execute(
      'Registry',
      { from: deployer, log: true },
      'setAcceptedInvoiceToken',
      acceptedInvoiceTokenProxy.address
    );
    await execute(
      'AcceptedInvoiceToken',
      { from: deployer, log: true },
      'grantRole',
      ...['0xcbbd203e90d3debc831e0cae56984cdf139ab8c0dbca5f46a4f8684496e0d14d', invoiceOperator]
    );
  }

  //deploy LoanKernel
  const loanKernelProxy = await deployProxy({ getNamedAccounts, deployments }, 'LoanKernel', [registry.address]);
  if (loanKernelProxy.newlyDeployed) {
    await execute('Registry', { from: deployer, log: true }, 'setLoanKernel', loanKernelProxy.address);
  }


  //deploy LoanAssetToken
  const loanAssetTokenProxy = await deployProxy(
    { getNamedAccounts, deployments },
    'LoanAssetToken',
    [registry.address, 'Loan Asset Token', 'LAT', ''],
    'initialize(address,string,string,string)'
  );
  if (loanAssetTokenProxy.newlyDeployed) {
    await execute('Registry', { from: deployer, log: true }, 'setLoanAssetToken', loanAssetTokenProxy.address);
  }

  //deploy LoanRegistry
  const loanRegistryProxy = await deployProxy({ getNamedAccounts, deployments }, 'LoanRegistry', [registry.address]);
  if (loanRegistryProxy.newlyDeployed) {
    await execute('Registry', { from: deployer, log: true }, 'setLoanRegistry', loanRegistryProxy.address);
  }

  //deploy LoanRepaymentRouter
  const loanRepaymentRouterProxy = await deployProxy({ getNamedAccounts, deployments }, 'LoanRepaymentRouter', [
    registry.address,
  ]);
  if (loanRepaymentRouterProxy.newlyDeployed) {
    await execute(
      'Registry',
      { from: deployer, log: true },
      'setLoanRepaymentRouter',
      loanRepaymentRouterProxy.address
    );
  }

  //deploy LoanInterestTermsContract
  const loanInterestTermsContractProxy = await deployProxy(
    { getNamedAccounts, deployments },
    'LoanInterestTermsContract',
    [registry.address]
  );
  if (loanInterestTermsContractProxy.newlyDeployed) {
    await execute(
      'Registry',
      { from: deployer, log: true },
      'setLoanInterestTermsContract',
      loanInterestTermsContractProxy.address
    );
  }
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['loan', 'core'];
