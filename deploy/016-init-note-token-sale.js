module.exports = async ({ getNamedAccounts, deployments }) => {
    const { execute } = deployments;
    const { deployer } = await getNamedAccounts();

    await execute(
        'SecuritizationManager',
        { from: deployer, log: true },
        'setupNoteTokenSale',
        network.config.pool,
        0,
        0,
        2,
        'SOT_'
    );

    await execute(
        'SecuritizationManager',
        { from: deployer, log: true },
        'setupNoteTokenSale',
        network.config.pool,
        1,
        0,
        0,
        'JOT_'
    );
};

module.exports.tags = ['InitNoteTokenSale'];
