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

describe('integration-test', () => {
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

            const oneDayInSecs = 24 * 3600;
            const halfOfADay = oneDayInSecs / 2;
            const riskScores = [
                {
                    daysPastDue: oneDayInSecs,
                    advanceRate: 850000, // 85%
                    penaltyRate: 900000, // 90%
                    interestRate: 120000, // 12%
                    probabilityOfDefault: 30000, // 3%
                    lossGivenDefault: 500000, // 50%
                    gracePeriod: halfOfADay,
                    collectionPeriod: halfOfADay,
                    writeOffAfterGracePeriod: halfOfADay,
                    writeOffAfterCollectionPeriod: halfOfADay,
                    discountRate: 100000, // 10%
                },
                {
                    daysPastDue: oneDayInSecs * 2,
                    advanceRate: 750000, // 75%
                    penaltyRate: 900000, // 90%
                    interestRate: 150000, // 15%
                    probabilityOfDefault: 250000, // 25%
                    lossGivenDefault: 1000000, // 100%
                    gracePeriod: halfOfADay,
                    collectionPeriod: halfOfADay,
                    writeOffAfterGracePeriod: halfOfADay,
                    writeOffAfterCollectionPeriod: halfOfADay,
                    discountRate: 100000, // 10%
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

        it('invest 20,000$ JOT', async () => {
            await untangledProtocol.buyToken(lenderSigner, jotMintedIncreasingInterestTGE.address, parseEther('20000'));
            expect(formatEther(await stableCoin.balanceOf(securitizationPoolContract.address))).equal('20000.0');

            let tokenPrice = await securitizationPoolContract.calcTokenPrices();
            expect(tokenPrice[0]).to.be.eq(parseEther('1'));
            await time.increase(1520);
        });

        // it('invest 390,000$ JOT', async () => {
        //     await untangledProtocol.buyToken(
        //         lenderSigner,
        //         jotMintedIncreasingInterestTGE.address,
        //         parseEther('390000')
        //     );
        //     expect(formatEther(await stableCoin.balanceOf(securitizationPoolContract.address))).equal('400000.0');

        //     let tokenPrice = await securitizationPoolContract.calcTokenPrices();
        //     expect(tokenPrice[0]).to.be.eq(parseEther('1'));
        //     await time.increase(123675);
        // });

        it('drawdown $12,962.21$', async () => {
            const JPM2411 = 4568000000000000000000n;
            const JPM2412 = 3656000000000000000000n;
            const JPM2413 = 3500000000000000000000n;
            const JPM2414 = 1185000000000000000000n;
            const JPM2415 = 3858000000000000000000n;
            const loans = [
                {
                    principalAmount: JPM2411,
                    expirationTimestamp: (await time.latest()) + 3600 * 24 * 202,
                    assetPurpose: ASSET_PURPOSE.LOAN,
                    termInDays: 202,
                    riskScore: '2',
                    salt: genSalt(),
                },
                {
                    principalAmount: JPM2412,
                    expirationTimestamp: (await time.latest()) + 3600 * 24 * 135,
                    assetPurpose: ASSET_PURPOSE.LOAN,
                    termInDays: 135,
                    riskScore: '2',
                    salt: genSalt(),
                },
                {
                    principalAmount: JPM2413,
                    expirationTimestamp: (await time.latest()) + 3600 * 24 * 140,
                    assetPurpose: ASSET_PURPOSE.LOAN,
                    termInDays: 140,
                    riskScore: '2',
                    salt: genSalt(),
                },
                {
                    principalAmount: JPM2414,
                    expirationTimestamp: (await time.latest()) + 3600 * 24 * 202,
                    assetPurpose: ASSET_PURPOSE.LOAN,
                    termInDays: 202,
                    riskScore: '2',
                    salt: genSalt(),
                },
                {
                    principalAmount: JPM2415,
                    expirationTimestamp: (await time.latest()) + 3600 * 24 * 91,
                    assetPurpose: ASSET_PURPOSE.LOAN,
                    termInDays: 91,
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
            console.log("JPM2411's fv: ", formatEther(await securitizationPoolContract.futureValue(tokenIds[0])));
            console.log("JPM2412's fv: ", formatEther(await securitizationPoolContract.futureValue(tokenIds[1])));
            console.log("JPM2413's fv: ", formatEther(await securitizationPoolContract.futureValue(tokenIds[2])));
            console.log("JPM2414's fv: ", formatEther(await securitizationPoolContract.futureValue(tokenIds[3])));
            console.log("JPM2415's fv: ", formatEther(await securitizationPoolContract.futureValue(tokenIds[4])));
            console.log("JPM2411's NAV: ", formatEther(await securitizationPoolContract.currentNAVAsset(tokenIds[0])));
            console.log("JPM2412's NAV: ", formatEther(await securitizationPoolContract.currentNAVAsset(tokenIds[1])));
            console.log("JPM2413's NAV: ", formatEther(await securitizationPoolContract.currentNAVAsset(tokenIds[2])));
            console.log("JPM2414's NAV: ", formatEther(await securitizationPoolContract.currentNAVAsset(tokenIds[3])));
            console.log("JPM2415's NAV: ", formatEther(await securitizationPoolContract.currentNAVAsset(tokenIds[4])));
            const ownerOfAggreement = await loanAssetTokenContract.ownerOf(tokenIds[0]);
            expect(ownerOfAggreement).equal(securitizationPoolContract.address);

            const poolBalance = await loanAssetTokenContract.balanceOf(securitizationPoolContract.address);
            expect(poolBalance).equal(tokenIds.length);
            await time.increase(570);
        });

        it('invest 30,000$ SOT', async () => {
            await untangledProtocol.buyToken(lenderSigner, mintedIncreasingInterestTGE.address, parseEther('30000'));
            expect(formatEther(await stableCoin.balanceOf(securitizationPoolContract.address))).equal('37038.95');
            let tokenPrice = await securitizationPoolContract.calcTokenPrices();
            console.log('JOT price: ', formatEther(tokenPrice[0]));
            console.log('SOT price: ', formatEther(tokenPrice[1]));
            await time.increase(150);
        });

        it('repay $3,046.69$', async () => {
            const repayAmount = parseEther('3046.69');
            const poolBalanceBefore = await stableCoin.balanceOf(securitizationPoolContract.address);

            await loanKernel
                .connect(untangledAdminSigner)
                .repayInBatch([tokenIds[0]], [repayAmount], stableCoin.address);
            console.log('current NAV: ', formatEther(await securitizationPoolContract.currentNAV()));
            console.log('future value: ', formatEther(await securitizationPoolContract.futureValue(tokenIds[0])));
            const poolBalanceAfter = await stableCoin.balanceOf(securitizationPoolContract.address);
            expect(poolBalanceAfter).to.be.eq(ethers.BigNumber.from(poolBalanceBefore).add(repayAmount));
            let tokenPrice = await securitizationPoolContract.calcTokenPrices();
            console.log('JOT price: ', formatEther(tokenPrice[0]));
            console.log('SOT price: ', formatEther(tokenPrice[1]));
            let seniorAssets = await securitizationPoolContract.seniorDebtAndBalance();
            console.log('senior debt: ', formatEther(seniorAssets[0]));
            console.log('senior balance: ', formatEther(seniorAssets[1]));
            await time.increase(47825);
        });

        it('invest $97,500$ JOT', async () => {
            const poolBalanceBefore = await stableCoin.balanceOf(securitizationPoolContract.address);
            const investAmount = parseEther('97500');
            await untangledProtocol.buyToken(lenderSigner, jotMintedIncreasingInterestTGE.address, investAmount);
            console.log('current NAV: ', formatEther(await securitizationPoolContract.currentNAV()));
            console.log('future value: ', formatEther(await securitizationPoolContract.futureValue(tokenIds[0])));
            expect(await stableCoin.balanceOf(securitizationPoolContract.address)).to.be.eq(
                ethers.BigNumber.from(poolBalanceBefore).add(investAmount)
            );
            let tokenPrice = await securitizationPoolContract.calcTokenPrices();
            console.log('JOT price: ', formatEther(tokenPrice[0]));
            console.log('SOT price: ', formatEther(tokenPrice[1]));
            await time.increase(375);
        });

        it('invest 300,000$ SOT', async () => {
            const poolBalanceBefore = await stableCoin.balanceOf(securitizationPoolContract.address);
            const investAmount = parseEther('300000');

            await untangledProtocol.buyToken(lenderSigner, mintedIncreasingInterestTGE.address, investAmount);
            expect(await stableCoin.balanceOf(securitizationPoolContract.address)).to.be.eq(
                ethers.BigNumber.from(poolBalanceBefore).add(investAmount)
            );
            let tokenPrice = await securitizationPoolContract.calcTokenPrices();
            console.log('JOT price: ', formatEther(tokenPrice[0]));
            console.log('SOT price: ', formatEther(tokenPrice[1]));
            await time.increase(560);
        });

        it('invest 500,000$ JOT', async () => {
            const poolBalanceBefore = await stableCoin.balanceOf(securitizationPoolContract.address);
            const investAmount = parseEther('500000');
            await untangledProtocol.buyToken(lenderSigner, jotMintedIncreasingInterestTGE.address, investAmount);
            console.log('current NAV: ', formatEther(await securitizationPoolContract.currentNAV()));
            console.log('future value: ', formatEther(await securitizationPoolContract.futureValue(tokenIds[0])));
            expect(await stableCoin.balanceOf(securitizationPoolContract.address)).to.be.eq(
                ethers.BigNumber.from(poolBalanceBefore).add(investAmount)
            );
            let tokenPrice = await securitizationPoolContract.calcTokenPrices();
            console.log('JOT price: ', formatEther(tokenPrice[0]));
            console.log('SOT price: ', formatEther(tokenPrice[1]));
            await time.increase(320);
        });

        it('invest 382,500$ JOT', async () => {
            const poolBalanceBefore = await stableCoin.balanceOf(securitizationPoolContract.address);
            const investAmount = parseEther('382500');
            await untangledProtocol.buyToken(lenderSigner, jotMintedIncreasingInterestTGE.address, investAmount);
            console.log('current NAV: ', formatEther(await securitizationPoolContract.currentNAV()));
            console.log('future value: ', formatEther(await securitizationPoolContract.futureValue(tokenIds[0])));
            expect(await stableCoin.balanceOf(securitizationPoolContract.address)).to.be.eq(
                ethers.BigNumber.from(poolBalanceBefore).add(investAmount)
            );
            let tokenPrice = await securitizationPoolContract.calcTokenPrices();
            console.log('JOT price: ', formatEther(tokenPrice[0]));
            console.log('SOT price: ', formatEther(tokenPrice[1]));
            await time.increase(33350);
        });

        it('Withdraw 5,000.14$', async () => {
            await time.increase(650810);
        });

        it('At the moment', async () => {
            console.log('current NAV: ', formatEther(await securitizationPoolContract.currentNAV()));
            let tokenPrice = await securitizationPoolContract.calcTokenPrices();
            console.log('JOT price: ', formatEther(tokenPrice[0]));
            console.log('SOT price: ', formatEther(tokenPrice[1]));
            console.log("JPM2411's NAV: ", formatEther(await securitizationPoolContract.currentNAVAsset(tokenIds[0])));
            console.log("JPM2412's NAV: ", formatEther(await securitizationPoolContract.currentNAVAsset(tokenIds[1])));
            console.log("JPM2413's NAV: ", formatEther(await securitizationPoolContract.currentNAVAsset(tokenIds[2])));
            console.log("JPM2414's NAV: ", formatEther(await securitizationPoolContract.currentNAVAsset(tokenIds[3])));
            console.log("JPM2415's NAV: ", formatEther(await securitizationPoolContract.currentNAVAsset(tokenIds[4])));
        });
    });
});
