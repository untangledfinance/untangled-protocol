module.exports = async ({ getNamedAccounts, deployments }) => {
    const { get, execute, deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const tgeInterest = await deploy('MintedIncreasingInterestTGE', {
        from: deployer,
        log: true,
    });

    // // if (tgeInterest.newlyDeployed) {
    await execute(
        'TokenGenerationEventFactory',
        {
            from: deployer,
            log: true,
        },
        'setTGEImplAddress',
        0,
        tgeInterest.address
    );
    // // }
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['next', 'mainnet', 'MintedIncreasingInterestTGE'];
