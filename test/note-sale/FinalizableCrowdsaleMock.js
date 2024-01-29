const { ethers, upgrades } = require('hardhat');
const { setup, initPool } = require('../setup');
// const { BigNumber } = require('ethers');
// const { keccak256 } = require('@ethersproject/keccak256');
const { impersonateAccount, setBalance } = require('@nomicfoundation/hardhat-network-helpers');
const { parseEther } = ethers.utils;
const { utils } = require('ethers');
const { POOL_ADMIN_ROLE } = require('../constants');
const { getPoolByAddress } = require('../utils');
const UntangledProtocol = require('../shared/untangled-protocol');

// const ONE_DAY = 86400;
// const DECIMAL = BigNumber.from(10).pow(18);

describe('FinalizableCrowdsaleMock', () => {
  let registry;
  let securitizationPool;
  let finalizableCrowdSale;
  let stableCoin;
  let untangledProtocol;

  before('create fixture', async () => {
    const [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer] =
      await ethers.getSigners();

    const contracts = await setup();
    untangledProtocol = UntangledProtocol.bind(contracts);
    ({ registry, stableCoin, securitizationManager } = contracts);

    const OWNER_ROLE = await securitizationManager.OWNER_ROLE();
    await securitizationManager.grantRole(OWNER_ROLE, borrowerSigner.address);
    await securitizationManager.setRoleAdmin(POOL_ADMIN_ROLE, OWNER_ROLE);
    await securitizationManager.connect(borrowerSigner).grantRole(POOL_ADMIN_ROLE, poolCreatorSigner.address);

    const securitizationPoolAddress = await untangledProtocol.createSecuritizationPool(poolCreatorSigner);
    securitizationPool = await getPoolByAddress(securitizationPoolAddress);



    const NoteToken = await ethers.getContractFactory('NoteToken');
    const noteToken = await upgrades.deployProxy(NoteToken, ['Test', 'TST', 18, securitizationPool.address, 1], {
      initializer: 'initialize(string,string,uint8,address,uint8)',
    });
    const currencyAddress = await securitizationPool.underlyingCurrency();

    const finalizableCrowdsaleMock = await ethers.getContractFactory('FinalizableCrowdsaleMock');
    finalizableCrowdSale = await finalizableCrowdsaleMock.deploy();
    finalizableCrowdSale.initialize(registry.address, securitizationPool.address, noteToken.address, currencyAddress);
  });

  it('#finalize', async () => {
    await impersonateAccount(securitizationPool.address);
    await setBalance(securitizationPool.address, ethers.utils.parseEther('1'));
    const signer = await ethers.getSigner(securitizationPool.address);

    await finalizableCrowdSale.connect(signer).finalize(false, signer.address);
  });
});
