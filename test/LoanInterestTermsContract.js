const { ethers } = require('hardhat');
const { expect } = require('chai');
const { BigNumber, constants, utils } = require('ethers');
const {
  genSalt,
  packTermsContractParameters,
  interestRateFixedPoint,
  saltFromOrderValues,
  debtorsFromOrderAddresses,
  genLoanAgreementIds,
  unlimitedAllowance,
  generateLATMintPayload,
  getPoolByAddress,
  formatFillDebtOrderParams,
} = require('./utils');
const { parseEther, parseUnits, formatEther, formatBytes32String } = ethers.utils;
const dayjs = require('dayjs');
const _ = require('lodash');
const {
  time,
  impersonateAccount,
  stopImpersonatingAccount,
  setBalance,
} = require('@nomicfoundation/hardhat-network-helpers');
const { parse } = require('dotenv');
const { setup } = require('./setup.js');

const { POOL_ADMIN_ROLE } = require('./constants.js');
const { SaleType } = require('./shared/constants.js');
const { presignedMintMessage } = require('./shared/uid-helper.js');
const { ORIGINATOR_ROLE } = require('./constants');

const ONE_DAY = 86400;

const YEAR_LENGTH_IN_SECONDS = 31536000; // Number of seconds in a year (approximately)
function calculateInterestForDuration(principalAmount, interestRate, durationLengthInSec) {
  // Calculate the interest rate as a fraction
  const interestRateFraction = interestRate * (1 / 100);

  // Calculate the compound interest using the formula
  const compoundInterest =
    principalAmount * Math.pow(1 + interestRateFraction / YEAR_LENGTH_IN_SECONDS, durationLengthInSec) -
    principalAmount;

  return compoundInterest;
}
describe('LoanInterestTermsContract', () => {
  let stableCoin;
  let securitizationManager;
  let loanKernel;
  let loanRepaymentRouter;
  let loanAssetTokenContract;
  let loanRegistry;
  let uniqueIdentity;
  let registry;
  let loanInterestTerms;
  let distributionOperator;
  let distributionTranche;
  let securitizationPoolContract;
  let defaultLoanAssetTokenValidator;
  let tokenIds;

  let loanInterestTermsContract;
  let secondSecuritizationPool;
  let sotToken;
  let jotToken;
  let mintedIncreasingInterestTGE;
  let jotMintedIncreasingInterestTGE;
  let securitizationPoolValueService;
  let distributionAssessor;

  // Wallets
  let untangledAdminSigner,
    poolCreatorSigner,
    originatorSigner,
    borrowerSigner,
    lenderSigner,
    relayer,
    impersonationKernel;

  before('create fixture', async () => {
    [
      untangledAdminSigner,
      poolCreatorSigner,
      originatorSigner,
      borrowerSigner,
      lenderSigner,
      relayer,
      impersonationKernel,
    ] = await ethers.getSigners();

    ({
      stableCoin,
      uniqueIdentity,
      loanAssetTokenContract,
      loanInterestTermsContract,
      loanRegistry,
      loanKernel,
      loanRepaymentRouter,
      securitizationManager,
      distributionOperator,
      distributionTranche,
      registry,
      defaultLoanAssetTokenValidator,
      securitizationPoolValueService,
      distributionAssessor,
    } = await setup());
    await stableCoin.transfer(lenderSigner.address, parseEther('1000'));

    await stableCoin.connect(untangledAdminSigner).approve(loanRepaymentRouter.address, unlimitedAllowance);

    // Gain UID
    const UID_TYPE = 0;
    const chainId = await getChainId();
    const expiredAt = dayjs().unix() + 86400;
    const nonce = 0;
    const ethRequired = parseEther('0.00083');

    const uidMintMessage = presignedMintMessage(
      lenderSigner.address,
      UID_TYPE,
      expiredAt,
      uniqueIdentity.address,
      nonce,
      chainId
    );
    const signature = await untangledAdminSigner.signMessage(uidMintMessage);
    await uniqueIdentity.connect(lenderSigner).mint(UID_TYPE, expiredAt, signature, { value: ethRequired });

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
    await securitizationPoolContract
      .connect(poolCreatorSigner)
      .grantRole(ORIGINATOR_ROLE, untangledAdminSigner.address);
  });

  describe('#Securitization Manager', async () => {
    it('Should set up TGE for SOT successfully', async () => {

      const openingTime = dayjs(new Date()).unix();
      const closingTime = dayjs(new Date()).add(7, 'days').unix();
      const rate = 2;
      const totalCapOfToken = parseEther('100000');
      const initialInterest = 10000;
      const finalInterest = 10000;
      const timeInterval = 1 * 24 * 3600; // seconds
      const amountChangeEachInterval = 0;
      const prefixOfNoteTokenSaleName = 'SOT_';

      const transaction = await securitizationManager
        .connect(poolCreatorSigner)
        .setUpTGEForSOT(
          {
            issuerTokenController: untangledAdminSigner.address,
            pool: securitizationPoolContract.address,
            minBidAmount: parseEther('1'),
            saleType: SaleType.MINTED_INCREASING_INTEREST,
            longSale: true,
            ticker: prefixOfNoteTokenSaleName,
          },
          { openingTime: openingTime, closingTime: closingTime, rate: rate, cap: totalCapOfToken },
          {
            initialInterest,
            finalInterest,
            timeInterval,
            amountChangeEachInterval,
          },
        );

      const receipt = await transaction.wait();

      const [tgeAddress] = receipt.events.find((e) => e.event == 'NewTGECreated').args;
      expect(tgeAddress).to.be.properAddress;

      mintedIncreasingInterestTGE = await ethers.getContractAt('MintedIncreasingInterestTGE', tgeAddress);

      const [sotTokenAddress] = receipt.events.find((e) => e.event == 'NewNotesTokenCreated').args;
      expect(sotTokenAddress).to.be.properAddress;

      sotToken = await ethers.getContractAt('NoteToken', sotTokenAddress);
    });

    it('Should set up TGE for JOT successfully', async () => {

      const openingTime = dayjs(new Date()).unix();
      const closingTime = dayjs(new Date()).add(7, 'days').unix();
      const rate = 2;
      const totalCapOfToken = parseEther('100000');
      const prefixOfNoteTokenSaleName = 'JOT_';
      const initialJotAmount = parseEther('100');

      // JOT only has SaleType.NORMAL_SALE
      const transaction = await securitizationManager
        .connect(poolCreatorSigner)
        .setUpTGEForJOT(
          {
            issuerTokenController: untangledAdminSigner.address,
            pool: securitizationPoolContract.address,
            minBidAmount: parseEther('1'),
            saleType: SaleType.NORMAL_SALE,
            longSale: true,
            ticker: prefixOfNoteTokenSaleName,
          },
          { openingTime: openingTime, closingTime: closingTime, rate: rate, cap: totalCapOfToken },
          initialJotAmount,
        );
      const receipt = await transaction.wait();

      const [tgeAddress] = receipt.events.find((e) => e.event == 'NewTGECreated').args;
      expect(tgeAddress).to.be.properAddress;

      jotMintedIncreasingInterestTGE = await ethers.getContractAt('MintedIncreasingInterestTGE', tgeAddress);

      const [jotTokenAddress] = receipt.events.find((e) => e.event == 'NewNotesTokenCreated').args;
      expect(jotTokenAddress).to.be.properAddress;

      jotToken = await ethers.getContractAt('NoteToken', jotTokenAddress);
    });

    it('Should buy tokens failed if buy sot first', async () => {
      await stableCoin.connect(lenderSigner).approve(mintedIncreasingInterestTGE.address, unlimitedAllowance);

      await expect(
        securitizationManager
          .connect(lenderSigner)
          .buyTokens(mintedIncreasingInterestTGE.address, parseEther('100'))
      ).to.be.revertedWith(`Crowdsale: sale not started`);
    });

    it('Should buy tokens successfully', async () => {
      await stableCoin.connect(lenderSigner).approve(mintedIncreasingInterestTGE.address, unlimitedAllowance);

      await stableCoin.connect(lenderSigner).approve(jotMintedIncreasingInterestTGE.address, unlimitedAllowance);
      await securitizationManager
        .connect(lenderSigner)
        .buyTokens(jotMintedIncreasingInterestTGE.address, parseEther('100'));

      await securitizationManager
        .connect(lenderSigner)
        .buyTokens(mintedIncreasingInterestTGE.address, parseEther('100'));

      const stablecoinBalanceOfPayerAfter = await stableCoin.balanceOf(lenderSigner.address);
      expect(formatEther(stablecoinBalanceOfPayerAfter)).equal('800.0');

      expect(formatEther(await stableCoin.balanceOf(securitizationPoolContract.address))).equal('200.0');

      const sotValue = await distributionAssessor.calcCorrespondingTotalAssetValue(
        sotToken.address,
        lenderSigner.address
      );
      expect(formatEther(sotValue)).equal('100.0');
    });
  });

  const agreementID = '0x979b5e9fab60f9433bf1aa924d2d09636ae0f5c10e2c6a8a58fe441cd1414d7f';
  let expirationTimestamps;
  const CREDITOR_FEE = '0';
  const ASSET_PURPOSE = '0';
  const inputAmount = 10;
  const inputPrice = 15;
  const principalAmount = 5000000000000000000;
  const interestRatePercentage = 5;
  describe('#registerTermStart', () => {
    it('should revert if caller is not LoanKernel contract address', async () => {
      await expect(
        loanInterestTermsContract.connect(untangledAdminSigner).registerTermStart([agreementID])
      ).to.be.revertedWith('LoanInterestTermsContract: Only for LoanKernel.');
    });
    it('should start loan successfully', async () => {
      await registry.setLoanKernel(impersonationKernel.address);
      await loanInterestTermsContract.connect(impersonationKernel).registerTermStart([agreementID]);
      expect(await loanInterestTermsContract.startedLoan(agreementID)).equal(true);
    });
    it('should revert if the loan has started', async () => {
      await expect(
        loanInterestTermsContract.connect(impersonationKernel).registerTermStart([agreementID])
      ).to.be.revertedWith('LoanInterestTermsContract: Loan has started!');
    });
  });

  describe('#getExpectedRepaymentValues', () => {
    before('upload a loan', async () => {
      await registry.setLoanKernel(loanKernel.address);
      const orderAddresses = [
        securitizationPoolContract.address,
        stableCoin.address,
        loanRepaymentRouter.address,
        loanInterestTermsContract.address,
        relayer.address,
        borrowerSigner.address, // for loan 0
        borrowerSigner.address, // for loan 1
        borrowerSigner.address, // for loan 2
        borrowerSigner.address, // for loan 3
        borrowerSigner.address, // for loan 4
      ];

      const salt = genSalt();
      const salt1 = genSalt();
      const salt2 = genSalt();
      const salt3 = genSalt();
      const salt4 = genSalt();
      const riskScore = '50';
      expirationTimestamps = dayjs(new Date()).add(7, 'days').unix();

      const orderValues = [
        CREDITOR_FEE,
        ASSET_PURPOSE,
        principalAmount.toString(),
        principalAmount.toString(),
        principalAmount.toString(),
        principalAmount.toString(),
        principalAmount.toString(),
        expirationTimestamps,
        expirationTimestamps,
        expirationTimestamps,
        expirationTimestamps,
        expirationTimestamps,
        salt,
        salt1,
        salt2,
        salt3,
        salt4,
        riskScore,
        riskScore,
        riskScore,
        riskScore,
        riskScore,
      ];

      const termInDaysLoan = 10;
      const termsContractParameter = packTermsContractParameters({
        amortizationUnitType: 1,
        gracePeriodInDays: 2,
        principalAmount: principalAmount,
        termLengthUnits: _.ceil(termInDaysLoan * 24),
        interestRateFixedPoint: interestRateFixedPoint(interestRatePercentage),
      });
      const termsContractParameter_1 = packTermsContractParameters({
        amortizationUnitType: 2,
        gracePeriodInDays: 2,
        principalAmount: principalAmount,
        termLengthUnits: _.ceil(termInDaysLoan * 24),
        interestRateFixedPoint: interestRateFixedPoint(interestRatePercentage),
      });

      const termsContractParameter_2 = packTermsContractParameters({
        amortizationUnitType: 3,
        gracePeriodInDays: 2,
        principalAmount: principalAmount,
        termLengthUnits: _.ceil(termInDaysLoan * 24),
        interestRateFixedPoint: interestRateFixedPoint(interestRatePercentage),
      });

      const termsContractParameter_3 = packTermsContractParameters({
        amortizationUnitType: 4,
        gracePeriodInDays: 2,
        principalAmount: principalAmount,
        termLengthUnits: _.ceil(termInDaysLoan * 24),
        interestRateFixedPoint: interestRateFixedPoint(interestRatePercentage),
      });
      const termsContractParameter_4 = packTermsContractParameters({
        amortizationUnitType: 5,
        gracePeriodInDays: 2,
        principalAmount: principalAmount,
        termLengthUnits: _.ceil(termInDaysLoan * 24),
        interestRateFixedPoint: interestRateFixedPoint(interestRatePercentage),
      });

      const termsContractParameters = [
        termsContractParameter,
        termsContractParameter_1,
        termsContractParameter_2,
        termsContractParameter_3,
        termsContractParameter_4,
      ];

      const salts = saltFromOrderValues(orderValues, termsContractParameters.length);
      const debtors = debtorsFromOrderAddresses(orderAddresses, termsContractParameters.length);

      tokenIds = genLoanAgreementIds(
        loanRepaymentRouter.address,
        debtors,
        loanInterestTermsContract.address,
        termsContractParameters,
        salts
      );

      await loanKernel.fillDebtOrder(
        formatFillDebtOrderParams(
          orderAddresses,
          orderValues,
          termsContractParameters,
          await Promise.all(
            tokenIds.map(async (x) => ({
              ...(await generateLATMintPayload(
                loanAssetTokenContract,
                defaultLoanAssetTokenValidator,
                [x],
                [(await loanAssetTokenContract.nonce(x)).toNumber()],
                defaultLoanAssetTokenValidator.address
              )),
            }))
          )
        )
      );

      await stableCoin.connect(untangledAdminSigner).approve(loanRepaymentRouter.address, unlimitedAllowance);
    });
    it('should return correct expected principal and expected interest', async () => {
      const now = await time.latest();
      const duration = YEAR_LENGTH_IN_SECONDS;
      const { expectedPrincipal, expectedInterest } = await loanInterestTermsContract.getExpectedRepaymentValues(
        tokenIds[0],
        now + duration
      );
      const repaidPrincipalAmount = await loanInterestTermsContract.repaidPrincipalAmounts(tokenIds[0]);
      expect(expectedPrincipal).equal(BigNumber.from(principalAmount.toString()).sub(repaidPrincipalAmount));

      const expectInterest = calculateInterestForDuration(principalAmount, interestRatePercentage, duration);
      expect(expectedInterest).closeTo(expectInterest.toString(), parseEther('0.001'));
    });
  });
  describe('#registerConcludeLoan', () => {
    it('should revert if caller is not LoanKernel contract address', async () => {
      await expect(
        loanInterestTermsContract.connect(untangledAdminSigner).registerConcludeLoan(agreementID)
      ).to.be.revertedWith('Registry: Only LoanKernel');
    });
  });

  describe('#getInterestRate', async () => {
    it('should unpack interest rate correctly', async () => {
      const interestRate = await loanInterestTermsContract.getInterestRate(tokenIds[0]);
      expect(interestRate).equal(BigNumber.from(interestRateFixedPoint(interestRatePercentage).toString()));
    });
  });

  describe('#getValueRepaidToDate', async () => {
    it('should return current repaid principal and interest amount of an agreementId', async () => {
      const [repaidPrincipal, repaidInterest] = await loanInterestTermsContract.getValueRepaidToDate(tokenIds[0]);
      const expectPrincipalAmount = await loanInterestTermsContract.repaidPrincipalAmounts(tokenIds[0]);
      const expectInterestAmount = await loanInterestTermsContract.repaidInterestAmounts(tokenIds[0]);
      expect(repaidPrincipal).to.equal(expectPrincipalAmount);
      expect(repaidInterest).to.equal(expectInterestAmount);
    });
    describe('#getMultiExpectedRepaymentValues', async () => {
      it('should return current repaid principal and interest amount of multiple agreementIds', async () => {
        const [repaidPrincipal, repaidInterest] = await loanInterestTermsContract.getValueRepaidToDate(tokenIds[0]);
        const expectPrincipalAmount = await loanInterestTermsContract.repaidPrincipalAmounts(tokenIds[0]);
        const expectInterestAmount = await loanInterestTermsContract.repaidInterestAmounts(tokenIds[0]);
        const [repaidPrincipal1, repaidInterest1] = await loanInterestTermsContract.getValueRepaidToDate(
          tokenIds[1]
        );
        const expectPrincipalAmount1 = await loanInterestTermsContract.repaidPrincipalAmounts(tokenIds[1]);
        const expectInterestAmount1 = await loanInterestTermsContract.repaidInterestAmounts(tokenIds[1]);
        expect(repaidPrincipal).to.equal(expectPrincipalAmount);
        expect(repaidInterest).to.equal(expectInterestAmount);
        expect(repaidPrincipal1).to.equal(expectPrincipalAmount1);
        expect(repaidInterest1).to.equal(expectInterestAmount1);
      });
    });
  });
});
