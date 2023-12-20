const { expect } = require('chai');
const { networks } = require('../networks');

// test

/**
 * proxyAdmin=0xCB8aDbfdFA11529F69b199fE9779ec19c54fFc8f 
 * adminSigner=0xc52a72eddca008580b4efc89ea9f343aff11fea3
 * poolAddress=0x747076ed901dc145b4f3b3c3268014c86bab3d18
 * poolAddressTemplate=new template
 * 
 */
task('upgrade-securitization-pool', 'Deploy Securitization Pool')
  .addParam('proxyAdmin', 'proxyAdmin')
  .addParam('adminSigner', 'adminSigner')
  .addParam('poolAddress', 'poolAddress')
  .addParam('poolAddressTemplate', 'poolAddressTemplate')
  .setAction(async (taskArgs, hre) => {
    const { deployments, ethers } = hre;

    const untangledAdminSigner = await ethers.getSigner(taskArgs.adminSigner);

    const proxyAdmin = await ethers.getContractAt('ProxyAdmin', taskArgs.proxyAdmin);
    await proxyAdmin.connect(untangledAdminSigner)
      .upgrade(taskArgs.poolAddress, taskArgs.poolAddressTemplate);

    console.log(`Pool ${taskArgs.poolAddress} upgraded to ${taskArgs.poolAddressTemplate}`);
  });