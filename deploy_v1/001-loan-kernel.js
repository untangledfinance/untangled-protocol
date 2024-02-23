//deploy LoanKernel

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { get, execute, deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const registry = await get('Registry');

    const loanKernelProxy = await deploy('LoanKernel', {
        from: deployer,
        proxy: {
            proxyContract: 'OpenZeppelinTransparentProxy',
            execute: {
                init: {
                    methodName: 'initialize',
                    args: [registry.address],
                },
            },
        },
        log: true,
    });

    await execute('Registry', { from: deployer, log: true }, 'setLoanKernel', loanKernelProxy.address);
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['next', 'mainnet', 'LoanKernel'];
