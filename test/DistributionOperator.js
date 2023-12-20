const { ethers, upgrades } = require('hardhat');
const { deployments } = require('hardhat');
const _ = require('lodash');
const dayjs = require('dayjs');
const { expect } = require('chai');
const { time } = require('@nomicfoundation/hardhat-network-helpers');

const { POOL_ADMIN_ROLE, ORIGINATOR_ROLE } = require('./constants');

const { BigNumber } = ethers;
const { parseEther, parseUnits, formatEther, formatBytes32String } = ethers.utils;
const { presignedMintMessage } = require('./shared/uid-helper.js');

const {
    unlimitedAllowance,
    ZERO_ADDRESS,
    genLoanAgreementIds,
    saltFromOrderValues,
    debtorsFromOrderAddresses,
    packTermsContractParameters,
    interestRateFixedPoint,
    genSalt,
    generateLATMintPayload,
    getPoolByAddress,
    formatFillDebtOrderParams,
} = require('./utils.js');
const { setup } = require('./setup.js');
const { SaleType } = require('./shared/constants.js');
const { constants, utils } = require('ethers');

const ONE_DAY = 86400;
const RATE_SCALING_FACTOR = 10 ** 4;

describe('Distribution', () => {
    let stableCoin;
    let loanAssetTokenContract;
    let loanInterestTermsContract;
    let loanKernel;
    let loanRepaymentRouter;
    let securitizationManager;
    let securitizationPoolContract;
    let secondSecuritizationPool;
    let tokenIds;
    let uniqueIdentity;
    let distributionOperator;
    let sotToken;
    let jotToken;
    let distributionTranche;
    let mintedIncreasingInterestTGE;
    let jotMintedIncreasingInterestTGE;
    let securitizationPoolValueService;
    let distributionAssessor;

    // Wallets
    let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer;
    before('create fixture', async () => {
        [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer] =
            await ethers.getSigners();

        ({
            stableCoin,
            loanAssetTokenContract,
            defaultLoanAssetTokenValidator,
            loanInterestTermsContract,
            loanKernel,
            loanRepaymentRouter,
            securitizationManager,
            uniqueIdentity,
            distributionOperator,
            distributionTranche,
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
    });

    describe('#security pool', async () => {
        it('Create pool', async () => {
            await securitizationManager.grantRole(POOL_ADMIN_ROLE, poolCreatorSigner.address);
            // Create new pool
            let transaction = await securitizationManager.connect(poolCreatorSigner).newPoolInstance(
                utils.keccak256(Date.now()),
                poolCreatorSigner.address,
                utils.defaultAbiCoder.encode(
                    [
                        {
                            type: 'tuple',
                            components: [
                                {
                                    name: 'currency',
                                    type: 'address',
                                },
                                {
                                    name: 'minFirstLossCushion',
                                    type: 'uint32',
                                },
                                {
                                    name: 'validatorRequired',
                                    type: 'bool',
                                },
                                {
                                    name: 'debtCeiling',
                                    type: 'uint256',
                                },
                            ],
                        },
                    ],
                    [
                        {
                            currency: stableCoin.address,
                            minFirstLossCushion: '100000',
                            validatorRequired: true,
                            debtCeiling: parseEther('1000').toString(),
                        },
                    ]
                )
            );

            let receipt = await transaction.wait();
            let [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;

            securitizationPoolContract = await getPoolByAddress(securitizationPoolAddress);
            await securitizationPoolContract
                .connect(poolCreatorSigner)
                .grantRole(ORIGINATOR_ROLE, originatorSigner.address);

            transaction = await securitizationManager.connect(poolCreatorSigner).newPoolInstance(
                utils.keccak256(Date.now()),

                poolCreatorSigner.address,
                utils.defaultAbiCoder.encode(
                    [
                        {
                            type: 'tuple',
                            components: [
                                {
                                    name: 'currency',
                                    type: 'address',
                                },
                                {
                                    name: 'minFirstLossCushion',
                                    type: 'uint32',
                                },
                                {
                                    name: 'validatorRequired',
                                    type: 'bool',
                                },
                                {
                                    name: 'debtCeiling',
                                    type: 'uint256',
                                },
                            ],
                        },
                    ],
                    [
                        {
                            currency: stableCoin.address,
                            minFirstLossCushion: '100000',
                            validatorRequired: true,
                            debtCeiling: parseEther('1000').toString(),
                        },
                    ]
                )
            );
            receipt = await transaction.wait();
            [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;

            secondSecuritizationPool = await getPoolByAddress(securitizationPoolAddress);
            await secondSecuritizationPool
                .connect(poolCreatorSigner)
                .grantRole(ORIGINATOR_ROLE, originatorSigner.address);

            await securitizationPoolContract
                .connect(poolCreatorSigner)
                .grantRole(ORIGINATOR_ROLE, untangledAdminSigner.address);

            const oneDayInSecs = 1 * 24 * 3600;
            const halfOfADay = oneDayInSecs / 2;

            const riskScore = {
                daysPastDue: oneDayInSecs,
                advanceRate: 950000,
                penaltyRate: 900000,
                interestRate: 910000,
                probabilityOfDefault: 800000,
                lossGivenDefault: 810000,
                discountRate: 100000,
                gracePeriod: halfOfADay,
                collectionPeriod: halfOfADay,
                writeOffAfterGracePeriod: halfOfADay,
                writeOffAfterCollectionPeriod: halfOfADay,
            };
            const daysPastDues = [riskScore.daysPastDue];
            const ratesAndDefaults = [
                riskScore.advanceRate,
                riskScore.penaltyRate,
                riskScore.interestRate,
                riskScore.probabilityOfDefault,
                riskScore.lossGivenDefault,
                riskScore.discountRate,
            ];
            const periodsAndWriteOffs = [
                riskScore.gracePeriod,
                riskScore.collectionPeriod,
                riskScore.writeOffAfterGracePeriod,
                riskScore.writeOffAfterCollectionPeriod,
            ];

            await securitizationPoolContract
                .connect(poolCreatorSigner)
                .setupRiskScores(daysPastDues, ratesAndDefaults, periodsAndWriteOffs);
        });

        it('Wrong risk scores', async () => {
            const oneDayInSecs = 1 * 24 * 3600;
            const halfOfADay = oneDayInSecs / 2;

            const riskScore = {
                daysPastDue: oneDayInSecs,
                advanceRate: 950000,
                penaltyRate: 900000,
                interestRate: 910000,
                probabilityOfDefault: 800000,
                lossGivenDefault: 810000,
                discountRate: 100000,
                gracePeriod: halfOfADay,
                collectionPeriod: halfOfADay,
                writeOffAfterGracePeriod: halfOfADay,
                writeOffAfterCollectionPeriod: halfOfADay,
            };
            const daysPastDues = [riskScore.daysPastDue, riskScore.daysPastDue];
            const ratesAndDefaults = [
                riskScore.advanceRate,
                riskScore.penaltyRate,
                riskScore.interestRate,
                riskScore.probabilityOfDefault,
                riskScore.lossGivenDefault,
                riskScore.discountRate,
                riskScore.advanceRate,
                riskScore.penaltyRate,
                riskScore.interestRate,
                riskScore.probabilityOfDefault,
                riskScore.lossGivenDefault,
                riskScore.discountRate,
            ];
            const periodsAndWriteOffs = [
                riskScore.gracePeriod,
                riskScore.collectionPeriod,
                riskScore.writeOffAfterGracePeriod,
                riskScore.writeOffAfterCollectionPeriod,
                riskScore.gracePeriod,
                riskScore.collectionPeriod,
                riskScore.writeOffAfterGracePeriod,
                riskScore.writeOffAfterCollectionPeriod,
            ];

            await expect(
                securitizationPoolContract
                    .connect(poolCreatorSigner)
                    .setupRiskScores(daysPastDues, ratesAndDefaults, periodsAndWriteOffs)
            ).to.be.revertedWith(`SecuritizationPool: Risk scores must be sorted`);
        });
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

    describe('#Distribution Operator', async () => {
        it('#makeRedeemRequestAndRedeem SOT', async () => {
            await sotToken.connect(lenderSigner).approve(distributionTranche.address, unlimitedAllowance);
            await distributionOperator
                .connect(lenderSigner)
                .makeRedeemRequestAndRedeem(securitizationPoolContract.address, sotToken.address, parseEther('10'));

            expect(formatEther(await sotToken.balanceOf(lenderSigner.address))).equal('90.0');
        });

        it('#makeRedeemRequestAndRedeem JOT', async () => {
            await jotToken.connect(lenderSigner).approve(distributionTranche.address, unlimitedAllowance);
            await distributionOperator
                .connect(lenderSigner)
                .makeRedeemRequestAndRedeem(securitizationPoolContract.address, jotToken.address, parseEther('10'));

            expect(formatEther(await jotToken.balanceOf(lenderSigner.address))).equal('90.0');
        });
    });

    let expirationTimestamps;
    const CREDITOR_FEE = '0';
    const ASSET_PURPOSE_LOAN = '0';
    const ASSET_PURPOSE_INVOICE = '1';
    const inputAmount = 10;
    const inputPrice = 15;
    const principalAmount = 10000000000000000000;

    describe('#LoanKernel', async () => {
        it('Execute fillDebtOrder successfully', async () => {
            const orderAddresses = [
                securitizationPoolContract.address,
                stableCoin.address,
                loanRepaymentRouter.address,
                loanInterestTermsContract.address,
                relayer.address,
                // borrower 1
                borrowerSigner.address,
                // borrower 2
                borrowerSigner.address,
            ];

            const riskScore = '1';
            expirationTimestamps = dayjs(new Date()).add(7, 'days').unix();

            const orderValues = [
                CREDITOR_FEE,
                ASSET_PURPOSE_LOAN,
                // token 1
                principalAmount.toString(),
                principalAmount.toString(),
                // token 2
                expirationTimestamps,
                expirationTimestamps,
                genSalt(),
                genSalt(),
                riskScore,
                riskScore,
            ];

            const termInDaysLoan = 10;
            const interestRatePercentage = 5;
            const termsContractParameter = packTermsContractParameters({
                amortizationUnitType: 1,
                gracePeriodInDays: 2,
                principalAmount,
                termLengthUnits: _.ceil(termInDaysLoan * 24),
                interestRateFixedPoint: interestRateFixedPoint(interestRatePercentage),
            });

            const termsContractParameters = [termsContractParameter, termsContractParameter];

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

            const ownerOfAgreement = await loanAssetTokenContract.ownerOf(tokenIds[0]);
            expect(ownerOfAgreement).equal(securitizationPoolContract.address);

            const balanceOfPool = await loanAssetTokenContract.balanceOf(securitizationPoolContract.address);
            expect(balanceOfPool).equal(tokenIds.length);

            await expect(
                loanKernel.fillDebtOrder(
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
                )
            ).to.be.revertedWith(`ERC721: token already minted`);
        });
    });

    describe('#Distribution Accessor', async () => {
        it('#calcCorrespondingTotalAssetValue', async () => {
            let result = await distributionAssessor.calcCorrespondingTotalAssetValue(
                sotToken.address,
                lenderSigner.address
            );
            expect(formatEther(result)).equal('90.0');

            result = await distributionAssessor.calcCorrespondingTotalAssetValue(
                jotToken.address,
                lenderSigner.address
            );

            expect(result).to.closeTo(parseEther('90.18'), parseEther('0.01'));
        });

        it('#calcCorrespondingAssetValue(address,address[])', async () => {
            const result = await distributionAssessor['calcCorrespondingAssetValue(address,address[])'](
                sotToken.address,
                [lenderSigner.address]
            );
            expect(result.map((x) => formatEther(x))).to.deep.equal(['90.0']);
        });

        it('#calcTokenPrice', async () => {
            let result = await distributionAssessor.calcTokenPrice(
                securitizationPoolContract.address,
                sotToken.address
            );
            expect(formatEther(result)).equal('1.0');

            result = await distributionAssessor.calcTokenPrice(securitizationPoolContract.address, jotToken.address);
            expect(result).to.closeTo(parseEther('1.002'), parseEther('0.001'));

            result = await distributionAssessor.calcTokenPrice(securitizationPoolContract.address, ZERO_ADDRESS);
            expect(formatEther(result)).equal('0.0');
        });

        it('#getCashBalance', async () => {
            const result = await distributionAssessor.getCashBalance(securitizationPoolContract.address);
            expect(result).to.closeTo(parseEther('161.000'), parseEther('0.001'));
        });
    });

    describe('Burn agreement', async () => {
        it('only LoanKernel contract can burn', async () => {
            await loanRepaymentRouter
                .connect(untangledAdminSigner)
                .repayInBatch([tokenIds[0]], [parseEther('100')], stableCoin.address);

            await expect(loanAssetTokenContract.ownerOf(tokenIds[0])).to.be.revertedWith(`ERC721: invalid token ID`);
        });
    });
});
