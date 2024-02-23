module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, get, execute } = deployments;
    const { deployer } = await getNamedAccounts();

    const NoteToken = await deploy('NoteToken', {
        from: deployer,
        // skipIfAlreadyDeployed: true,
        args: [],
        log: true,
    });

    await execute(
        'NoteTokenFactory',
        {
            from: deployer,
            log: true,
        },
        `setNoteTokenImplementation`,
        NoteToken.address
    );
};

module.exports.dependencies = ['Registry', 'NoteTokenFactory'];
module.exports.tags = ['next', 'mainnet', 'NoteToken'];
