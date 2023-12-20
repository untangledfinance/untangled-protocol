const { artifacts } = require('hardhat');
const { setup, initPool } = require('../setup');
const { expect, assert } = require('chai');
const { BigNumber, utils } = require('ethers');
const { POOL_ADMIN_ROLE } = require('../constants');
const { getPoolByAddress } = require('../utils');

// const ONE_DAY = 86400;
// const DECIMAL = BigNumber.from(10).pow(18);
describe('MintedNormalTGE', () => {
  let mintedNormalTGE;
  let registry;
  let securitizationPool;

  before('create fixture', async () => {
    ({ registry, noteTokenFactory, securitizationManager, stableCoin } = await setup());


    const [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer] =
      await ethers.getSigners();

    const [poolTest] = await ethers.getSigners();
    const SecuritizationPool = await ethers.getContractFactory('SecuritizationPool');
    const MintedNormalTGE = await ethers.getContractFactory('MintedNormalTGE');
    const NoteToken = await ethers.getContractFactory('NoteToken');

    mintedNormalTGE = await MintedNormalTGE.deploy();

    const currencyAddress = stableCoin.address; // await securitizationPool.underlyingCurrency();
    const longSale = true;
    const noteToken = await upgrades.deployProxy(NoteToken, ['Test', 'TST', 18, poolTest.address, 1], {
      initializer: 'initialize(string,string,uint8,address,uint8)',
    });

    await mintedNormalTGE.initialize(registry.address, poolTest.address, noteToken.address, currencyAddress, longSale);
  });

  it('Get isLongSale', async () => {
    assert.equal(await mintedNormalTGE.isLongSale(), true);
  });

  it('Set Yield', async () => {
    await mintedNormalTGE.setYield(20);
    assert.equal(await mintedNormalTGE.yield(), 20);
  });

  it('Setup LongSale', async () => {
    await mintedNormalTGE.setupLongSale(20, 86400, Math.trunc(Date.now() / 1000));
  });

  it('Setup newRoundSale', async () => {
    const openingTime = (await ethers.provider.getBlock("latest")).timestamp + 60; // Starts 1 minute from now

    const closingTime = openingTime + 3600; // Ends 1 hour after opening
    const rate = 100; // Your desired rate
    const cap = ethers.utils.parseEther('1000'); // Your desired cap in ether
    const [owner, securitizationManager, ...accounts] = await ethers.getSigners();

    // Only the owner (or pool) should be able to start a new round sale
    await expect(
      mintedNormalTGE
        .connect(accounts[0])
        .startNewRoundSale(openingTime, closingTime, rate, cap)
    ).to.be.revertedWith('MintedNormalTGE: Caller must be owner or manager');

    // The owner (or pool) should be able to start a new round sale
    await mintedNormalTGE
      .connect(owner)
      .startNewRoundSale(openingTime, closingTime, rate, cap);

    // Verify the new round sale parameters
    const _openTime = await mintedNormalTGE.openingTime(); // Replace with the correct function for fetching round info
    const _closingTime = await mintedNormalTGE.closingTime(); // Replace with the correct function for fetching round info
    const _rate = await mintedNormalTGE.rate(); // Replace with the correct function for fetching round info
    const _cap = await mintedNormalTGE.totalCap(); // Replace with the correct function for fetching round info
    expect(_openTime.toNumber()).to.equal(openingTime);
    expect(_closingTime.toNumber()).to.equal(closingTime);
    expect(_rate.toNumber()).to.equal(rate);
    expect(_cap).to.equal(cap);
  });

  it('Setup initialAmount', async () => {
    const expectedInitialAmount = 1000; // Replace with your desired initial amount

    await mintedNormalTGE.setInitialAmount(expectedInitialAmount);

    const actualInitialAmount = await mintedNormalTGE.initialAmount();
    expect(actualInitialAmount).to.equal(expectedInitialAmount);
  });
});
