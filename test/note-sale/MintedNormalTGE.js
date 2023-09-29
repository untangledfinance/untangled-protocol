const { artifacts } = require('hardhat');
const { setup } = require('../setup');
const { expect, assert } = require('chai');
const { BigNumber } = require('ethers');

const ONE_DAY = 86400;
const DECIMAL = BigNumber.from(10).pow(18);
describe('MintedNormalTGE', () => {
  let mintedNormalTGE;
  let registry;
  let securitizationPool;

  before('create fixture', async () => {
    const [poolTest] = await ethers.getSigners();
    ({ registry, noteTokenFactory } = await setup());
    const SecuritizationPool = await ethers.getContractFactory('SecuritizationPool');
    const MintedNormalTGE = await ethers.getContractFactory('MintedNormalTGE');
    const NoteToken = await ethers.getContractFactory('NoteToken');

    mintedNormalTGE = await MintedNormalTGE.deploy();
    securitizationPool = await SecuritizationPool.deploy();
    const currencyAddress = await securitizationPool.underlyingCurrency();
    const longSale = true;
    const noteToken = await upgrades.deployProxy(NoteToken, ['Test', 'TST', 18, securitizationPool.address, 1], {
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
});
