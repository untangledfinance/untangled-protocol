const { ethers } = require('hardhat');
const _ = require('lodash');
const { expect } = require('chai');
const dayjs = require('dayjs');
const { time } = require('@nomicfoundation/hardhat-network-helpers');
const { parseEther, formatEther } = ethers.utils;
const UntangledProtocol = require('./shared/untangled-protocol');
const { setup } = require('./setup');
const { SaleType, ASSET_PURPOSE } = require('./shared/constants');
const { OWNER_ROLE, POOL_ADMIN_ROLE, BACKEND_ADMIN, ORIGINATOR_ROLE } = require('./constants.js');
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
const { BigNumber } = require('ethers');

describe('riskscore-change', () => {
    let stableCoin,
        loanAssetTokenContract,
        loanKernel,
        loanRepaymentRouter,
        securitizationManager,
        distributionTranche,
        securitizationPoolContract,
        tokenIds,
        uniqueIdentity,
        distributionOperator,
        sotToken,
        jotToken,
        mintedIncreasingInterestTGE,
        jotMintedIncreasingInterestTGE,
        factoryAdmin,
        securitizationPoolValueService,
        securitizationPoolImpl,
        defaultLoanAssetTokenValidator,
        loanRegistry,
        untangledProtocol;
    let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer;
    const drawdownAmount = 100000000000000000000000n;
    const oneDayInSecs = 24 * 3600;
    const halfOfADay = oneDayInSecs / 2;
    let totalRepay = BigNumber.from(0);
    before('create fixture', async () => {
        [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer] =
            await ethers.getSigners();
        const contracts = await setup();
        untangledProtocol = UntangledProtocol.bind(contracts);
        ({
            stableCoin,
            loanAssetTokenContract,
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
            loanRegistry,
        } = contracts);

        await stableCoin.transfer(lenderSigner.address, parseEther('2000000'));

        await stableCoin.connect(untangledAdminSigner).approve(loanRepaymentRouter.address, unlimitedAllowance);

        await untangledProtocol.mintUID(lenderSigner);
    });

    describe('#intialize suit', async () => {
        it('Create pool & TGEs', async () => {
            // const OWNER_ROLE = await securitizationManager.OWNER_ROLE();
            await securitizationManager.setRoleAdmin(POOL_ADMIN_ROLE, OWNER_ROLE);

            await securitizationManager.grantRole(OWNER_ROLE, borrowerSigner.address);
            await securitizationManager.connect(borrowerSigner).grantRole(POOL_ADMIN_ROLE, poolCreatorSigner.address);

            const poolParams = {
                currency: 'cUSD',
                minFirstLossCushion: 20,
                validatorRequired: true,
                debtCeiling: 2000000,
            };

            const riskScores = [
                {
                    daysPastDue: oneDayInSecs,
                    advanceRate: 1000000, // 100%
                    penaltyRate: 900000, // 90%
                    interestRate: 157000, // 15.7%
                    probabilityOfDefault: 1000, // 0.1%
                    lossGivenDefault: 250000, // 25%
                    gracePeriod: halfOfADay,
                    collectionPeriod: halfOfADay,
                    writeOffAfterGracePeriod: halfOfADay,
                    writeOffAfterCollectionPeriod: halfOfADay,
                    discountRate: 157000, // 15.7%
                },
            ];

            const openingTime = dayjs(new Date()).unix();
            const closingTime = dayjs(new Date()).add(7, 'days').unix();
            const rate = 2;
            const totalCapOfToken = parseEther('1000000');
            const interestRate = 10000; // 1.5%
            const timeInterval = 1 * 24 * 3600; // seconds
            const amountChangeEachInterval = 0;
            const prefixOfNoteTokenSaleName = 'Ticker_';
            const sotInfo = {
                issuerTokenController: untangledAdminSigner.address,
                saleType: SaleType.MINTED_INCREASING_INTEREST,
                minBidAmount: parseEther('5000'),
                openingTime,
                closingTime,
                rate,
                cap: totalCapOfToken,
                timeInterval,
                amountChangeEachInterval,
                ticker: prefixOfNoteTokenSaleName,
                interestRate,
            };

            const initialJOTAmount = parseEther('100');
            const jotInfo = {
                issuerTokenController: untangledAdminSigner.address,
                minBidAmount: parseEther('5000'),
                saleType: SaleType.NORMAL_SALE,
                longSale: true,
                ticker: prefixOfNoteTokenSaleName,
                openingTime: openingTime,
                closingTime: closingTime,
                rate: rate,
                cap: totalCapOfToken,
                initialJOTAmount,
            };
            const [poolAddress, sotCreated, jotCreated] = await untangledProtocol.createFullPool(
                poolCreatorSigner,
                poolParams,
                riskScores,
                sotInfo,
                jotInfo
            );
            securitizationPoolContract = await getPoolByAddress(poolAddress);
            mintedIncreasingInterestTGE = await ethers.getContractAt('MintedNormalTGE', sotCreated.sotTGEAddress);
            jotMintedIncreasingInterestTGE = await ethers.getContractAt('MintedNormalTGE', jotCreated.jotTGEAddress);
        });

        it('invest 1,000,000$ JOT', async () => {
            await untangledProtocol.buyToken(
                lenderSigner,
                jotMintedIncreasingInterestTGE.address,
                parseEther('1000000')
            );
            expect(formatEther(await stableCoin.balanceOf(securitizationPoolContract.address))).equal('1000000.0');

            let tokenPrice = await securitizationPoolContract.calcTokenPrices();
            expect(tokenPrice[0]).to.be.eq(parseEther('1'));
        });

        it('drawdown $100,000', async () => {
            const loanParam = {
                orderAddresses: [
                    '0xf24a7a2a548120494b002166a63b2d4739963fda',
                    '0x6f48Ef99a294d5C9F394A0a08f4149b1f350441a',
                    '0x3828A20e026d4332CdEb8aDa9C2D21502d71885a',
                    '0x0000000000000000000000000000000000000000',
                    '0x0000000000000000000000000000000000000000',
                ],
                orderValues: [0, 0, '1250000000', '1250000000', 1706288400, 1712336400, 8364207077, 5123848855, 3, 1],
                termsContractParameters: [
                    '0x0000000000000000004a817c8001d4c010000000000000000000002700200000',
                    '0x0000000000000000004a817c8001388010000000000000000000008e80200000',
                ],
                latInfo: [
                    {
                        tokenIds: [
                            '0xf8ec6da64b3a5106efa55cbb6ac8bd9d8c9c86a8cf2d9050e1284e6de61a9b0c',
                            '0x1da3a8b35d60d5ba711a0a67b84df142960a29dc378020f5d2aa32bad60daf94',
                        ],
                        nonces: ['0', '0'],
                        validator: '0x0000000000000000000000000000000000000000',
                        validateSignature: '0x',
                    },
                ],
            };
            console.log('expected loan value: ', await loanKernel.getLoansValue(loanParam));
        });
    });
});
