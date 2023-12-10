const { ethers, getChainId } = require('hardhat');
const { expect } = require('chai');
const { BigNumber, utils } = require('ethers');
const { parseEther } = ethers.utils;

const dayjs = require('dayjs');
const { time } = require('@nomicfoundation/hardhat-network-helpers');
const { setup } = require('../setup');
const { presignedMintMessage } = require('../shared/uid-helper');
const { POOL_ADMIN_ROLE, ORIGINATOR_ROLE, BACKEND_ADMIN } = require('../constants.js');
const { impersonateAccount, setBalance } = require('@nomicfoundation/hardhat-network-helpers');
const { getPoolByAddress, unlimitedAllowance } = require('../utils');
const { SaleType } = require('../shared/constants.js');

const ONE_DAY_IN_SECONDS = 86400;

describe('SecuritizationTranche', () => {
  let stableCoin;
  let securitizationManager;
  let uniqueIdentity;
  let jotContract;
  let sotContract;
  let securitizationPoolContract;
  let mintedNormalTGEContract;
  let mintedIncreasingInterestTGEContract;
  let loanKernel;

  // Wallets
  let untangledAdminSigner,
    poolCreatorSigner,
    poolACreator,
    originatorSigner,
    lenderSignerA,
    lenderSignerB,
    secondLenderSigner,
    backendAdminSigner,
    relayer;

  const stableCoinAmountToBuyJOT = parseEther('1');
  const stableCoinAmountToBuySOT = parseEther('1');

  before('create fixture', async () => {
    // Init wallets
    [
      untangledAdminSigner,
      poolCreatorSigner,
      poolACreator,
      originatorSigner,
      lenderSignerA,
      lenderSignerB,
      secondLenderSigner,
      relayer,
      backendAdminSigner
    ] = await ethers.getSigners();

    // Init contracts
    ({ stableCoin, uniqueIdentity, securitizationManager, loanKernel } = await setup());

    await securitizationManager.grantRole(POOL_ADMIN_ROLE, poolCreatorSigner.address);
    // Create new pool
    const transaction = await securitizationManager
      .connect(poolCreatorSigner)

      .newPoolInstance(
        utils.keccak256(Date.now()),

        poolCreatorSigner.address,
        utils.defaultAbiCoder.encode([
          {
            type: 'tuple',
            components: [
              {
                name: 'currency',
                type: 'address'
              },
              {
                name: 'minFirstLossCushion',
                type: 'uint32'
              },
              {
                name: 'validatorRequired',
                type: 'bool'
              },
              {
                name: 'debtCeiling',
                type: 'uint256',
              },

            ]
          }
        ], [
          {
            currency: stableCoin.address,
            minFirstLossCushion: '100000',
            validatorRequired: true,
            debtCeiling: parseEther('1000').toString(),
          }
        ]));

    const receipt = await transaction.wait();
    const [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;

    securitizationPoolContract = await getPoolByAddress(securitizationPoolAddress);

    // Grant role originator
    await securitizationPoolContract.connect(poolCreatorSigner).grantRole(ORIGINATOR_ROLE, originatorSigner.address);
    await securitizationPoolContract.connect(poolCreatorSigner).grantRole(BACKEND_ADMIN, backendAdminSigner.address);

    // Init JOT sale
    const jotCap = parseEther('1000'); // $1000
    const isLongSaleTGEJOT = true;
    const now = dayjs().unix();
    const initialJotAmount = stableCoinAmountToBuyJOT;

    const setUpTGEJOTTransaction = await securitizationManager.connect(poolCreatorSigner).setUpTGEForJOT(
      {
        issuerTokenController: poolCreatorSigner.address,
        pool: securitizationPoolContract.address,
        minBidAmount: parseEther('1'),
        saleType: SaleType.NORMAL_SALE,
        longSale: isLongSaleTGEJOT,
        ticker: 'Ticker',
      },
      {
        openingTime: now,
        closingTime: now + ONE_DAY_IN_SECONDS,
        rate: 10000,
        cap: jotCap,
      },
      initialJotAmount,
    );
    const setUpTGEJOTReceipt = await setUpTGEJOTTransaction.wait();
    const [jotTGEAddress] = setUpTGEJOTReceipt.events.find((e) => e.event == 'NewTGECreated').args;
    mintedNormalTGEContract = await ethers.getContractAt('MintedNormalTGE', jotTGEAddress);
    const jotAddress = await securitizationPoolContract.jotToken();
    jotContract = await ethers.getContractAt('NoteToken', jotAddress);

    // Init SOT sale
    const sotCap = parseEther('1000'); // $1000
    const isLongSaleTGESOT = true;
    const setUpTGESOTTransaction = await securitizationManager.connect(poolCreatorSigner).setUpTGEForSOT(
      {
        issuerTokenController: poolCreatorSigner.address,
        pool: securitizationPoolContract.address,
        minBidAmount: parseEther('1'),
        saleType: SaleType.MINTED_INCREASING_INTEREST,
        longSale: isLongSaleTGESOT,
        ticker: 'Ticker',
      },
      {
        openingTime: now,
        closingTime: now + 2 * ONE_DAY_IN_SECONDS,
        rate: 10000,
        cap: sotCap,
      },
      {
        initialInterest: 10000,
        finalInterest: 90000,
        timeInterval: 86400,
        amountChangeEachInterval: 10000,
      },
    );
    const setUpTGESOTReceipt = await setUpTGESOTTransaction.wait();
    const [sotTGEAddress] = setUpTGESOTReceipt.events.find((e) => e.event == 'NewTGECreated').args;
    mintedIncreasingInterestTGEContract = await ethers.getContractAt('MintedIncreasingInterestTGE', sotTGEAddress);
    const sotAddress = await securitizationPoolContract.sotToken();
    sotContract = await ethers.getContractAt('NoteToken', sotAddress);

    // Lender gain UID
    const UID_TYPE = 0;
    const chainId = await getChainId();
    const expiredAt = now + ONE_DAY_IN_SECONDS;
    const nonce = 0;
    const ethRequired = parseEther('0.00083');
    const uidMintMessage = presignedMintMessage(
      lenderSignerA.address,
      UID_TYPE,
      expiredAt,
      uniqueIdentity.address,
      nonce,
      chainId
    );
    const signature = await untangledAdminSigner.signMessage(uidMintMessage);
    await uniqueIdentity.connect(lenderSignerA).mint(UID_TYPE, expiredAt, signature, { value: ethRequired });

    const uidMintMessageLenderB = presignedMintMessage(
        lenderSignerB.address,
        UID_TYPE,
        expiredAt,
        uniqueIdentity.address,
        nonce,
        chainId
    );
    const signatureForLenderB = await untangledAdminSigner.signMessage(uidMintMessageLenderB);
    await uniqueIdentity.connect(lenderSignerB).mint(UID_TYPE, expiredAt, signatureForLenderB, { value: ethRequired });

    // Faucet stable coin to lender/investor
    await stableCoin.transfer(lenderSignerA.address, parseEther('10000')); // $10k
    await stableCoin.transfer(lenderSignerB.address, parseEther('10000')); // $10k
  });

  describe('Redeem Orders', () => {
    before('Lender A buy JOT and SOT', async () => {
      // Lender buys JOT Token
      await stableCoin.connect(lenderSignerA).approve(mintedNormalTGEContract.address, stableCoinAmountToBuyJOT);
      await securitizationManager
          .connect(lenderSignerA)
          .buyTokens(mintedNormalTGEContract.address, stableCoinAmountToBuyJOT);
      // Lender try to buy SOT with amount violates min first loss
      await stableCoin
        .connect(lenderSignerA)
        .approve(mintedIncreasingInterestTGEContract.address, stableCoinAmountToBuySOT);
      await securitizationManager
        .connect(lenderSignerA)
        .buyTokens(mintedIncreasingInterestTGEContract.address, stableCoinAmountToBuySOT);
    });
    before('Lender B buy JOT and SOT', async () => {
      // Lender buys JOT Token
      await stableCoin.connect(lenderSignerB).approve(mintedNormalTGEContract.address, stableCoinAmountToBuyJOT);
      await securitizationManager
          .connect(lenderSignerB)
          .buyTokens(mintedNormalTGEContract.address, stableCoinAmountToBuyJOT);
      // Lender try to buy SOT with amount violates min first loss
      await stableCoin
          .connect(lenderSignerB)
          .approve(mintedIncreasingInterestTGEContract.address, stableCoinAmountToBuySOT);
      await securitizationManager
          .connect(lenderSignerB)
          .buyTokens(mintedIncreasingInterestTGEContract.address, stableCoinAmountToBuySOT);
    });
    describe('Redeem Order', () => {
      it('Investor A should make redeem order for 1 JOT', async () => {
        await jotContract.connect(lenderSignerA).approve(securitizationPoolContract.address, unlimitedAllowance);
        await securitizationPoolContract.connect(lenderSignerA).redeemJOTOrder(parseEther('1'));
        const totalJOTRedeem = await securitizationPoolContract.totalJOTRedeem();
        expect(totalJOTRedeem).to.equal(parseEther('1'));
        const jotRedeemOrderLenderA = await securitizationPoolContract.userRedeemJOTOrder(lenderSignerA.address);
        expect(jotRedeemOrderLenderA).to.equal(parseEther('1'));
      });
      it('Investor A should change redeem order for 0.5 JOT', async () => {
        await securitizationPoolContract.connect(lenderSignerA).redeemJOTOrder(parseEther('0.5'));
        const totalJOTRedeem = await securitizationPoolContract.totalJOTRedeem();
        expect(totalJOTRedeem).to.equal(parseEther('0.5'));
        const jotRedeemOrderLenderA = await securitizationPoolContract.userRedeemJOTOrder(lenderSignerA.address);
        expect(jotRedeemOrderLenderA).to.equal(parseEther('0.5'));
        const jotLenderABalance = await jotContract.balanceOf(lenderSignerA.address);
        expect(jotLenderABalance).to.equal(parseEther('0.5'));
      });
      it('Investor B should make redeem order for 1 JOT', async () => {
        const jotLenderBBalance = await jotContract.balanceOf(lenderSignerB.address); // 1 jot
        await jotContract.connect(lenderSignerB).approve(securitizationPoolContract.address, jotLenderBBalance);
        await securitizationPoolContract.connect(lenderSignerB).redeemJOTOrder(parseEther('1'));

        const totalJOTRedeem = await securitizationPoolContract.totalJOTRedeem();
        expect(totalJOTRedeem).to.equal(parseEther('1.5'));
        const jotRedeemOrderLenderB = await securitizationPoolContract.userRedeemJOTOrder(lenderSignerB.address);
        expect(jotRedeemOrderLenderB).to.equal(parseEther('1'));
      });
      it('Investor A should make redeem order for 1 SOT', async () => {
        await sotContract.connect(lenderSignerA).approve(securitizationPoolContract.address, unlimitedAllowance);
        await securitizationPoolContract.connect(lenderSignerA).redeemSOTOrder(parseEther('1'));
        const totalSOTRedeem = await securitizationPoolContract.totalSOTRedeem();
        expect(totalSOTRedeem).to.equal(parseEther('1'));
        const sotRedeemOrderLenderA = await securitizationPoolContract.userRedeemSOTOrder(lenderSignerA.address);
        expect(sotRedeemOrderLenderA).to.equal(parseEther('1'));
      });
      it('Investor A should change redeem order for 0.5 SOT', async () => {
        await securitizationPoolContract.connect(lenderSignerA).redeemSOTOrder(parseEther('0.5'));
        const totalSOTRedeem = await securitizationPoolContract.totalSOTRedeem();
        expect(totalSOTRedeem).to.equal(parseEther('0.5'));
        const sotRedeemOrderLenderA = await securitizationPoolContract.userRedeemSOTOrder(lenderSignerA.address);
        expect(sotRedeemOrderLenderA).to.equal(parseEther('0.5'));
      });
      it('Investor B should make redeem order for 1 SOT', async () => {
        const sotLenderBBalance = await sotContract.balanceOf(lenderSignerB.address); // 1 sot
        await sotContract.connect(lenderSignerB).approve(securitizationPoolContract.address, sotLenderBBalance);
        await securitizationPoolContract.connect(lenderSignerB).redeemSOTOrder(parseEther('1'));

        const totalSOTRedeem = await securitizationPoolContract.totalSOTRedeem();
        expect(totalSOTRedeem).to.equal(parseEther('1.5'));
        const sotRedeemOrderLenderB = await securitizationPoolContract.userRedeemSOTOrder(lenderSignerB.address);
        expect(sotRedeemOrderLenderB).to.equal(parseEther('1'));
      });
      it('only pool creator can disable redeem request', async () => {
        await expect(securitizationPoolContract.connect(lenderSignerA).setRedeemDisabled(true)).to.be.revertedWith('AccessControl: caller is not an originator');
        await securitizationPoolContract.connect(backendAdminSigner).setRedeemDisabled(true);

      });
      it('should revert if request redemption when redeem disabled', async () => {
        await expect(
            securitizationPoolContract.connect(lenderSignerB).redeemJOTOrder(parseEther('1'))
        ).to.be.revertedWith('redeem-not-allowed');

        await expect(
            securitizationPoolContract.connect(lenderSignerB).redeemSOTOrder(parseEther('1'))
        ).to.be.revertedWith('redeem-not-allowed');

      });

      it('should revert if buy note token when redeem disabled', async () => {
        await stableCoin.connect(lenderSignerA).approve(mintedNormalTGEContract.address, stableCoinAmountToBuyJOT);
        await expect(securitizationManager
            .connect(lenderSignerA)
            .buyTokens(mintedNormalTGEContract.address, stableCoinAmountToBuyJOT))
            .to.be.revertedWith("SM: Buy token paused")
        // Lender try to buy SOT with amount violates min first loss
        await stableCoin
            .connect(lenderSignerA)
            .approve(mintedIncreasingInterestTGEContract.address, stableCoinAmountToBuySOT);
        expect(securitizationManager
            .connect(lenderSignerA)
            .buyTokens(mintedIncreasingInterestTGEContract.address, stableCoinAmountToBuySOT))
            .to.be.revertedWith("SM: Buy token paused")

      });
      it('should revert if drawdown when redeem disabled', async () => {
        await impersonateAccount(loanKernel.address);
        await setBalance(loanKernel.address, ethers.utils.parseEther('1'));
        const signer = await ethers.getSigner(loanKernel.address);
        await expect(
            securitizationPoolContract.connect(signer).withdraw(originatorSigner.address, parseEther('0.5'))
        ).to.be.revertedWith("SecuritizationPool: withdraw paused");

      });
      it('enable redeem order', async () => {
        await securitizationPoolContract.connect(backendAdminSigner).setRedeemDisabled(false);
      });
      it('Investor A should change redeem order for 1 JOT', async () => {
        await securitizationPoolContract.connect(lenderSignerA).redeemJOTOrder(parseEther('1'));
        const totalJOTRedeem = await securitizationPoolContract.totalJOTRedeem();
        expect(totalJOTRedeem).to.equal(parseEther('2'));
        const jotRedeemOrderLenderA = await securitizationPoolContract.userRedeemJOTOrder(lenderSignerA.address);
        expect(jotRedeemOrderLenderA).to.equal(parseEther('1'));
        const jotLenderABalance = await jotContract.balanceOf(lenderSignerA.address);
        expect(jotLenderABalance).to.equal(parseEther('0'));
      });
      it('Investor A change redeem order for 1 SOT', async () => {
        await securitizationPoolContract.connect(lenderSignerA).redeemSOTOrder(parseEther('1'));
        const totalSOTRedeem = await securitizationPoolContract.totalSOTRedeem();
        expect(totalSOTRedeem).to.equal(parseEther('2'));
        const sotRedeemOrderLenderA = await securitizationPoolContract.userRedeemSOTOrder(lenderSignerA.address);
        expect(sotRedeemOrderLenderA).to.equal(parseEther('1'));
      });

    });

    describe('Disburse', () => {
      it('SOT: should revert if not backend admin', async () => {
        await expect(securitizationPoolContract
            .connect(poolCreatorSigner)
            .disburseAllForSOT(
                [lenderSignerA.address, lenderSignerB.address],
                [parseEther('0.5'), parseEther('1')],
                [parseEther('0.5'), parseEther('1')]
            )).to.be.revertedWith("AccessControl: caller is not an originator")
      });

      it('SOT: should run successfully', async () => {
        await securitizationPoolContract
            .connect(backendAdminSigner)
            .disburseAllForSOT(
                [lenderSignerA.address, lenderSignerB.address],
                [parseEther('0.5'), parseEther('1')],
                [parseEther('0.5'), parseEther('1')]
            )
        const totalSOTRedeem = await securitizationPoolContract.totalSOTRedeem();
        expect(totalSOTRedeem).to.equal(parseEther('0.5'));
        const sotRedeemOrderLenderA = await securitizationPoolContract.userRedeemSOTOrder(lenderSignerA.address);
        expect(sotRedeemOrderLenderA).to.equal(parseEther('0.5'));
        const sotRedeemOrderLenderB = await securitizationPoolContract.userRedeemSOTOrder(lenderSignerB.address);
        expect(sotRedeemOrderLenderB).to.equal(parseEther('0'));
        const reserve = await securitizationPoolContract.reserve();
        expect(reserve).to.equal(parseEther('2.5')); // $2 SOT raised + $2 JOT raised - $1.5 redeemed
      });

      it('JOT: should revert if not backend admin', async () => {
        await expect(securitizationPoolContract
            .connect(poolCreatorSigner)
            .disburseAllForJOT(
                [lenderSignerA.address, lenderSignerB.address],
                [parseEther('0.5'), parseEther('1')],
                [parseEther('0.5'), parseEther('1')]
            )).to.be.revertedWith("AccessControl: caller is not an originator")
      });

      it('JOT: should run successfully', async () => {
        await securitizationPoolContract
            .connect(backendAdminSigner)
            .disburseAllForJOT(
                [lenderSignerA.address, lenderSignerB.address],
                [parseEther('0.5'), parseEther('1')],
                [parseEther('0.5'), parseEther('1')]
            )
        const totalJOTRedeem = await securitizationPoolContract.totalJOTRedeem();
        expect(totalJOTRedeem).to.equal(parseEther('0.5'));
        const sotRedeemOrderLenderA = await securitizationPoolContract.userRedeemJOTOrder(lenderSignerA.address);
        expect(sotRedeemOrderLenderA).to.equal(parseEther('0.5'));
        const sotRedeemOrderLenderB = await securitizationPoolContract.userRedeemJOTOrder(lenderSignerB.address);
        expect(sotRedeemOrderLenderB).to.equal(parseEther('0'));
        const reserve = await securitizationPoolContract.reserve();
        expect(reserve).to.equal(parseEther('1'));
      });
    });

  });
});
