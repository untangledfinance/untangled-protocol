const { ethers, upgrades } = require('hardhat');

async function main() {
    const registryAddress = '0xD9a530aFf568b9537f2292dDa2fb59ab213f56E8';
    // const noteTokenVaultAddress = '0x802D2C0EA6c20943730ba94Cba16703d7470F30c';
    // const registry = await ethers.getContractAt('Registry', registryAddress);

    // console.log(
    //     `isWhitelistedTo: `,
    //     await registry.isValidNoteTokenTransfer(noteTokenVaultAddress, noteTokenVaultAddress)
    // );
    const RegistryImp = await ethers.getContractFactory('Registry');
    const registry = await upgrades.upgradeProxy(registryAddress, RegistryImp);
}
main();
