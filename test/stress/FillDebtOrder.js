const { ethers, upgrades } = require('hardhat');
const { snapshot } = require('@openzeppelin/test-helpers');
const _ = require('lodash');
const dayjs = require('dayjs');
const { expect } = require('chai');

const { BigNumber, constants } = ethers;
const { parseEther, formatEther } = ethers.utils;

const {
    unlimitedAllowance,
    genLoanAgreementIds,
    saltFromOrderValues,
    debtorsFromOrderAddresses,
    packTermsContractParameters,
    interestRateFixedPoint,
    genSalt,
    generateLATMintPayload,
    getPoolByAddress,
    formatFillDebtOrderParams,
    ZERO_ADDRESS,
} = require('../utils.js');
const { setup } = require('../setup.js');

const { POOL_ADMIN_ROLE, ORIGINATOR_ROLE } = require('../constants.js');
const { utils } = require('ethers');
const { presignedMintMessage } = require('../shared/uid-helper.js');
const { SaleType } = require('../shared/constants.js');
const LAT_AMOUNT = 10;

async function getFillDebtOrderParameters(
    signer,
    securitizationPoolContract,
    relayer,
    borrowerSigner,
    assetPurpose,
    loans
) {
    const CREDITOR_FEE = '0';

    const orderAddresses = [
        securitizationPoolContract.address,
        this.stableCoin.address,
        this.loanRepaymentRouter.address,
        relayer.address,
        // borrower 1
        // borrower 2
        // ...
        ...new Array(loans.length).fill(borrowerSigner.address),
    ];

    const orderValues = [
        CREDITOR_FEE,
        assetPurpose,
        ...loans.map((l) => parseEther(l.principalAmount.toString())),
        ...loans.map((l) => l.expirationTimestamp),
        ...loans.map((l) => l.salt || genSalt()),
        ...loans.map((l) => l.riskScore),
    ];

    const interestRatePercentage = 5;

    const termsContractParameters = loans.map((l) =>
        packTermsContractParameters({
            amortizationUnitType: 1,
            gracePeriodInDays: 2,
            principalAmount: l.principalAmount,
            termLengthUnits: _.ceil(l.termInDays * 24),
            interestRateFixedPoint: interestRateFixedPoint(interestRatePercentage),
        })
    );

    const salts = saltFromOrderValues(orderValues, termsContractParameters.length);
    const debtors = debtorsFromOrderAddresses(orderAddresses, termsContractParameters.length);

    const tokenIds = genLoanAgreementIds(this.loanRepaymentRouter.address, debtors, termsContractParameters, salts);

    return {
        fillDebtOrderParams: formatFillDebtOrderParams(
            orderAddresses,
            orderValues,
            termsContractParameters,
            await Promise.all(
                tokenIds.map(async (x) => ({
                    ...(await generateLATMintPayload(
                        this.loanAssetTokenContract,
                        this.defaultLoanAssetTokenValidator,
                        [x],
                        [(await this.loanAssetTokenContract.nonce(x)).toNumber()],
                        this.defaultLoanAssetTokenValidator.address
                    )),
                }))
            )
        ),
        tokenIds,
    };
}

describe('FillDebtOrder - Stress test', () => {
    let stableCoin;
    let registry;
    let loanAssetTokenContract;
    let loanRegistry;
    let loanKernel;
    let loanRepaymentRouter;
    let securitizationManager;
    let securitizationPoolContract;
    let tokenIds;
    let defaultLoanAssetTokenValidator;
    let uniqueIdentity;
    let sotToken;
    let jotToken;
    let contracts;
    let mintedIncreasingInterestTGE;
    let jotMintedIncreasingInterestTGE;
    let securitizationPoolValueService;
    let securitizationPoolImpl;
    let distributionAssessor;
    let chainId;
    // Wallets
    let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer;
    before('create fixture', async () => {
        [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer] =
            await ethers.getSigners();

        contracts = await setup();
        ({
            stableCoin,
            registry,
            loanAssetTokenContract,
            loanRegistry,
            loanKernel,
            loanRepaymentRouter,
            securitizationManager,
            securitizationPoolValueService,
            securitizationPoolImpl,
            defaultLoanAssetTokenValidator,
            uniqueIdentity,
            distributionAssessor,
        } = contracts);

        await stableCoin.mint(parseEther('1000000'));
        await stableCoin.transfer(lenderSigner.address, parseEther('1000000'));

        await stableCoin.connect(untangledAdminSigner).approve(loanRepaymentRouter.address, unlimitedAllowance);

        // Gain UID
        const UID_TYPE = 0;
        chainId = await getChainId();
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
            const transaction = await securitizationManager.connect(poolCreatorSigner).newPoolInstance(
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
                            debtCeiling: parseEther('20000').toString(),
                        },
                    ]
                )
            );

            const receipt = await transaction.wait();
            const [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;

            securitizationPoolContract = await getPoolByAddress(securitizationPoolAddress);
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
                gracePeriod: halfOfADay,
                collectionPeriod: halfOfADay,
                writeOffAfterGracePeriod: halfOfADay,
                writeOffAfterCollectionPeriod: halfOfADay,
                discountRate: 100000,
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
    });

    describe('Raise fund for pool', async () => {
        it('Set up TGE for SOT', async () => {
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

        it('Set up TGE for JOT', async () => {
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

        it('Buy tokens', async () => {
            await stableCoin.connect(lenderSigner).approve(mintedIncreasingInterestTGE.address, unlimitedAllowance);

            await stableCoin.connect(lenderSigner).approve(jotMintedIncreasingInterestTGE.address, unlimitedAllowance);
            await securitizationManager
                .connect(lenderSigner)
                .buyTokens(jotMintedIncreasingInterestTGE.address, parseEther('10000'));

            await securitizationManager
                .connect(lenderSigner)
                .buyTokens(mintedIncreasingInterestTGE.address, parseEther('10000'));

            const stablecoinBalanceOfPayerAfter = await stableCoin.balanceOf(lenderSigner.address);
            // expect(formatEther(stablecoinBalanceOfPayerAfter)).equal('800.0');

            // expect(formatEther(await stableCoin.balanceOf(securitizationPoolContract.address))).equal('200.0');

            const sotValue = await distributionAssessor.calcCorrespondingTotalAssetValue(
                sotToken.address,
                lenderSigner.address
            );
            // expect(formatEther(sotValue)).equal('100.0');
        });
    });

    const ASSET_PURPOSE = '0';
    const principalAmount = 100;

    describe('#Upload loan', async () => {
        it(`Upload 10 loans`, async () => {
            const snap = await snapshot();

            // grant AA as Validator
            const [, , , , newValidatorSigner] = await ethers.getSigners();
            const aa = await upgrades.deployProxy(await ethers.getContractFactory('AAWallet'), []);
            await securitizationManager.registerValidator(aa.address);

            /*
            const loans = [
                {
                    principalAmount,
                    expirationTimestamp: dayjs(new Date()).add(7, 'days').unix(),
                    termInDays: 10,
                    riskScore: '1'
                },
            ]
*/
            const loans = new Array(LAT_AMOUNT).fill({
                principalAmount,
                expirationTimestamp: dayjs(new Date()).add(7, 'days').unix(),
                termInDays: 10,
                riskScore: '1',
            });

            // add whitelist & try again
            await aa.grantRole(await aa.VALIDATOR_ROLE(), newValidatorSigner.address);

            let fillDebtOrderParams;
            ({ fillDebtOrderParams, tokenIds } = await getFillDebtOrderParameters.bind(contracts)(
                untangledAdminSigner,
                securitizationPoolContract,
                relayer,
                borrowerSigner,
                ASSET_PURPOSE,
                loans
            ));
            await loanKernel.fillDebtOrder(fillDebtOrderParams);

            const ownerOfAgreement = await loanAssetTokenContract.ownerOf(tokenIds[0]);
            expect(ownerOfAgreement).equal(securitizationPoolContract.address);

            const balanceOfPool = await loanAssetTokenContract.balanceOf(securitizationPoolContract.address);
            expect(balanceOfPool).equal(tokenIds.length);

            await snap.restore();
        });

        it(`Upload 100 loans`, async () => {
            const loans = new Array(30).fill({
                principalAmount,
                expirationTimestamp: dayjs(new Date()).add(7, 'days').unix(),
                termInDays: 10,
                riskScore: '1',
            });

            let fillDebtOrderParams;
            ({ fillDebtOrderParams, tokenIds } = await getFillDebtOrderParameters.bind(contracts)(
                untangledAdminSigner,
                securitizationPoolContract,
                relayer,
                borrowerSigner,
                ASSET_PURPOSE,
                loans
            ));
            await loanKernel.fillDebtOrder(fillDebtOrderParams);

            const ownerOfAgreement = await loanAssetTokenContract.ownerOf(tokenIds[0]);
            expect(ownerOfAgreement).equal(securitizationPoolContract.address);
        });
    });
});
