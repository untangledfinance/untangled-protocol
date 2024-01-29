const { ethers } = require('hardhat');
const { expect } = require('chai');
const { BigNumber, utils } = require('ethers');
const {
    genSalt,
    packTermsContractParameters,
    interestRateFixedPoint,
    saltFromOrderValues,
    debtorsFromOrderAddresses,
    genLoanAgreementIds,
    unlimitedAllowance,
    generateLATMintPayload,
    genRiskScoreParam,
    getPoolByAddress,
    formatFillDebtOrderParams,
    ZERO_ADDRESS,
} = require('../utils');
const { parseEther, parseUnits, formatEther, formatBytes32String } = ethers.utils;
const UntangledProtocol = require('../shared/untangled-protocol');
const dayjs = require('dayjs');
const _ = require('lodash');
const {
    time,
    impersonateAccount,
    stopImpersonatingAccount,
    setBalance,
} = require('@nomicfoundation/hardhat-network-helpers');
const { POOL_ADMIN_ROLE, ORIGINATOR_ROLE } = require('../constants.js');
const { RISK_SCORES, SaleType } = require('../shared/constants');
const { parse } = require('dotenv');
const { setup } = require('../setup');
const { presignedMintMessage } = require('../shared/uid-helper');

const ONE_DAY = 86400;

const YEAR_LENGTH_IN_SECONDS = 31536000; // Number of seconds in a year (approximately)
const ONE_DAY_IN_SECONDS = 86400;
function calculateInterestForDuration(principalAmount, interestRate, durationLengthInSec) {
    // Calculate the interest rate as a fraction
    const interestRateFraction = interestRate * (1 / 100);

    // Calculate the compound interest using the formula
    const compoundInterest =
        principalAmount * Math.pow(1 + interestRateFraction / YEAR_LENGTH_IN_SECONDS, durationLengthInSec) -
        principalAmount;

    return compoundInterest;
}

describe('NAV', () => {
    describe('A loan', () => {
        let stableCoin;
        let securitizationManager;
        let loanKernel;
        let loanRepaymentRouter;
        let loanAssetTokenContract;
        let loanRegistry;
        let uniqueIdentity;
        let registry;
        let distributionOperator;
        let distributionTranche;
        let securitizationPoolContract;
        let securitizationPoolValueService;
        let tokenIds;
        let defaultLoanAssetTokenValidator;
        let securitizationPoolNAV;

        let sotToken;
        let jotToken;
        let mintedIncreasingInterestTGE;
        let jotMintedIncreasingInterestTGE;
        let distributionAssessor;
        let untangledProtocol;

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

            const contracts = await setup();
            untangledProtocol = UntangledProtocol.bind(contracts);
            ({
                stableCoin,
                distributionOperator,
                distributionAssessor,
                distributionTranche,
                securitizationPoolValueService,
                uniqueIdentity,
                loanAssetTokenContract,
                loanRegistry,
                loanKernel,
                loanRepaymentRouter,
                securitizationManager,
                distributionOperator,
                distributionTranche,
                registry,
                defaultLoanAssetTokenValidator,
            } = contracts);
            await stableCoin.transfer(lenderSigner.address, parseEther('1000'));

            // Gain UID
            await untangledProtocol.mintUID(lenderSigner);

            const OWNER_ROLE = await securitizationManager.OWNER_ROLE();
            await securitizationManager.setRoleAdmin(POOL_ADMIN_ROLE, OWNER_ROLE);

            await securitizationManager.grantRole(OWNER_ROLE, borrowerSigner.address);
            await securitizationManager.connect(borrowerSigner).grantRole(POOL_ADMIN_ROLE, poolCreatorSigner.address);
            // Create new pool
            const securitizationPoolAddress = await untangledProtocol.createSecuritizationPool(poolCreatorSigner);

            securitizationPoolContract = await getPoolByAddress(securitizationPoolAddress);
            await securitizationPoolContract
                .connect(poolCreatorSigner)
                .grantRole(ORIGINATOR_ROLE, untangledAdminSigner.address);
        });

        let expirationTimestamps;
        const CREDITOR_FEE = '0';
        const ASSET_PURPOSE = '1';
        const principalAmount = 10000000000000000000;
        const interestRatePercentage = 12; //12%
        before('Should set up TGE for SOT successfully', async () => {
            const openingTime = dayjs(new Date()).unix();
            const closingTime = dayjs(new Date()).add(7, 'days').unix();
            const rate = 2;
            const totalCapOfToken = parseEther('100000');
            const initialInterest = 10000;
            const finalInterest = 10000;
            const timeInterval = 1 * 24 * 3600; // seconds
            const amountChangeEachInterval = 0;
            const prefixOfNoteTokenSaleName = 'SOT_';

            const transaction = await securitizationManager.connect(poolCreatorSigner).setUpTGEForSOT(
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
                }
            );

            const receipt = await transaction.wait();

            const [sotTokenAddress, tgeAddress] = receipt.events.find((e) => e.event == 'SetupSot').args;
            expect(tgeAddress).to.be.properAddress;

            mintedIncreasingInterestTGE = await ethers.getContractAt('MintedIncreasingInterestTGE', tgeAddress);
            expect(sotTokenAddress).to.be.properAddress;

            sotToken = await ethers.getContractAt('NoteToken', sotTokenAddress);
        });

        before('Should set up TGE for JOT successfully', async () => {
            const openingTime = dayjs(new Date()).unix();
            const closingTime = dayjs(new Date()).add(7, 'days').unix();
            const rate = 2;
            const totalCapOfToken = parseEther('100000');
            const prefixOfNoteTokenSaleName = 'JOT_';
            const initialJotAmount = parseEther('100');

            // JOT only has SaleType.NORMAL_SALE
            const transaction = await securitizationManager.connect(poolCreatorSigner).setUpTGEForJOT(
                {
                    issuerTokenController: untangledAdminSigner.address,
                    pool: securitizationPoolContract.address,
                    minBidAmount: parseEther('1'),
                    saleType: SaleType.NORMAL_SALE,
                    longSale: true,
                    ticker: prefixOfNoteTokenSaleName,
                },
                { openingTime: openingTime, closingTime: closingTime, rate: rate, cap: totalCapOfToken },
                initialJotAmount
            );
            const receipt = await transaction.wait();

            const [jotTokenAddress, tgeAddress] = receipt.events.find((e) => e.event == 'SetupJot').args;
            expect(tgeAddress).to.be.properAddress;

            jotMintedIncreasingInterestTGE = await ethers.getContractAt('MintedIncreasingInterestTGE', tgeAddress);

            expect(jotTokenAddress).to.be.properAddress;

            jotToken = await ethers.getContractAt('NoteToken', jotTokenAddress);
        });

        before('Should buy tokens successfully', async () => {
            await untangledProtocol.buyToken(lenderSigner, jotMintedIncreasingInterestTGE.address, parseEther('100'));
            await untangledProtocol.buyToken(lenderSigner, mintedIncreasingInterestTGE.address, parseEther('100'));

            const stablecoinBalanceOfPayerAfter = await stableCoin.balanceOf(lenderSigner.address);
            expect(formatEther(stablecoinBalanceOfPayerAfter)).equal('800.0');

            expect(formatEther(await stableCoin.balanceOf(securitizationPoolContract.address))).equal('200.0');

            const sotValue = await distributionAssessor.calcCorrespondingTotalAssetValue(
                sotToken.address,
                lenderSigner.address
            );
            expect(formatEther(sotValue)).equal('100.0');
        });

        before('upload a loan', async () => {
            // Setup risk scores
            const { riskScoreA, riskScoreB, riskScoreC, riskScoreD, riskScoreE, riskScoreF } = RISK_SCORES;
            const riskScores = [riskScoreA, riskScoreB, riskScoreC, riskScoreD, riskScoreE, riskScoreF];
            await untangledProtocol.setupRiskScore(poolCreatorSigner, securitizationPoolContract, riskScores);

            // Grant role originator
            await securitizationPoolContract
                .connect(poolCreatorSigner)
                .grantRole(ORIGINATOR_ROLE, originatorSigner.address);
            await securitizationPoolContract
                .connect(poolCreatorSigner)
                .grantRole(ORIGINATOR_ROLE, untangledAdminSigner.address);

            // Prepare parameters for loan upload
            const orderAddresses = [
                securitizationPoolContract.address,
                stableCoin.address,
                loanRepaymentRouter.address,
                borrowerSigner.address,
            ];

            const salt = genSalt();
            const riskScore = '3';
            expirationTimestamps = (await time.latest()) + 30 * ONE_DAY_IN_SECONDS;

            const orderValues = [
                CREDITOR_FEE,
                ASSET_PURPOSE,
                principalAmount.toString(),
                expirationTimestamps,
                salt,
                riskScore,
            ];

            const termInDaysLoan = 30;
            const termsContractParameter = packTermsContractParameters({
                amortizationUnitType: 1,
                gracePeriodInDays: 5,
                principalAmount: principalAmount,
                termLengthUnits: _.ceil(termInDaysLoan * 24),
                interestRateFixedPoint: interestRateFixedPoint(interestRatePercentage),
            });

            const termsContractParameters = [termsContractParameter];

            const salts = saltFromOrderValues(orderValues, termsContractParameters.length);
            const debtors = debtorsFromOrderAddresses(orderAddresses, termsContractParameters.length);

            tokenIds = genLoanAgreementIds(loanRepaymentRouter.address, debtors, termsContractParameters, salts);

            // Upload, tokenize loan assets
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

            // Transfer LAT asset to pool
            /*
              await loanAssetTokenContract.connect(originatorSigner).setApprovalForAll(securitizationPoolContract.address, true);
              await securitizationPoolContract.connect(originatorSigner)
                  .collectAssets(loanAssetTokenContract.address, originatorSigner.address, tokenIds);
      */

            // PoolNAV contract
            securitizationPoolNAV = await ethers.getContractAt(
                'SecuritizationPoolNAV',
                securitizationPoolContract.address
            );
        });

        it('after upload loan successfully', async () => {
            const currentNAV = await securitizationPoolNAV.currentNAV();

            const debtLoan = await securitizationPoolNAV.debt(tokenIds[0]);
            expect(debtLoan).to.equal(parseEther('9'));
            expect(currentNAV).to.closeTo(parseEther('9.0037'), parseEther('0.001'));
            expect(await securitizationPoolNAV.currentNAVAsset(tokenIds[0])).to.closeTo(
                parseEther('9.0037'),
                parseEther('0.001')
            );
        });

        it('after 10 days - should include interest', async () => {
            await time.increase(10 * ONE_DAY);
            const now = await time.latest();

            const currentNAV = await securitizationPoolNAV.currentNAV();
            const debtLoan = await securitizationPoolNAV.debt(tokenIds[0]);
            expect(debtLoan).to.closeTo(parseEther('9.029'), parseEther('0.001'));
            expect(currentNAV).to.closeTo(parseEther('9.02839'), parseEther('0.001'));
            const value = await securitizationPoolValueService.getExpectedAssetsValue(
                securitizationPoolContract.address
            );
            expect(value).to.closeTo(parseEther('9.02839'), parseEther('0.001'));
            expect(await securitizationPoolNAV.currentNAVAsset(tokenIds[0])).to.closeTo(
                parseEther('9.02839'),
                parseEther('0.001')
            );
        });
        it('Should revert if updating loan risk without having Pool Admin role', async () => {
            await expect(
                securitizationPoolNAV.connect(originatorSigner).updateAssetRiskScore(tokenIds[0], 2)
            ).to.be.revertedWith('Registry: Not an pool admin');
        });
        it('Change risk score', async () => {
            const currentAsset = await securitizationPoolNAV.getAsset(tokenIds[0]);
            expect(currentAsset.interestRate.toString()).equal('120000');
            await securitizationPoolNAV.connect(untangledAdminSigner).updateAssetRiskScore(tokenIds[0], 2);
            const nextAsset = await securitizationPoolNAV.getAsset(tokenIds[0]);
            expect(nextAsset.interestRate.toString()).equal('100000');
            const currentNAV = await securitizationPoolNAV.currentNAV();
            const debtLoan = await securitizationPoolNAV.debt(tokenIds[0]);
            const curNAVAsset = await securitizationPoolNAV.currentNAVAsset(tokenIds[0]);
            expect(currentNAV).to.closeTo(parseEther('9.0221'), parseEther('0.001'));
            expect(curNAVAsset).to.closeTo(parseEther('9.0221'), parseEther('0.001'));
            expect(debtLoan).to.closeTo(parseEther('9.029'), parseEther('0.001'));
            await securitizationPoolContract.connect(untangledAdminSigner).updateAssetRiskScore(tokenIds[0], 3);
            expect(await securitizationPoolNAV.debt(tokenIds[0])).to.closeTo(parseEther('9.029'), parseEther('0.001'));
            expect(await securitizationPoolNAV.currentNAV()).to.closeTo(parseEther('9.02839'), parseEther('0.001'));
            expect(await securitizationPoolNAV.currentNAVAsset(tokenIds[0])).to.closeTo(
                parseEther('9.02839'),
                parseEther('0.001')
            );
        });
        it('next 20 days - on maturity date', async () => {
            await time.increase(20 * ONE_DAY);
            const now = await time.latest();
            const currentNAV = await securitizationPoolNAV.currentNAV();
            const debtLoan = await securitizationPoolNAV.debt(tokenIds[0]);
            expect(debtLoan).to.closeTo(parseEther('9.089'), parseEther('0.001'));
            expect(currentNAV).to.closeTo(parseEther('9.078'), parseEther('0.001'));
            expect(await securitizationPoolNAV.currentNAVAsset(tokenIds[0])).to.closeTo(
                parseEther('9.078'),
                parseEther('0.001')
            );
        });

        it('should revert if write off loan before grace period', async () => {
            await time.increase(2 * ONE_DAY);
            await expect(securitizationPoolNAV.writeOff(tokenIds[0])).to.be.revertedWith('maturity-date-in-the-future');
        });

        it('overdue 6 days - should write off after grace period', async () => {
            await time.increase(3 * ONE_DAY);

            await securitizationPoolNAV.writeOff(tokenIds[0]);
            await time.increase(1 * ONE_DAY);

            const currentNAV = await securitizationPoolNAV.currentNAV();
            expect(currentNAV).to.closeTo(parseEther('4.5543'), parseEther('0.005'));

            const la = await securitizationPoolNAV.currentNAVAsset(tokenIds[0]);
            expect(la).to.closeTo(parseEther('4.5543'), parseEther('0.005'));
        });
        it('overdue next 30 days - should write off after collection period', async () => {
            await time.increase(30 * ONE_DAY);
            await securitizationPoolNAV.writeOff(tokenIds[0]);
            const currentNAV = await securitizationPoolNAV.currentNAV();
            expect(currentNAV).to.equal(parseEther('0'));
            expect(await securitizationPoolNAV.currentNAVAsset(tokenIds[0])).to.equal(parseEther('0'));
        });

        it('should repay successfully', async () => {
            await stableCoin.connect(untangledAdminSigner).approve(loanRepaymentRouter.address, unlimitedAllowance);
            await loanRepaymentRouter
                .connect(untangledAdminSigner)
                .repayInBatch([tokenIds[0]], [parseEther('10')], stableCoin.address);
            const balanceAfterRepay = await stableCoin.balanceOf(untangledAdminSigner.address);
            expect(balanceAfterRepay).to.closeTo(parseEther('98999.80'), parseEther('0.01'));
        });
    });

    describe('Two loan - different interest rate & risk score', () => {
        let stableCoin;
        let securitizationManager;
        let loanKernel;
        let loanRepaymentRouter;
        let loanAssetTokenContract;
        let loanRegistry;
        let uniqueIdentity;
        let registry;
        let distributionOperator;
        let distributionTranche;
        let securitizationPoolContract;
        let securitizationPoolValueService;
        let tokenIds;
        let defaultLoanAssetTokenValidator;
        let uploadedLoanTime;
        let untangledProtocol;

        let sotToken;
        let jotToken;
        let mintedIncreasingInterestTGE;
        let jotMintedIncreasingInterestTGE;
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

            const contracts = await setup();
            untangledProtocol = UntangledProtocol.bind(contracts);
            ({
                stableCoin,
                distributionOperator,
                distributionAssessor,
                distributionTranche,
                securitizationPoolValueService,
                uniqueIdentity,
                loanAssetTokenContract,
                loanRegistry,
                loanKernel,
                loanRepaymentRouter,
                securitizationManager,
                distributionOperator,
                distributionTranche,
                registry,
                defaultLoanAssetTokenValidator,
            } = contracts);
            await stableCoin.transfer(lenderSigner.address, parseEther('1000'));

            // Gain UID
            await untangledProtocol.mintUID(lenderSigner);

            const OWNER_ROLE = await securitizationManager.OWNER_ROLE();
            await securitizationManager.setRoleAdmin(POOL_ADMIN_ROLE, OWNER_ROLE);

            await securitizationManager.grantRole(OWNER_ROLE, borrowerSigner.address);
            await securitizationManager.connect(borrowerSigner).grantRole(POOL_ADMIN_ROLE, poolCreatorSigner.address);
            // Create new pool
            const securitizationPoolAddress = await untangledProtocol.createSecuritizationPool(poolCreatorSigner);

            securitizationPoolContract = await getPoolByAddress(securitizationPoolAddress);
            await securitizationPoolContract
                .connect(poolCreatorSigner)
                .grantRole(ORIGINATOR_ROLE, untangledAdminSigner.address);
        });
        before('setting riskscore for pool', async () => {
            const { riskScoreA, riskScoreB, riskScoreC, riskScoreD, riskScoreE, riskScoreF } = RISK_SCORES;
            const { daysPastDues, ratesAndDefaults, periodsAndWriteOffs } = genRiskScoreParam(
                riskScoreA,
                riskScoreB,
                riskScoreC,
                riskScoreD,
                riskScoreE,
                riskScoreF
            );
            await securitizationPoolContract
                .connect(poolCreatorSigner)
                .setupRiskScores(daysPastDues, ratesAndDefaults, periodsAndWriteOffs);

            // Grant role originator
            await securitizationPoolContract
                .connect(poolCreatorSigner)
                .grantRole(ORIGINATOR_ROLE, originatorSigner.address);
            await securitizationPoolContract
                .connect(poolCreatorSigner)
                .grantRole(ORIGINATOR_ROLE, untangledAdminSigner.address);
        });

        before('Should set up TGE for SOT successfully', async () => {
            const { sotTGEAddress, sotTokenAddress } = await untangledProtocol.initSOTSale(poolCreatorSigner, {
                issuerTokenController: untangledAdminSigner.address,
                pool: securitizationPoolContract.address,
                saleType: SaleType.MINTED_INCREASING_INTEREST,
                minBidAmount: parseEther('1'),
                openingTime: dayjs(new Date()).unix(),
                closingTime: dayjs(new Date()).add(7, 'days').unix(),
                rate: 2,
                cap: parseEther('100000'),
                initialInterest: 10000,
                finalInterest: 10000,
                timeInterval: 86400,
                amountChangeEachInterval: 1000,
                ticker: 'Ticker',
            });

            mintedIncreasingInterestTGE = await ethers.getContractAt('MintedIncreasingInterestTGE', sotTGEAddress);

            expect(sotTokenAddress).to.be.properAddress;

            sotToken = await ethers.getContractAt('NoteToken', sotTokenAddress);
        });

        before('Should set up TGE for JOT successfully', async () => {
            // JOT only has SaleType.NORMAL_SALE
            const { jotTGEAddress, jotTokenAddress } = await untangledProtocol.initJOTSale(poolCreatorSigner, {
                issuerTokenController: untangledAdminSigner.address,
                pool: securitizationPoolContract.address,
                minBidAmount: parseEther('1'),
                saleType: SaleType.NORMAL_SALE,
                longSale: true,
                ticker: 'Ticker',
                openingTime: dayjs(new Date()).unix(),
                closingTime: dayjs(new Date()).add(7, 'days').unix(),
                rate: 10000,
                cap: parseEther('100000'),
                initialJOTAmount: parseEther('100'),
            });

            jotMintedIncreasingInterestTGE = await ethers.getContractAt('MintedIncreasingInterestTGE', jotTGEAddress);

            expect(jotTokenAddress).to.be.properAddress;

            jotToken = await ethers.getContractAt('NoteToken', jotTokenAddress);
        });

        before('Should buy tokens successfully', async () => {
            await untangledProtocol.buyToken(lenderSigner, jotMintedIncreasingInterestTGE.address, parseEther('100'));

            await untangledProtocol.buyToken(lenderSigner, mintedIncreasingInterestTGE.address, parseEther('100'));

            const stablecoinBalanceOfPayerAfter = await stableCoin.balanceOf(lenderSigner.address);
            expect(formatEther(stablecoinBalanceOfPayerAfter)).equal('800.0');

            expect(formatEther(await stableCoin.balanceOf(securitizationPoolContract.address))).equal('200.0');

            const sotValue = await distributionAssessor.calcCorrespondingTotalAssetValue(
                sotToken.address,
                lenderSigner.address
            );
            expect(formatEther(sotValue)).equal('100.0');
        });

        before('upload loans', async () => {
            let expirationTimestamps;
            const CREDITOR_FEE = '0';
            const ASSET_PURPOSE = '1';
            const principalAmount = 10000000000000000000;
            const interestRatePercentage = 12; //12%
            const principalAmountLoan2 = 5000000000000000000;
            const interestRatePercentageLoan2 = 8; // 8%
            // Setup Risk Scores

            // Prepare parameters for loan upload
            const orderAddresses = [
                securitizationPoolContract.address,
                stableCoin.address,
                loanRepaymentRouter.address,
                borrowerSigner.address,
                borrowerSigner.address,
            ];

            const salt = genSalt();
            const salt2 = genSalt();
            const riskScore = '3';
            const riskScoreLoan2 = '1';
            expirationTimestamps = (await time.latest()) + 30 * ONE_DAY_IN_SECONDS;
            const expirationTimestampsLoan2 = (await time.latest()) + 60 * ONE_DAY_IN_SECONDS;

            const orderValues = [
                CREDITOR_FEE,
                ASSET_PURPOSE,
                principalAmount.toString(),
                principalAmountLoan2.toString(),
                expirationTimestamps,
                expirationTimestampsLoan2,
                salt,
                salt2,
                riskScore,
                riskScoreLoan2,
            ];

            const termInDaysLoan = 30;
            const termInDaysLoan2 = 60;
            const termsContractParameter = packTermsContractParameters({
                amortizationUnitType: 1,
                gracePeriodInDays: 5,
                principalAmount: principalAmount,
                termLengthUnits: _.ceil(termInDaysLoan * 24),
                interestRateFixedPoint: interestRateFixedPoint(interestRatePercentage),
            });
            const termsContractParameter2 = packTermsContractParameters({
                amortizationUnitType: 1,
                gracePeriodInDays: 5,
                principalAmount: principalAmountLoan2,
                termLengthUnits: _.ceil(termInDaysLoan2 * 24),
                interestRateFixedPoint: interestRateFixedPoint(interestRatePercentageLoan2),
            });

            const termsContractParameters = [termsContractParameter, termsContractParameter2];

            const salts = saltFromOrderValues(orderValues, termsContractParameters.length);
            const debtors = debtorsFromOrderAddresses(orderAddresses, termsContractParameters.length);

            tokenIds = genLoanAgreementIds(loanRepaymentRouter.address, debtors, termsContractParameters, salts);

            // Upload, tokenize loan assets
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

            // Transfer LAT asset to pool
            /*
              await loanAssetTokenContract.connect(originatorSigner).setApprovalForAll(securitizationPoolContract.address, true);
              await securitizationPoolContract.connect(originatorSigner)
                  .collectAssets(loanAssetTokenContract.address, originatorSigner.address, tokenIds);
      */
            uploadedLoanTime = await time.latest();

            securitizationPoolContract = await ethers.getContractAt(
                'SecuritizationPoolNAV',
                securitizationPoolContract.address
            );
        });

        it('after upload loan successfully', async () => {
            const currentNAV = await securitizationPoolContract.currentNAV();

            const debtLoan = await securitizationPoolContract.debt(tokenIds[0]);
            expect(debtLoan).to.equal(parseEther('9'));
            const debtLoan2 = await securitizationPoolContract.debt(tokenIds[1]);
            expect(debtLoan2).to.equal(parseEther('4.75'));
            expect(currentNAV).to.closeTo(parseEther('13.73'), parseEther('0.01'));
            const poolValue = await securitizationPoolValueService.getExpectedAssetsValue(
                securitizationPoolContract.address
            );
            expect(poolValue).to.closeTo(parseEther('13.73'), parseEther('0.01'));

            // total nav assets = currentNAV
            const totalNavAssets = (
                await Promise.all(tokenIds.map(async (x) => await securitizationPoolContract.currentNAVAsset(x)))
            ).reduce((acc, x) => acc.add(x), BigNumber.from(0));

            expect(totalNavAssets).to.closeTo(parseEther('13.73'), parseEther('0.01'));
        });

        it('after 10 days - should include interest', async () => {
            await time.increaseTo(uploadedLoanTime + 10 * ONE_DAY);
            const now = await time.latest();

            const currentNAV = await securitizationPoolContract.currentNAV();
            const debtLoan = await securitizationPoolContract.debt(tokenIds[0]);
            expect(debtLoan).to.closeTo(parseEther('9.029'), parseEther('0.001'));
            expect(currentNAV).to.closeTo(parseEther('13.77'), parseEther('0.001'));

            // total nav assets = currentNAV
            const totalNavAssets = (
                await Promise.all(tokenIds.map(async (x) => await securitizationPoolContract.currentNAVAsset(x)))
            ).reduce((acc, x) => acc.add(x), BigNumber.from(0));

            expect(totalNavAssets).to.closeTo(parseEther('13.77'), parseEther('0.001'));
        });
        it('after 30 days - on maturity date', async () => {
            await time.increaseTo(uploadedLoanTime + 30 * ONE_DAY);
            const now = await time.latest();
            const currentNAV = await securitizationPoolContract.currentNAV();
            const debtLoan = await securitizationPoolContract.debt(tokenIds[0]);
            expect(debtLoan).to.closeTo(parseEther('9.089'), parseEther('0.001'));
            expect(currentNAV).to.closeTo(parseEther('13.84'), parseEther('0.01'));

            // total nav assets = currentNAV
            const totalNavAssets = (
                await Promise.all(tokenIds.map(async (x) => await securitizationPoolContract.currentNAVAsset(x)))
            ).reduce((acc, x) => acc.add(x), BigNumber.from(0));

            expect(totalNavAssets).to.closeTo(parseEther('13.84'), parseEther('0.01'));
        });
        /*
        xit('should repay now', async () => {
          await stableCoin.connect(untangledAdminSigner).approve(loanRepaymentRouter.address, unlimitedAllowance);
          await loanRepaymentRouter
              .connect(untangledAdminSigner)
              .repayInBatch([tokenIds[0]], [parseEther('10')], stableCoin.address);
    */
        it('should revert if write off loan before grace period', async () => {
            await time.increaseTo(uploadedLoanTime + 32 * ONE_DAY);
            await expect(securitizationPoolContract.connect(lenderSigner).writeOff(tokenIds[1])).to.be.revertedWith(
                'maturity-date-in-the-future'
            );
        });

        it('after 36days - should write off loan 1 after grace period', async () => {
            await time.increaseTo(uploadedLoanTime + 35 * ONE_DAY);
            await securitizationPoolContract.connect(lenderSigner).writeOff(tokenIds[0]);
            await time.increaseTo(uploadedLoanTime + 36 * ONE_DAY);
            const currentNAV = await securitizationPoolContract.currentNAV();
            await expect(securitizationPoolContract.connect(lenderSigner).writeOff(tokenIds[1])).to.be.revertedWith(
                'maturity-date-in-the-future'
            );
            expect(currentNAV).to.closeTo(parseEther('9.33'), parseEther('0.001'));

            // total nav assets = currentNAV
            const totalNavAssets = (
                await Promise.all(tokenIds.map(async (x) => await securitizationPoolContract.currentNAVAsset(x)))
            ).reduce((acc, x) => acc.add(x), BigNumber.from(0));

            expect(totalNavAssets).to.closeTo(parseEther('9.33'), parseEther('0.001'));
        });
        it('after 65 days - write off loan 2', async () => {
            await time.increaseTo(uploadedLoanTime + 65 * ONE_DAY);
            await securitizationPoolContract.connect(lenderSigner).writeOff(tokenIds[1]);
        });
        it('after 66 days - should write off', async () => {
            await time.increaseTo(uploadedLoanTime + 66 * ONE_DAY);
            await securitizationPoolContract.connect(lenderSigner).writeOff(tokenIds[0]);
            const currentNAV = await securitizationPoolContract.currentNAV();
            expect(currentNAV).to.closeTo(parseEther('3.6148'), parseEther('0.001'));

            // total nav assets = currentNAV
            const totalNavAssets = (
                await Promise.all(tokenIds.map(async (x) => await securitizationPoolContract.currentNAVAsset(x)))
            ).reduce((acc, x) => acc.add(x), BigNumber.from(0));

            expect(totalNavAssets).to.closeTo(parseEther('3.6148'), parseEther('0.001'));
        });

        it('should repay partially successfully', async () => {
            await stableCoin.connect(untangledAdminSigner).approve(loanRepaymentRouter.address, unlimitedAllowance);
            await loanRepaymentRouter
                .connect(untangledAdminSigner)
                .repayInBatch(tokenIds, [parseEther('5'), parseEther('5')], stableCoin.address);
            const debtLoan = await securitizationPoolContract.debt(tokenIds[0]);
            expect(debtLoan).to.closeTo(parseEther('4.197'), parseEther('0.001'));
            const debtLoan2 = await securitizationPoolContract.debt(tokenIds[1]);
            expect(debtLoan2).to.equal(parseEther('0'));
            const balanceAfterRepay = await stableCoin.balanceOf(untangledAdminSigner.address);
            expect(balanceAfterRepay).to.closeTo(parseEther('99003.91'), parseEther('0.05'));
            const currentNAV = await securitizationPoolContract.currentNAV();
        });
        it('should repay remaining successfully', async () => {
            await stableCoin.transfer(borrowerSigner.address, parseEther('10'));
            await stableCoin.connect(borrowerSigner).approve(loanRepaymentRouter.address, unlimitedAllowance);
            await loanRepaymentRouter
                .connect(borrowerSigner)
                .repayInBatch([tokenIds[0]], [parseEther('5')], stableCoin.address);

            const balanceAfterRepay = await stableCoin.balanceOf(borrowerSigner.address);
            const currentNAV = await securitizationPoolContract.currentNAV();
            expect(balanceAfterRepay).to.closeTo(parseEther('5.80257'), parseEther('0.05'));
        });
    });
});
