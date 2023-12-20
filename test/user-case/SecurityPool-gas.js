const { ethers, artifacts } = require('hardhat');
const _ = require('lodash');
const dayjs = require('dayjs');
const { expect } = require('chai');
const { time } = require('@nomicfoundation/hardhat-network-helpers');

const { constants } = ethers;
const { parseEther, formatEther } = ethers.utils;
const { presignedMintMessage } = require('../shared/uid-helper.js');
const { impersonateAccount, setBalance } = require('@nomicfoundation/hardhat-network-helpers');

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
    getPoolAbi,
    formatFillDebtOrderParams,
} = require('../utils.js');
const { setup } = require('../setup.js');
const { SaleType } = require('../shared/constants.js');

const { POOL_ADMIN_ROLE, ORIGINATOR_ROLE } = require('../constants.js');
const { utils, Contract } = require('ethers');

const RATE_SCALING_FACTOR = 10 ** 4;

describe('SecuritizationPool', () => {
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
    let factoryAdmin;
    let securitizationPoolImpl;
    let defaultLoanAssetTokenValidator;

    // Wallets
    let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer;
    before('create fixture', async () => {
        [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer] =
            await ethers.getSigners();

        ({
            stableCoin,
            loanAssetTokenContract,
            loanInterestTermsContract,
            loanKernel,
            loanRepaymentRouter,
            securitizationManager,
            uniqueIdentity,
            distributionOperator,
            distributionTranche,
            securitizationPoolValueService,
            factoryAdmin,
            securitizationPoolImpl,
            defaultLoanAssetTokenValidator,
        } = await setup());

        await stableCoin.transfer(lenderSigner.address, parseEther('1000'));

        await stableCoin.connect(untangledAdminSigner).approve(loanRepaymentRouter.address, unlimitedAllowance);

        // Gain UID
        const UID_TYPE = 0;
        const chainId = await getChainId();
        const expiredAt = dayjs().unix() + 86400 * 1000;
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
            const OWNER_ROLE = await securitizationManager.OWNER_ROLE();
            await securitizationManager.setRoleAdmin(POOL_ADMIN_ROLE, OWNER_ROLE);

            await securitizationManager.grantRole(OWNER_ROLE, borrowerSigner.address);
            await securitizationManager.connect(borrowerSigner).grantRole(POOL_ADMIN_ROLE, poolCreatorSigner.address);

            const salt = utils.keccak256(Date.now());

            // Create new pool
            let transaction = await securitizationManager
                .connect(poolCreatorSigner)

                .newPoolInstance(
                    salt,

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
                                debtCeiling: parseEther('300').toString(),
                            },
                        ]
                    )
                );

            let receipt = await transaction.wait();
            let [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;

            // expect address, create2
            const { bytecode } = await artifacts.readArtifact('TransparentUpgradeableProxy');
            // abi.encodePacked(
            //     type(TransparentUpgradeableProxy).creationCode,
            //     abi.encode(_poolImplAddress, address(this), '')
            // )
            const initCodeHash = utils.keccak256(
                utils.solidityPack(
                    ['bytes', 'bytes'],
                    [
                        `${bytecode}`,
                        utils.defaultAbiCoder.encode(
                            ['address', 'address', 'bytes'],
                            [securitizationPoolImpl.address, securitizationManager.address, Buffer.from([])]
                        ),
                    ]
                )
            );

            const create2 = utils.getCreate2Address(securitizationManager.address, salt, initCodeHash);
            expect(create2).to.be.eq(securitizationPoolAddress);

            securitizationPoolContract = await getPoolByAddress(securitizationPoolAddress);
            await securitizationPoolContract
                .connect(poolCreatorSigner)
                .grantRole(ORIGINATOR_ROLE, originatorSigner.address);
            await securitizationPoolContract
                .connect(poolCreatorSigner)
                .grantRole(ORIGINATOR_ROLE, untangledAdminSigner.address);

            expect(await securitizationPoolContract.debtCeiling()).equal(parseEther('300'));

            transaction = await securitizationManager
                .connect(poolCreatorSigner)

                .newPoolInstance(
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
                                debtCeiling: parseEther('99999999999999').toString(),
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
                    minBidAmount: parseEther('50'),
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
            const initialJOTAmount = parseEther('1');
            const prefixOfNoteTokenSaleName = 'JOT_';

            // JOT only has SaleType.NORMAL_SALE
            const transaction = await securitizationManager.connect(poolCreatorSigner).setUpTGEForJOT(
                {
                    issuerTokenController: untangledAdminSigner.address,
                    pool: securitizationPoolContract.address,
                    minBidAmount: parseEther('50'),
                    saleType: SaleType.NORMAL_SALE,
                    longSale: true,
                    ticker: prefixOfNoteTokenSaleName,
                },
                { openingTime: openingTime, closingTime: closingTime, rate: rate, cap: totalCapOfToken },
                initialJOTAmount
            );
            const receipt = await transaction.wait();

            const [tgeAddress] = receipt.events.find((e) => e.event == 'NewTGECreated').args;
            expect(tgeAddress).to.be.properAddress;

            jotMintedIncreasingInterestTGE = await ethers.getContractAt('MintedIncreasingInterestTGE', tgeAddress);

            const [jotTokenAddress] = receipt.events.find((e) => e.event == 'NewNotesTokenCreated').args;
            expect(jotTokenAddress).to.be.properAddress;

            jotToken = await ethers.getContractAt('NoteToken', jotTokenAddress);
        });

        it('Should buy tokens successfully', async () => {
            await stableCoin.connect(lenderSigner).approve(jotMintedIncreasingInterestTGE.address, unlimitedAllowance);
            await stableCoin.connect(lenderSigner).approve(mintedIncreasingInterestTGE.address, unlimitedAllowance);
            await securitizationManager
                .connect(lenderSigner)
                .buyTokens(jotMintedIncreasingInterestTGE.address, parseEther('100'));

            await securitizationManager
                .connect(lenderSigner)
                .buyTokens(mintedIncreasingInterestTGE.address, parseEther('100'));

            const stablecoinBalanceOfPayerAfter = await stableCoin.balanceOf(lenderSigner.address);
            expect(formatEther(stablecoinBalanceOfPayerAfter)).equal('800.0');

            expect(formatEther(await stableCoin.balanceOf(securitizationPoolContract.address))).equal('200.0');
        });
    });

    let expirationTimestamps;
    const CREDITOR_FEE = '0';
    const ASSET_PURPOSE_LOAN = '0';
    const ASSET_PURPOSE_INVOICE = '1';
    const inputAmount = 10;
    const inputPrice = 15;
    const principalAmount = _.round(inputAmount * inputPrice * 100);

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
                borrowerSigner.address,
                borrowerSigner.address,
            ];

            const riskScore = '1';
            expirationTimestamps = dayjs(new Date()).add(7, 'days').unix();

            const orderValues = [
                CREDITOR_FEE,
                ASSET_PURPOSE_LOAN,
                parseEther(principalAmount.toString()), // token 1
                parseEther(principalAmount.toString()), // token 2
                parseEther(principalAmount.toString()),
                parseEther(principalAmount.toString()),
                expirationTimestamps,
                expirationTimestamps,
                expirationTimestamps,
                expirationTimestamps,
                genSalt(),
                genSalt(),
                genSalt(),
                genSalt(),
                riskScore,
                riskScore,
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

            const termsContractParameters = [
                termsContractParameter,
                termsContractParameter,
                termsContractParameter,
                termsContractParameter,
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

            const tx = await loanKernel.fillDebtOrder(
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

            console.log('TxXXX', (await tx.wait()).gasUsed);
        });
    });
});
