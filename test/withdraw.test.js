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
        noteTokenVault,
        untangledProtocol;
    let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer;
    const drawdownAmount = 600000000000000000000000n;
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
            noteTokenVault,
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
                    advanceRate: 1000000, // 85%
                    penaltyRate: 900000, // 90%
                    interestRate: 168217, // 12%
                    probabilityOfDefault: 30000, // 3%
                    lossGivenDefault: 500000, // 50%
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
            sotToken = await ethers.getContractAt('NoteToken', sotCreated.sotTokenAddress);
            jotToken = await ethers.getContractAt('NoteToken', jotCreated.jotTokenAddress);
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

        it('drawdown $600,000', async () => {
            const loans = [
                {
                    principalAmount: drawdownAmount,
                    expirationTimestamp: (await time.latest()) + 3600 * 24 * 360 * 3,
                    assetPurpose: ASSET_PURPOSE.LOAN,
                    termInDays: 360 * 3,
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
            await time.increase(91 * 24 * 3600);
        });

        it('1st repay', async () => {
            const totalDebt = await securitizationPoolContract.debt(tokenIds[0]);
            const repayAmount = BigNumber.from(totalDebt).sub(drawdownAmount);
            totalRepay = totalRepay.add(repayAmount);
            console.log('repay amount: ', formatEther(repayAmount));
            await loanKernel
                .connect(untangledAdminSigner)
                .repayInBatch([tokenIds[0]], [repayAmount], stableCoin.address);
            expect(await securitizationPoolContract.debt(tokenIds[0])).to.be.closeTo(
                parseEther('600000'),
                parseEther('0.01')
            );
            console.log('current debt: ', formatEther(await securitizationPoolContract.debt(tokenIds[0])));
            console.log('total repay: ', formatEther(totalRepay));
            const [incomeReserve, capitalReserve] = await securitizationPoolContract.getReserves();
            console.log('income reserve: ', formatEther(incomeReserve));
            console.log('capital reserve: ', formatEther(capitalReserve));

            await time.increase(31 * 24 * 3600);
        });

        it('withdraw', async () => {
            await noteTokenVault.grantRole(BACKEND_ADMIN, untangledAdminSigner.address);
            await jotToken.connect(lenderSigner).approve(noteTokenVault.address, unlimitedAllowance);
            await noteTokenVault.connect(lenderSigner).createOrder(securitizationPoolContract.address, {
                sotCurrencyAmount: 0,
                jotCurrencyAmount: parseEther('30000'),
                allSOTIncomeOnly: false,
                allJOTIncomeOnly: false,
            });
            await noteTokenVault.connect(untangledAdminSigner).closeEpoch(securitizationPoolContract.address);

            console.log('jot balance before: ', formatEther(await jotToken.balanceOf(lenderSigner.address)));
            console.log('currency balance before: ', formatEther(await stableCoin.balanceOf(lenderSigner.address)));
            const [incomeReserve, capitalReserve] = await securitizationPoolContract.getReserves();
            await noteTokenVault.connect(untangledAdminSigner).executeOrders(securitizationPoolContract.address, [
                {
                    user: lenderSigner.address,
                    sotIncomeClaimAmount: 0,
                    jotIncomeClaimAmount: incomeReserve,
                    sotCapitalClaimAmount: 0,
                    jotCapitalClaimAmount: parseEther('30000').sub(incomeReserve),
                },
            ]);
            console.log('jot balance after: ', formatEther(await jotToken.balanceOf(lenderSigner.address)));
            console.log('currency balance after: ', formatEther(await stableCoin.balanceOf(lenderSigner.address)));
        });
    });
});
