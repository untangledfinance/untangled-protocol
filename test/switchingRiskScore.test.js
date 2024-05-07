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

describe('switching-riskscore', () => {
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
                {
                    daysPastDue: 2 * oneDayInSecs,
                    advanceRate: 1000000, // 100%
                    penaltyRate: 900000, // 90%
                    interestRate: 157000, // 15.7%
                    probabilityOfDefault: 50000, // 5%
                    lossGivenDefault: 500000, // 50%
                    gracePeriod: halfOfADay,
                    collectionPeriod: halfOfADay,
                    writeOffAfterGracePeriod: halfOfADay,
                    writeOffAfterCollectionPeriod: halfOfADay,
                    discountRate: 157000, // 15.7%
                },
                {
                    daysPastDue: 3 * oneDayInSecs,
                    advanceRate: 1000000, // 100%
                    penaltyRate: 900000, // 90%
                    interestRate: 157000, // 15.7%
                    probabilityOfDefault: 500000, // 50%
                    lossGivenDefault: 1000000, // 100%
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
            const loans = [
                {
                    principalAmount: drawdownAmount,
                    expirationTimestamp: (await time.latest()) + 3600 * 24 * 900,
                    assetPurpose: ASSET_PURPOSE.LOAN,
                    termInDays: 900,
                    riskScore: '1',
                    salt: genSalt(),
                },
            ];
            await securitizationPoolContract
                .connect(poolCreatorSigner)
                .grantRole(ORIGINATOR_ROLE, untangledAdminSigner.address);
            const { expectedLoansValue } = await untangledProtocol.getLoansValue(
                untangledAdminSigner,
                securitizationPoolContract,
                borrowerSigner,
                ASSET_PURPOSE.LOAN,
                loans
            );
            console.log('expected loan value: ', formatEther(expectedLoansValue));
            tokenIds = await untangledProtocol.uploadLoans(
                untangledAdminSigner,
                securitizationPoolContract,
                borrowerSigner,
                ASSET_PURPOSE.LOAN,
                loans
            );
            console.log('current NAV: ', formatEther(await securitizationPoolContract.currentNAV()));
            const ownerOfAggreement = await loanAssetTokenContract.ownerOf(tokenIds[0]);
            expect(ownerOfAggreement).equal(securitizationPoolContract.address);

            const poolBalance = await loanAssetTokenContract.balanceOf(securitizationPoolContract.address);
            expect(poolBalance).equal(tokenIds.length);
            await time.increase(877806);
        });

        it('change riskscore', async () => {
            console.log('Before risk score change');
            console.log('current NAV: ', formatEther(await securitizationPoolContract.currentNAV()));
            console.log('total debt: ', formatEther(await securitizationPoolContract.debt(tokenIds[0])));
            await securitizationPoolContract
                .connect(poolCreatorSigner)
                .updateAssetRiskScore(tokenIds[0], 2, { gasLimit: 10000000 });
            console.log('===========================================');
            console.log('After riskscore change');
            console.log('current NAV: ', formatEther(await securitizationPoolContract.currentNAVAsset(tokenIds[0])));
            console.log('total debt: ', formatEther(await securitizationPoolContract.debt(tokenIds[0])));
            await time.increase(10 * 3600 * 24);
        });
        it('10 days after riskscores change', async () => {
            console.log('10 days later');
            console.log('current NAV: ', formatEther(await securitizationPoolContract.currentNAVAsset(tokenIds[0])));
            console.log('total debt: ', formatEther(await securitizationPoolContract.debt(tokenIds[0])));
        });
    });
});
