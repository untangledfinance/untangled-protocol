const { deployments, getNamedAccounts } = require('hardhat');

async function registrySet(contracts) {
  const { execute, get } = deployments;
  const { deployer } = await getNamedAccounts();

  for (let i = 0; i < contracts.length; i++) {
    const contract = contracts[i];

    const contractDeployment = await get(contract);

    await execute(
      'Registry',
      {
        from: deployer,
        log: true,
      },
      `set${contract}`,
      contractDeployment.address
    );
  }
}

module.exports = {
  registrySet,
};
