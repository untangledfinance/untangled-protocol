module.exports = async ({ getNamedAccounts, deployments }) => {
    const { get, execute, deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const tgeNormal = await deploy('MintedNormalTGE', {
        from: deployer,
        log: true,
    });

    await execute(
        'TokenGenerationEventFactory',
        {
            from: deployer,
            log: true,
        },
        'setTGEImplAddress',
        0,
        tgeNormal.address
    );

    await execute(
        'TokenGenerationEventFactory',
        {
            from: deployer,
            log: true,
        },
        'setTGEImplAddress',
        1,
        tgeNormal.address
    );
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['next', 'mainnet', 'MintedNormalTGE'];
