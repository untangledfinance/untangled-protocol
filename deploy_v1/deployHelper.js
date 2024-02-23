const deployProxy = async (hre, contractName, initParams, initSignature, contractSpecificName) => {
  const { getNamedAccounts, deployments } = hre;
  const { deploy, execute, get, save } = deployments;
  const { deployer } = await getNamedAccounts();

  const specificName = contractSpecificName || contractName;
  const contractImpl = await deploy(`${specificName}_Implementation`, {
    contract: contractName,
    // skipIfAlreadyDeployed: true,
    from: deployer,
    args: [],
    log: true,
  });

  const contractProxy = await deploy(`${specificName}_Proxy`, {
    contract: 'UpgradableProxy',
    skipIfAlreadyDeployed: true,
    from: deployer,
    args: [contractImpl.address],
    log: true,
  });

  if (contractProxy.newlyDeployed) {
    const contract = contractImpl;
    contract.address = contractProxy.address;
    await save(specificName, contract);
    await execute(specificName, { from: deployer, log: true }, initSignature || 'initialize', ...initParams);
  } else if (contractImpl.newlyDeployed) {
    await execute(`${specificName}_Proxy`, { from: deployer, log: true }, 'updateImplementation', contractImpl.address);
    const contract = contractImpl;
    contract.address = contractProxy.address;
    await save(specificName, contract);
  }

  return contractProxy;
};

module.exports = {
  deployProxy,
};
