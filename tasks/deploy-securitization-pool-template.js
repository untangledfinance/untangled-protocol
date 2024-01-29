const { expect } = require('chai');
const { networks } = require('../networks');


const initPool = async (securitizationPoolImpl) => {
  // SecuritizationAccessControl,
  // SecuritizationPoolStorage,
  // SecuritizationTGE,
  // SecuritizationPoolAsset,
  // SecuritizationLockDistribution
  console.log('Deploy SecuritizationAccessControl, SecuritizationPoolStorage, SecuritizationTGE, SecuritizationPoolAsset, SecuritizationLockDistribution');
  const SecuritizationAccessControl = await ethers.getContractFactory('SecuritizationAccessControl');
  const securitizationAccessControlImpl = await SecuritizationAccessControl.deploy();
  await securitizationAccessControlImpl.deployed();
  console.log('Deploy SecuritizationAccessControl', securitizationAccessControlImpl.address);
  const tx1 = await securitizationPoolImpl.registerExtension(securitizationAccessControlImpl.address);
  await tx1.wait();
  console.log('Registered SecuritizationAccessControl', tx1.hash);

  const SecuritizationPoolStorage = await ethers.getContractFactory('SecuritizationPoolStorage');
  const securitizationPoolStorageImpl = await SecuritizationPoolStorage.deploy();
  await securitizationPoolStorageImpl.deployed();
  const tx2 = await securitizationPoolImpl.registerExtension(securitizationPoolStorageImpl.address);
  await tx2.wait();
  console.log('Registered SecuritizationPoolStorage', tx2.hash);

  const SecuritizationPoolTGE = await ethers.getContractFactory('SecuritizationTGE');
  const securitizationPoolTGEImpl = await SecuritizationPoolTGE.deploy();
  await securitizationPoolTGEImpl.deployed();
  console.log('Deploy securitizationPoolTGE', securitizationPoolTGEImpl.address);
  const tx3 = await securitizationPoolImpl.registerExtension(securitizationPoolTGEImpl.address);
  await tx3.wait();
  console.log('Registered SecuritizationPoolTGE', tx3.hash);

  const SecuritizationPoolAsset = await ethers.getContractFactory('SecuritizationPoolAsset');
  const securitizationPoolAssetImpl = await SecuritizationPoolAsset.deploy();
  await securitizationPoolAssetImpl.deployed();
  console.log('Deploy securitizationPoolAsset', securitizationPoolAssetImpl.address);
  const tx4 = await securitizationPoolImpl.registerExtension(securitizationPoolAssetImpl.address);
  await tx4.wait();
  console.log('Registered SecuritizationPoolAsset', tx4.hash);

  const SecuritizationLockDistribution = await ethers.getContractFactory('SecuritizationLockDistribution');
  const securitizationLockDistributionImpl = await SecuritizationLockDistribution.deploy();
  await securitizationLockDistributionImpl.deployed();
  console.log('Deploy securitizationLockDistributionImpl', securitizationLockDistributionImpl.address);
  const tx5 = await securitizationPoolImpl.registerExtension(securitizationLockDistributionImpl.address);
  await tx5.wait();
  console.log('Registered SecuritizationLockDistribution', tx5.hash);

  return securitizationPoolImpl;
};

task('deploy-securitization-pool-template', 'Deploy Securitization Pool').setAction(async (taskArgs, hre) => {
  const { deployments, ethers } = hre;
  const { get, read } = deployments;

  // deploy script
  const SecuritizationPool = await ethers.getContractFactory('SecuritizationPool');
  const securitizationPoolImpl = await SecuritizationPool.deploy();

  await initPool(securitizationPoolImpl);

  console.log(`Pool template ${securitizationPoolImpl.address} deployed`);
});