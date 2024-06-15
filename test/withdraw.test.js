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
    let untangledAdminSigner,
        poolCreatorSigner,
        originatorSigner,
        borrowerSigner,
        lenderSigner,
        alice,
        bob,
        charlie,
        duncan;
    const drawdownAmount = 80000000000000000000000n;
    let totalRepay = BigNumber.from(0);
    before('create fixture', async () => {
        [
            untangledAdminSigner,
            poolCreatorSigner,
            originatorSigner,
            borrowerSigner,
            lenderSigner,
            alice,
            bob,
            charlie,
            duncan,
        ] = await ethers.getSigners();
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

        await stableCoin.transfer(alice.address, parseEther('100000'));
        await stableCoin.transfer(bob.address, parseEther('100000'));
        await stableCoin.transfer(charlie.address, parseEther('100000'));
        await stableCoin.transfer(duncan.address, parseEther('100000'));

        await stableCoin.connect(untangledAdminSigner).approve(loanRepaymentRouter.address, unlimitedAllowance);

        await untangledProtocol.mintUID(alice);
        await untangledProtocol.mintUID(bob);
        await untangledProtocol.mintUID(charlie);
        await untangledProtocol.mintUID(duncan);
    });

    describe('#intialize suit', async () => {
        it('Create pool & TGEs', async () => {
            // const OWNER_ROLE = await securitizationManager.OWNER_ROLE();
            await securitizationManager.setRoleAdmin(POOL_ADMIN_ROLE, OWNER_ROLE);

            await securitizationManager.grantRole(OWNER_ROLE, borrowerSigner.address);
            await securitizationManager.connect(borrowerSigner).grantRole(POOL_ADMIN_ROLE, poolCreatorSigner.address);

            const poolParams = {
                currency: 'cUSD',
                minFirstLossCushion: 50,
                validatorRequired: true,
                debtCeiling: 2000000,
            };

            const oneDayInSecs = 24 * 3600;
            const halfOfADay = oneDayInSecs / 2;
            const riskScores = [
                {
                    daysPastDue: oneDayInSecs,
                    advanceRate: 1000000, // 100%
                    penaltyRate: 900000, // 90%
                    interestRate: 150000, // 15%
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

        it('invest', async () => {
            await untangledProtocol.buyToken(alice, jotMintedIncreasingInterestTGE.address, parseEther('10000'));
            await untangledProtocol.buyToken(bob, jotMintedIncreasingInterestTGE.address, parseEther('20000'));
            await untangledProtocol.buyToken(charlie, jotMintedIncreasingInterestTGE.address, parseEther('30000'));
            await untangledProtocol.buyToken(duncan, jotMintedIncreasingInterestTGE.address, parseEther('40000'));

            await untangledProtocol.buyToken(alice, mintedIncreasingInterestTGE.address, parseEther('10000'));
            await untangledProtocol.buyToken(bob, mintedIncreasingInterestTGE.address, parseEther('20000'));
            await untangledProtocol.buyToken(charlie, mintedIncreasingInterestTGE.address, parseEther('30000'));
            await untangledProtocol.buyToken(duncan, mintedIncreasingInterestTGE.address, parseEther('40000'));
            let tokenPrice = await securitizationPoolContract.calcTokenPrices();
            expect(tokenPrice[0]).to.be.eq(parseEther('1'));
        });

        it('drawdown', async () => {
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
            console.log('current debt: ', formatEther(await securitizationPoolContract.debt(tokenIds[0])));
            console.log('total repay: ', formatEther(totalRepay));
            const [incomeReserve, capitalReserve] = await securitizationPoolContract.getReserves();
            console.log('income reserve: ', formatEther(incomeReserve));
            console.log('capital reserve: ', formatEther(capitalReserve));

            await time.increase(31 * 24 * 3600);
        });

        it('withdraw', async () => {
            await noteTokenVault.grantRole(BACKEND_ADMIN, untangledAdminSigner.address);
            const [jotPriceBefore, sotPriceBefore] = await securitizationPoolContract.calcTokenPrices();
            console.log('jot price before: ', formatEther(jotPriceBefore));
            console.log('sot price before: ', formatEther(sotPriceBefore));
            // aprove
            await jotToken.connect(alice).approve(noteTokenVault.address, unlimitedAllowance);
            await jotToken.connect(bob).approve(noteTokenVault.address, unlimitedAllowance);
            await jotToken.connect(charlie).approve(noteTokenVault.address, unlimitedAllowance);
            await jotToken.connect(duncan).approve(noteTokenVault.address, unlimitedAllowance);

            await sotToken.connect(alice).approve(noteTokenVault.address, unlimitedAllowance);
            await sotToken.connect(bob).approve(noteTokenVault.address, unlimitedAllowance);
            await sotToken.connect(charlie).approve(noteTokenVault.address, unlimitedAllowance);
            await sotToken.connect(duncan).approve(noteTokenVault.address, unlimitedAllowance);

            // create order
            await noteTokenVault.connect(alice).createOrder(securitizationPoolContract.address, {
                sotCurrencyAmount: parseEther('2000'),
                jotCurrencyAmount: parseEther('3000'),
                allSOTIncomeOnly: false,
                allJOTIncomeOnly: false,
            });

            await noteTokenVault.connect(bob).createOrder(securitizationPoolContract.address, {
                sotCurrencyAmount: parseEther('2000'),
                jotCurrencyAmount: parseEther('3000'),
                allSOTIncomeOnly: false,
                allJOTIncomeOnly: false,
            });

            await noteTokenVault.connect(charlie).createOrder(securitizationPoolContract.address, {
                sotCurrencyAmount: parseEther('2000'),
                jotCurrencyAmount: parseEther('3000'),
                allSOTIncomeOnly: false,
                allJOTIncomeOnly: false,
            });

            await noteTokenVault.connect(duncan).createOrder(securitizationPoolContract.address, {
                sotCurrencyAmount: parseEther('2000'),
                jotCurrencyAmount: parseEther('3000'),
                allSOTIncomeOnly: false,
                allJOTIncomeOnly: false,
            });

            // close epoch
            await noteTokenVault.connect(untangledAdminSigner).closeEpoch(securitizationPoolContract.address, 1);

            const [incomeReserve, capitalReserve] = await securitizationPoolContract.getReserves();

            console.log('income reserve: ', formatEther(incomeReserve));
            console.log('capital reserve: ', formatEther(capitalReserve));

            const jotSupply = BigNumber.from(await jotToken.totalSupply()).div(parseEther('1'));
            const sotSupply = BigNumber.from(await sotToken.totalSupply()).div(parseEther('1'));
            const sotIncome = BigNumber.from(incomeReserve).div(3); // sotIncome = incomeReserve * 50% * 10% / 15% = incomeReserve / 3;
            const jotIncome = BigNumber.from(incomeReserve).sub(sotIncome);
            const sotIncomePerToken = BigNumber.from(sotIncome).div(sotSupply);
            const jotIncomePerToken = BigNumber.from(jotIncome).div(jotSupply);

            console.log('sot income: ', formatEther(sotIncome));
            console.log('jot income: ', formatEther(jotIncome));

            const aliceSeniorIncome = BigNumber.from(await sotToken.balanceOf(alice.address))
                .div(parseEther('1'))
                .mul(sotIncomePerToken);
            const bobSeniorIncome = BigNumber.from(await sotToken.balanceOf(bob.address))
                .div(parseEther('1'))
                .mul(sotIncomePerToken);
            const charlieSeniorIncome = BigNumber.from(await sotToken.balanceOf(charlie.address))
                .div(parseEther('1'))
                .mul(sotIncomePerToken);
            const duncanSeniorIncome = BigNumber.from(await sotToken.balanceOf(duncan.address))
                .div(parseEther('1'))
                .mul(sotIncomePerToken);

            const aliceJuniorIncome = BigNumber.from(await jotToken.balanceOf(alice.address))
                .div(parseEther('1'))
                .mul(jotIncomePerToken);
            const bobJuniorIncome = BigNumber.from(await jotToken.balanceOf(bob.address))
                .div(parseEther('1'))
                .mul(jotIncomePerToken);
            const charlieJuniorIncome = BigNumber.from(await jotToken.balanceOf(charlie.address))
                .div(parseEther('1'))
                .mul(jotIncomePerToken);
            const duncanJuniorIncome = BigNumber.from(await jotToken.balanceOf(duncan.address))
                .div(parseEther('1'))
                .mul(jotIncomePerToken);

            console.log('alice senior income: ', formatEther(aliceSeniorIncome));
            console.log('bob senior income: ', formatEther(bobSeniorIncome));
            console.log('charlie senior income: ', formatEther(charlieSeniorIncome));
            console.log('duncan senior income: ', formatEther(duncanSeniorIncome));

            console.log('alice junior income: ', formatEther(aliceJuniorIncome));
            console.log('bob junior income: ', formatEther(bobJuniorIncome));
            console.log('charlie junior income: ', formatEther(charlieJuniorIncome));
            console.log('duncan junior income: ', formatEther(duncanJuniorIncome));

            await noteTokenVault.connect(untangledAdminSigner).executeOrders(securitizationPoolContract.address, [
                {
                    user: alice.address,
                    sotIncomeClaimAmount: aliceSeniorIncome,
                    jotIncomeClaimAmount: aliceJuniorIncome,
                    sotCapitalClaimAmount: parseEther('2000').sub(aliceSeniorIncome),
                    jotCapitalClaimAmount: parseEther('3000').sub(aliceJuniorIncome),
                },
                {
                    user: bob.address,
                    sotIncomeClaimAmount: bobSeniorIncome,
                    jotIncomeClaimAmount: bobJuniorIncome,
                    sotCapitalClaimAmount: parseEther('2000').sub(bobSeniorIncome),
                    jotCapitalClaimAmount: parseEther('3000').sub(bobJuniorIncome),
                },
                {
                    user: charlie.address,
                    sotIncomeClaimAmount: charlieSeniorIncome,
                    jotIncomeClaimAmount: charlieJuniorIncome,
                    sotCapitalClaimAmount: parseEther('2000').sub(charlieSeniorIncome),
                    jotCapitalClaimAmount: parseEther('3000').sub(charlieJuniorIncome),
                },
                {
                    user: duncan.address,
                    sotIncomeClaimAmount: duncanSeniorIncome,
                    jotIncomeClaimAmount: duncanJuniorIncome,
                    sotCapitalClaimAmount: parseEther('2000').sub(duncanSeniorIncome),
                    jotCapitalClaimAmount: parseEther('3000').sub(duncanJuniorIncome),
                },
            ]);
            console.log('============== After execution ==============');
            const [jotPriceAfter, sotPriceAfter] = await securitizationPoolContract.calcTokenPrices();
            console.log('jot price after: ', formatEther(jotPriceAfter));
            console.log('sot price after: ', formatEther(sotPriceAfter));

            const [seniorDebt, seniorBalance] = await securitizationPoolContract.seniorDebtAndBalance();
            console.log('min first loss: ', await securitizationPoolContract.calcJuniorRatio());
            console.log('senior debt: ', formatEther(seniorDebt));
            console.log('senior balance: ', formatEther(seniorBalance));

            const [incomeAfter, capitalAfter] = await securitizationPoolContract.getReserves();
            console.log('income reserve: ', formatEther(incomeAfter));
            console.log('capital reserve: ', formatEther(capitalAfter));

            console.log('net asset value: ', formatEther(await securitizationPoolContract.currentNAV()));

            console.log('============== sot balance ==============');
            console.log('alice sot token balance: ', formatEther(await sotToken.balanceOf(alice.address)));
            console.log('bob sot token balance: ', formatEther(await sotToken.balanceOf(bob.address)));
            console.log('charlie sot token balance: ', formatEther(await sotToken.balanceOf(charlie.address)));
            console.log('duncan sot token balance: ', formatEther(await sotToken.balanceOf(duncan.address)));

            console.log('============== jot balance ==============');
            console.log('alice jot token balance: ', formatEther(await jotToken.balanceOf(alice.address)));
            console.log('bob jot token balance: ', formatEther(await jotToken.balanceOf(bob.address)));
            console.log('charlie jot token balance: ', formatEther(await jotToken.balanceOf(charlie.address)));
            console.log('duncan jot token balance: ', formatEther(await jotToken.balanceOf(duncan.address)));

            console.log('============== currency balance ==============');
            console.log('alice currency balance: ', formatEther(await stableCoin.balanceOf(alice.address)));
            console.log('bob currency balance: ', formatEther(await stableCoin.balanceOf(bob.address)));
            console.log('charlie currency balance: ', formatEther(await stableCoin.balanceOf(charlie.address)));
            console.log('duncan currency balance: ', formatEther(await stableCoin.balanceOf(duncan.address)));
        });

        //     it('withdraw', async () => {
        //         await noteTokenVault.grantRole(BACKEND_ADMIN, untangledAdminSigner.address);

        //         // aprove
        //         await jotToken.connect(alice).approve(noteTokenVault.address, unlimitedAllowance);
        //         await jotToken.connect(bob).approve(noteTokenVault.address, unlimitedAllowance);
        //         await jotToken.connect(charlie).approve(noteTokenVault.address, unlimitedAllowance);
        //         await jotToken.connect(duncan).approve(noteTokenVault.address, unlimitedAllowance);
        //         // create order
        //         await noteTokenVault.connect(alice).createOrder(securitizationPoolContract.address, {
        //             sotCurrencyAmount: 0,
        //             jotCurrencyAmount: parseEther('3000'),
        //             allSOTIncomeOnly: false,
        //             allJOTIncomeOnly: false,
        //         });

        //         await noteTokenVault.connect(bob).createOrder(securitizationPoolContract.address, {
        //             sotCurrencyAmount: 0,
        //             jotCurrencyAmount: parseEther('3000'),
        //             allSOTIncomeOnly: false,
        //             allJOTIncomeOnly: false,
        //         });

        //         await noteTokenVault.connect(charlie).createOrder(securitizationPoolContract.address, {
        //             sotCurrencyAmount: 0,
        //             jotCurrencyAmount: parseEther('3000'),
        //             allSOTIncomeOnly: false,
        //             allJOTIncomeOnly: false,
        //         });

        //         await noteTokenVault.connect(duncan).createOrder(securitizationPoolContract.address, {
        //             sotCurrencyAmount: 0,
        //             jotCurrencyAmount: parseEther('3000'),
        //             allSOTIncomeOnly: false,
        //             allJOTIncomeOnly: false,
        //         });

        //         // close epoch
        //         await noteTokenVault.connect(untangledAdminSigner).closeEpoch(securitizationPoolContract.address, 1);

        //         const [incomeReserve, capitalReserve] = await securitizationPoolContract.getReserves();
        //         const noteTokenSupply = BigNumber.from(await jotToken.totalSupply()).div(parseEther('1'));
        //         const incomePerNoteToken = BigNumber.from(incomeReserve).div(noteTokenSupply);

        //         const aliceIncome = BigNumber.from(await jotToken.balanceOf(alice.address))
        //             .div(parseEther('1'))
        //             .mul(incomePerNoteToken);
        //         const bobIncome = BigNumber.from(await jotToken.balanceOf(bob.address))
        //             .div(parseEther('1'))
        //             .mul(incomePerNoteToken);
        //         const charlieIncome = BigNumber.from(await jotToken.balanceOf(charlie.address))
        //             .div(parseEther('1'))
        //             .mul(incomePerNoteToken);
        //         const duncanIncome = BigNumber.from(await jotToken.balanceOf(duncan.address))
        //             .div(parseEther('1'))
        //             .mul(incomePerNoteToken);

        //         console.log('income reserve: ', formatEther(incomeReserve));
        //         console.log('capital reserve: ', formatEther(capitalReserve));
        //         console.log("alice's income: ", formatEther(aliceIncome));
        //         console.log("bob's income: ", formatEther(bobIncome));
        //         console.log("charlie's income: ", formatEther(charlieIncome));
        //         console.log("duncan's income: ", formatEther(duncanIncome));

        //         await noteTokenVault.connect(untangledAdminSigner).executeOrders(securitizationPoolContract.address, [
        //             {
        //                 user: alice.address,
        //                 sotIncomeClaimAmount: 0,
        //                 jotIncomeClaimAmount: aliceIncome,
        //                 sotCapitalClaimAmount: 0,
        //                 jotCapitalClaimAmount: parseEther('3000').sub(aliceIncome),
        //             },
        //             {
        //                 user: bob.address,
        //                 sotIncomeClaimAmount: 0,
        //                 jotIncomeClaimAmount: bobIncome,
        //                 sotCapitalClaimAmount: 0,
        //                 jotCapitalClaimAmount: parseEther('3000').sub(bobIncome),
        //             },
        //             {
        //                 user: charlie.address,
        //                 sotIncomeClaimAmount: 0,
        //                 jotIncomeClaimAmount: charlieIncome,
        //                 sotCapitalClaimAmount: 0,
        //                 jotCapitalClaimAmount: parseEther('3000').sub(charlieIncome),
        //             },
        //             {
        //                 user: duncan.address,
        //                 sotIncomeClaimAmount: 0,
        //                 jotIncomeClaimAmount: duncanIncome,
        //                 sotCapitalClaimAmount: 0,
        //                 jotCapitalClaimAmount: parseEther('3000').sub(duncanIncome),
        //             },
        //         ]);
        //         console.log('============== After execution ==============');
        //         let [IR, CR] = await securitizationPoolContract.getReserves();
        //         console.log('income reserve: ', formatEther(IR));
        //         console.log('capital reserve: ', formatEther(CR));

        //         console.log('alice note token balance: ', formatEther(await jotToken.balanceOf(alice.address)));
        //         console.log('bob note token balance: ', formatEther(await jotToken.balanceOf(bob.address)));
        //         console.log('charlie note token balance: ', formatEther(await jotToken.balanceOf(charlie.address)));
        //         console.log('duncan note token balance: ', formatEther(await jotToken.balanceOf(duncan.address)));

        //         console.log('alice currency balance: ', formatEther(await stableCoin.balanceOf(alice.address)));
        //         console.log('bob currency balance: ', formatEther(await stableCoin.balanceOf(bob.address)));
        //         console.log('charlie currency balance: ', formatEther(await stableCoin.balanceOf(charlie.address)));
        //         console.log('duncan currency balance: ', formatEther(await stableCoin.balanceOf(duncan.address)));
        //     });
    });
});
