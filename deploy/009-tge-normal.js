module.exports = async ({ getNamedAccounts, deployments }) => {
    const { get, execute, deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const tgeNormal = await deploy('MintedNormalTGE', {
        from: deployer,
        log: true,
    });

    // if (tgeNormal.newlyDeployed) {
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

    await execute(
        'TokenGenerationEventFactory',
        {
            from: deployer,
            log: true,
        },
        'setTGEImplAddress',
        2,
        tgeNormal.address
    );
    // }
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['next', 'mainnet', 'MintedNormalTGE'];
