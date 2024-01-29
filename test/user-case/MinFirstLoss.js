const { ethers } = require('hardhat');
const { expect } = require('chai');
const UntangledProtocol = require('../shared/untangled-protocol');
const { parseEther } = ethers.utils;

const dayjs = require('dayjs');
const { setup } = require('../setup');
const { POOL_ADMIN_ROLE } = require('../constants.js');
const { getPoolByAddress } = require('../utils');
const { SaleType } = require('../shared/constants.js');

describe('MinFirstLoss', () => {
  let stableCoin;
  let securitizationManager;
  let uniqueIdentity;
  let jotContract;
  let sotContract;
  let untangledProtocol;
  let securitizationPoolContract;
  let mintedIncreasingInterestTGEContract;
  let mintedNormalTGEContract;

  // Wallets
  let untangledAdminSigner,
    poolCreatorSigner,
    poolACreator,
    originatorSigner,
    lenderSigner,
    secondLenderSigner,
    relayer;

  const stableCoinAmountToBuyJOT = parseEther('1');
  const stableCoinAmountToBuySOT = parseEther('9');

  before('create fixture', async () => {
    // Init wallets
    [
      untangledAdminSigner,
      poolCreatorSigner,
      poolACreator,
      originatorSigner,
      lenderSigner,
      secondLenderSigner,
      relayer,
    ] = await ethers.getSigners();

    // Init contracts
    const contracts = await setup();
    untangledProtocol = UntangledProtocol.bind(contracts);
    ({ stableCoin, uniqueIdentity, securitizationManager } = contracts);

    await securitizationManager.grantRole(POOL_ADMIN_ROLE, poolCreatorSigner.address);

    const poolParams = {
      currency: 'cUSD',
      minFirstLossCushion: 10,
      validatorRequired: true,
      debtCeiling: 1000,
    };

    const oneDayInSecs = 1 * 24 * 3600;
    const halfOfADay = oneDayInSecs / 2;
    const riskScores = [{
      daysPastDue: oneDayInSecs,
      advanceRate: 950000,
      penaltyRate: 900000,
      interestRate: 910000,
      probabilityOfDefault: 800000,
      lossGivenDefault: 810000,
      gracePeriod: halfOfADay,
      collectionPeriod: halfOfADay,
      writeOffAfterGracePeriod: halfOfADay,
      writeOffAfterCollectionPeriod: halfOfADay,
      discountRate: 100000,
    }];

    const openingTime = dayjs(new Date()).unix();
    const closingTime = dayjs(new Date()).add(1, 'days').unix();
    const rate = 10000;
    const totalCapOfToken = parseEther('1000');
    const initialInterest = 10000;
    const finalInterest = 10000;
    const timeInterval = 1 * 24 * 3600; // seconds
    const amountChangeEachInterval = 0;
    const prefixOfNoteTokenSaleName = 'Ticker_';
    const sotInfo = {
      issuerTokenController: untangledAdminSigner.address,
      saleType: SaleType.MINTED_INCREASING_INTEREST,
      minBidAmount: parseEther('1'),
      openingTime,
      closingTime,
      rate,
      cap: totalCapOfToken,
      initialInterest,
      finalInterest,
      timeInterval,
      amountChangeEachInterval,
      ticker: prefixOfNoteTokenSaleName,
    };

    const initialJOTAmount = parseEther('1');
    const jotInfo = {
      issuerTokenController: untangledAdminSigner.address,
      minBidAmount: parseEther('1'),
      saleType: SaleType.NORMAL_SALE,
      longSale: true,
      ticker: prefixOfNoteTokenSaleName,
      openingTime: openingTime,
      closingTime: closingTime,
      rate: rate,
      cap: totalCapOfToken,
      initialJOTAmount,
    };
    const [poolAddress, sotCreated, jotCreated] = await untangledProtocol.createFullPool(poolCreatorSigner, poolParams, riskScores, sotInfo, jotInfo);
    securitizationPoolContract = await getPoolByAddress(poolAddress);
    mintedIncreasingInterestTGEContract = await ethers.getContractAt('MintedIncreasingInterestTGE', sotCreated.sotTGEAddress);
    mintedNormalTGEContract = await ethers.getContractAt('MintedIncreasingInterestTGE', jotCreated.jotTGEAddress);
    sotContract = await ethers.getContractAt('NoteToken', sotCreated.sotTokenAddress);
    jotContract = await ethers.getContractAt('NoteToken', jotCreated.jotTokenAddress);

    // Lender gain UID
    await untangledProtocol.mintUID(lenderSigner);

    // Faucet stable coin to lender/investor
    await stableCoin.transfer(lenderSigner.address, parseEther('10000')); // $10k
  });

  describe('Check min first loss when buying tokens', () => {
    it('should revert if try to buy SOT when total JOT supply is 0 (zero JOT was sold)', async () => {
      // Lender buys SOT
      await expect(
        untangledProtocol.buyToken(lenderSigner, mintedIncreasingInterestTGEContract.address, stableCoinAmountToBuySOT)
      ).to.be.revertedWith('Crowdsale: sale not started');
    });
    it('should revert if try to buy SOT with amount violates min first loss', async () => {
      // Lender buys JOT Token
      await stableCoin.connect(lenderSigner).approve(mintedNormalTGEContract.address, stableCoinAmountToBuyJOT);
      await securitizationManager
        .connect(lenderSigner)
        .buyTokens(mintedNormalTGEContract.address, stableCoinAmountToBuyJOT);
      // Lender try to buy SOT with amount violates min first loss
      const amountToBuySOT = stableCoinAmountToBuySOT.add(parseEther('1'));
      await stableCoin.connect(lenderSigner).approve(mintedIncreasingInterestTGEContract.address, amountToBuySOT);
      await expect(
        securitizationManager
          .connect(lenderSigner)
          .buyTokens(mintedIncreasingInterestTGEContract.address, amountToBuySOT)
      ).to.be.revertedWith('MinFirstLoss is not satisfied');
    });
    it('should buy SOT successfully if min first loss condition is satisfied', async () => {
      // Lender try to buy SOT with amount violates min first loss
      await untangledProtocol.buyToken(lenderSigner, mintedIncreasingInterestTGEContract.address, stableCoinAmountToBuySOT);
    });
  });
});
