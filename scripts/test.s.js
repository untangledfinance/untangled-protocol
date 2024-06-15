const { ethers, upgrades } = require('hardhat');

async function main() {
    const registryAddress = '0x46E43cB8d708E5714DA929845E00Fc2757851b29';
    const noteTokenVaultAddress = '0x608a8C14DE2085f98D931F6562a5D774dE40B91B';
    const poolAddress = '0x6621Ca4B5988b21E14582bFdda9C9CF8770A5f92';
    const user = '0xf60b11ba5312BF98845278eD98CfDa03e8f2C5Fa';
    const usdcAddress = '0xE3398bAB66b00F2e4ae551968b9A91D064186B66';
    const jotAddress = '0x4D4f58c1caAaA8210203648fcc203259721812CF';

    const noteTokenVault = await ethers.getContractAt('NoteTokenVault', noteTokenVaultAddress);
    const jotToken = await ethers.getContractAt('NoteToken', jotAddress);
    const usdc = await ethers.getContractAt('TestERC20', usdcAddress);
    const pool = await ethers.getContractAt('Pool', poolAddress);

    const potWallet = await pool.pot();
    // console.log('pot wallet: ', potWallet);
    // console.log('sot address: ', await pool.sotToken());
    // console.log('jot address: ', await pool.jotToken());
    // // console.log('prices: ', await pool.calcTokenPrices());
    // console.log('tge address: ', await pool.tgeAddress());
    // console.log('second tge address: ', await pool.secondTGEAddress());
    await noteTokenVault.executeOrders(poolAddress, [
        {
            user: user,
            sotIncomeClaimAmount: 0,
            jotIncomeClaimAmount: 0,
            sotCapitalClaimAmount: 0,
            jotCapitalClaimAmount: 500000000,
        },
    ]);
}
main();
