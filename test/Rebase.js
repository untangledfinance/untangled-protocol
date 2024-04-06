const { ethers, artifacts } = require('hardhat');
const _ = require('lodash');
const dayjs = require('dayjs');
const { expect } = require('chai');
const { impersonateAccount, setBalance, time, takeSnapshot } = require('@nomicfoundation/hardhat-network-helpers');

const { parseEther, formatEther, formatBytes32String } = ethers.utils;
const { presignedMintMessage } = require('./shared/uid-helper.js');
const UntangledProtocol = require('./shared/untangled-protocol.js');

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
const { SaleType, ASSET_PURPOSE } = require('./shared/constants.js');

const { OWNER_ROLE, POOL_ADMIN_ROLE, BACKEND_ADMIN, ORIGINATOR_ROLE } = require('./constants.js');
const { utils, BigNumber } = require('ethers');

describe('Rebase Logic', () => {
    let stableCoin;
    let loanAssetTokenContract;
    let loanKernel;
    let loanRepaymentRouter;
    let securitizationManager;
    let securitizationPoolContract;
    let tokenIds;
    let uniqueIdentity;
    let distributionOperator;
    let sotToken;
    let jotToken;
    let distributionTranche;
    let sotTGE;
    let jotTGE;
    let securitizationPoolValueService;
    let factoryAdmin;
    let securitizationPoolImpl;
    let defaultLoanAssetTokenValidator;
    let loanRegistry;
    let untangledProtocol;

    // Wallets
    let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer;
    before('create fixture', async () => {
        [
            untangledAdminSigner,
            poolCreatorSigner,
            originatorSigner,
            borrowerSigner,
            lenderSigner,
            relayer,
            backendAdminSigner,
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

        await stableCoin.transfer(lenderSigner.address, parseEther('1000'));

        await stableCoin.connect(untangledAdminSigner).approve(loanRepaymentRouter.address, unlimitedAllowance);

        // Gain UID
        await untangledProtocol.mintUID(lenderSigner);
    });

    let snapshot;

    describe('#Initialize suit', async () => {
        it('Create pool & TGEs', async () => {
            // const OWNER_ROLE = await securitizationManager.OWNER_ROLE();
            await securitizationManager.setRoleAdmin(POOL_ADMIN_ROLE, OWNER_ROLE);

            await securitizationManager.grantRole(OWNER_ROLE, borrowerSigner.address);
            await securitizationManager.connect(borrowerSigner).grantRole(POOL_ADMIN_ROLE, poolCreatorSigner.address);

            const poolParams = {
                currency: 'cUSD',
                minFirstLossCushion: 1, // 1%
                validatorRequired: true,
                debtCeiling: 1000,
            };

            const oneDayInSecs = 1 * 24 * 3600;
            const halfOfADay = oneDayInSecs / 2;
            const riskScores = [
                {
                    daysPastDue: oneDayInSecs,
                    advanceRate: 1000000, // LTV
                    penaltyRate: 0,
                    interestRate: 150000, //
                    probabilityOfDefault: 0, //
                    lossGivenDefault: 0, //
                    gracePeriod: halfOfADay,
                    collectionPeriod: halfOfADay,
                    writeOffAfterGracePeriod: halfOfADay,
                    writeOffAfterCollectionPeriod: halfOfADay,
                    discountRate: 150000,
                },
            ];

            const openingTime = dayjs(new Date()).unix();
            const closingTime = dayjs(new Date()).add(8000, 'days').unix();
            const rate = 100000;
            const totalCapOfToken = parseEther('100000');
            const interestRate = 100000; // 10%
            const timeInterval = 1 * 24 * 3600; // seconds
            const amountChangeEachInterval = 0;
            const prefixOfNoteTokenSaleName = 'Ticker_';
            const sotInfo = {
                issuerTokenController: untangledAdminSigner.address,
                saleType: SaleType.MINTED_INCREASING_INTEREST,
                minBidAmount: parseEther('10'),
                openingTime,
                closingTime,
                rate,
                cap: totalCapOfToken,
                timeInterval,
                amountChangeEachInterval,
                ticker: prefixOfNoteTokenSaleName,
                interestRate,
            };

            const initialJOTAmount = parseEther('1');
            const jotInfo = {
                issuerTokenController: untangledAdminSigner.address,
                minBidAmount: parseEther('10'),
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
            sotTGE = await ethers.getContractAt('MintedNormalTGE', sotCreated.sotTGEAddress);
            jotTGE = await ethers.getContractAt('MintedNormalTGE', jotCreated.jotTGEAddress);
            sotToken = await ethers.getContractAt('NoteToken', await sotTGE.token());
            jotToken = await ethers.getContractAt('NoteToken', await jotTGE.token());

            await noteTokenVault.connect(untangledAdminSigner).grantRole(BACKEND_ADMIN, backendAdminSigner.address);
        });

        it('Should buy tokens successfully', async () => {
            await untangledProtocol.buyToken(lenderSigner, jotTGE.address, parseEther('10'));
            await untangledProtocol.buyToken(lenderSigner, sotTGE.address, parseEther('90'));

            let debtAndBalance = await securitizationPoolContract.seniorDebtAndBalance();
            expect(debtAndBalance[0]).equal(parseEther('0'));
            expect(debtAndBalance[1]).equal(parseEther('90'));

            let ratio = await securitizationPoolContract.calcJuniorRatio();
            expect(ratio).equal(BigNumber.from(100000));

            const stablecoinBalanceOfPayerAfter = await stableCoin.balanceOf(lenderSigner.address);
            expect(formatEther(stablecoinBalanceOfPayerAfter)).equal('900.0');

            expect(formatEther(await stableCoin.balanceOf(securitizationPoolContract.address))).equal('100.0');
        });
    });

    let expirationTimestamps;
    const CREDITOR_FEE = '0';
    const ASSET_PURPOSE_LOAN = '0';
    const ASSET_PURPOSE_INVOICE = '1';
    const inputAmount = 10;
    const inputPrice = 15;
    const ONE_YEAR = 365 * 24 * 60 * 60;
    const principalAmount1 = 80000000000000000000n;
    const principalAmount2 = 10000000000000000000n;

    describe('#Set up basic case', async () => {
        it('Execute fillDebtOrder successfully', async () => {
            const loans = [
                {
                    principalAmount: principalAmount1,
                    expirationTimestamp: dayjs(new Date()).add(2000, 'days').unix(), // due day
                    assetPurpose: ASSET_PURPOSE.LOAN,
                    termInDays: 2000, // expirationTimestamp - block.timestamp
                    riskScore: '1',
                    salt: genSalt(),
                },
            ];

            await securitizationPoolContract
                .connect(poolCreatorSigner)
                .grantRole(ORIGINATOR_ROLE, untangledAdminSigner.address);

            let currentNAV = await securitizationPoolContract.currentNAV();
            expect(currentNAV).equal(parseEther('0'));
            let reserve = await securitizationPoolContract.reserve();
            expect(reserve).equal(parseEther('100'));

            let tokenPrice = await securitizationPoolContract.calcTokenPrices();
            expect(tokenPrice[0]).equal(parseEther('1'));
            expect(tokenPrice[1]).equal(parseEther('1'));

            // ACTION: DRAWDOWN 80
            tokenIds = await untangledProtocol.uploadLoans(
                untangledAdminSigner,
                securitizationPoolContract,
                borrowerSigner,
                ASSET_PURPOSE.LOAN,
                loans
            );

            // check NAV and reserve
            currentNAV = await securitizationPoolContract.currentNAV();
            expect(currentNAV).equal(parseEther('80'));
            reserve = await securitizationPoolContract.reserve();
            expect(reserve).equal(parseEther('20'));

            // Price still the same after rebase
            tokenPrice = await securitizationPoolContract.calcTokenPrices();
            expect(tokenPrice[0]).equal(parseEther('1'));
            expect(tokenPrice[1]).equal(parseEther('1'));

            // seniorDebt and seniorBalance
            let debtAndBalance = await securitizationPoolContract.seniorDebtAndBalance();
            expect(debtAndBalance[0]).equal(parseEther('72'));
            expect(debtAndBalance[1]).equal(parseEther('18'));

            snapshot = await takeSnapshot();
        });
    });

    describe('#Drawdown test', async () => {
        it('Draw down again after 1 years', async () => {
            await snapshot.restore();
            await time.increase(ONE_YEAR);
            // check NAV and reserve
            let currentNAV = await securitizationPoolContract.currentNAV();
            let reserve = await securitizationPoolContract.reserve();
            expect(currentNAV).to.closeTo(parseEther('92.946739'), parseEther('0.000001'));
            expect(reserve).equal(parseEther('20'));

            // Price still the same after rebase
            let tokenPrice = await securitizationPoolContract.calcTokenPrices();
            expect(tokenPrice[0]).to.closeTo(parseEther('1.537443'), parseEther('0.000001'));
            expect(tokenPrice[1]).to.closeTo(parseEther('1.084136'), parseEther('0.000001'));

            // seniorDebt and seniorBalance
            let debtAndBalance = await securitizationPoolContract.seniorDebtAndBalance();
            expect(debtAndBalance[0]).to.closeTo(parseEther('79.572306'), parseEther('0.000001'));
            expect(debtAndBalance[1]).to.closeTo(parseEther('18'), parseEther('0.000001'));

            const loans = [
                {
                    principalAmount: principalAmount2,
                    expirationTimestamp: dayjs(new Date()).add(2000, 'days').unix(), // due day
                    assetPurpose: ASSET_PURPOSE.LOAN,
                    termInDays: 2000, // expirationTimestamp - block.timestamp
                    riskScore: '1',
                    salt: genSalt(),
                },
            ];

            // ACTION: DRAWDOWN 10
            await untangledProtocol.uploadLoans(
                untangledAdminSigner,
                securitizationPoolContract,
                borrowerSigner,
                ASSET_PURPOSE.LOAN,
                loans
            );

            // Price still the same after rebase
            tokenPrice = await securitizationPoolContract.calcTokenPrices();
            expect(tokenPrice[0]).to.closeTo(parseEther('1.537443'), parseEther('0.000001'));
            expect(tokenPrice[1]).to.closeTo(parseEther('1.084136'), parseEther('0.000001'));
            // check NAV and reserve
            currentNAV = await securitizationPoolContract.currentNAV();
            reserve = await securitizationPoolContract.reserve();
            expect(currentNAV).to.closeTo(parseEther('102.946739'), parseEther('0.000001'));
            expect(reserve).equal(parseEther('10'));

            // seniorDebt and seniorBalance
            debtAndBalance = await securitizationPoolContract.seniorDebtAndBalance();
            expect(debtAndBalance[0]).to.closeTo(parseEther('88.933517'), parseEther('0.000001'));
            expect(debtAndBalance[1]).to.closeTo(parseEther('8.638789'), parseEther('0.000001'));
        });

        it('Check state after 1 years', async () => {
            await time.increase(ONE_YEAR);
            // check NAV and reserve
            let currentNAV = await securitizationPoolContract.currentNAV();
            let reserve = await securitizationPoolContract.reserve();
            expect(currentNAV).to.closeTo(parseEther('119.607047'), parseEther('0.000001'));
            expect(reserve).equal(parseEther('10'));

            // Price still the same after rebase
            let tokenPrice = await securitizationPoolContract.calcTokenPrices();
            expect(tokenPrice[0]).to.closeTo(parseEther('2.268152'), parseEther('0.000001'));
            expect(tokenPrice[1]).to.closeTo(parseEther('1.188061'), parseEther('0.000001'));

            // seniorDebt and seniorBalance
            let debtAndBalance = await securitizationPoolContract.seniorDebtAndBalance();
            expect(debtAndBalance[0]).to.closeTo(parseEther('98.286737'), parseEther('0.000001'));
            expect(debtAndBalance[1]).to.closeTo(parseEther('8.638789'), parseEther('0.000001'));
        });
    });

    describe('#Repay test', async () => {
        it('Repay after 1 years', async () => {
            await snapshot.restore();
            await time.increase(ONE_YEAR);
            // check NAV and reserve
            let currentNAV = await securitizationPoolContract.currentNAV();
            let reserve = await securitizationPoolContract.reserve();
            expect(currentNAV).to.closeTo(parseEther('92.946739'), parseEther('0.000001'));
            expect(reserve).equal(parseEther('20'));

            // Price still the same after rebase
            let tokenPrice = await securitizationPoolContract.calcTokenPrices();
            expect(tokenPrice[0]).to.closeTo(parseEther('1.537443'), parseEther('0.000001'));
            expect(tokenPrice[1]).to.closeTo(parseEther('1.084136'), parseEther('0.000001'));

            // seniorDebt and seniorBalance
            let debtAndBalance = await securitizationPoolContract.seniorDebtAndBalance();
            expect(debtAndBalance[0]).to.closeTo(parseEther('79.572306'), parseEther('0.000001'));
            expect(debtAndBalance[1]).to.closeTo(parseEther('18'), parseEther('0.000001'));

            // ACTION: REPAY 60
            await loanRepaymentRouter
                .connect(untangledAdminSigner)
                .repayInBatch([tokenIds[0]], [parseEther('60')], stableCoin.address);

            // Price still the same after rebase
            tokenPrice = await securitizationPoolContract.calcTokenPrices();
            expect(tokenPrice[0]).to.closeTo(parseEther('1.537443'), parseEther('0.000001'));
            expect(tokenPrice[1]).to.closeTo(parseEther('1.084136'), parseEther('0.000001'));

            // check NAV and reserve
            currentNAV = await securitizationPoolContract.currentNAV();
            reserve = await securitizationPoolContract.reserve();
            expect(currentNAV).to.closeTo(parseEther('32.946739'), parseEther('0.000001'));
            expect(reserve).equal(parseEther('80'));

            // seniorDebt and seniorBalance
            debtAndBalance = await securitizationPoolContract.seniorDebtAndBalance();
            expect(debtAndBalance[0]).to.closeTo(parseEther('28.461993'), parseEther('0.000001'));
            expect(debtAndBalance[1]).to.closeTo(parseEther('69.110313'), parseEther('0.000001'));
        });

        it('Check state after 1 years', async () => {
            await time.increase(ONE_YEAR);
            // check NAV and reserve
            let currentNAV = await securitizationPoolContract.currentNAV();
            let reserve = await securitizationPoolContract.reserve();
            expect(currentNAV).to.closeTo(parseEther('38.278650'), parseEther('0.000001'));
            expect(reserve).equal(parseEther('80'));

            // Price still the same after rebase
            let tokenPrice = await securitizationPoolContract.calcTokenPrices();
            expect(tokenPrice[0]).to.closeTo(parseEther('1.771297'), parseEther('0.000001'));
            expect(tokenPrice[1]).to.closeTo(parseEther('1.117396'), parseEther('0.000001'));

            // seniorDebt and seniorBalance
            let debtAndBalance = await securitizationPoolContract.seniorDebtAndBalance();
            expect(debtAndBalance[0]).to.closeTo(parseEther('31.455367'), parseEther('0.000001'));
            expect(debtAndBalance[1]).to.closeTo(parseEther('69.110313'), parseEther('0.000001'));
        });
    });

    describe('#Jot investment test', async () => {
        it('Jot investment 1 years', async () => {
            await snapshot.restore();
            await time.increase(ONE_YEAR);
            // check NAV and reserve
            let currentNAV = await securitizationPoolContract.currentNAV();
            let reserve = await securitizationPoolContract.reserve();
            expect(currentNAV).to.closeTo(parseEther('92.946739'), parseEther('0.000001'));
            expect(reserve).equal(parseEther('20'));

            // Price still the same after rebase
            let tokenPrice = await securitizationPoolContract.calcTokenPrices();
            expect(tokenPrice[0]).to.closeTo(parseEther('1.537443'), parseEther('0.000001'));
            expect(tokenPrice[1]).to.closeTo(parseEther('1.084136'), parseEther('0.000001'));

            // seniorDebt and seniorBalance
            let debtAndBalance = await securitizationPoolContract.seniorDebtAndBalance();
            expect(debtAndBalance[0]).to.closeTo(parseEther('79.572306'), parseEther('0.000001'));
            expect(debtAndBalance[1]).to.closeTo(parseEther('18'), parseEther('0.000001'));

            // ACTION: INVEST JOT 100
            await untangledProtocol.buyToken(lenderSigner, jotTGE.address, parseEther('100'));

            // Price still the same after rebase
            tokenPrice = await securitizationPoolContract.calcTokenPrices();
            expect(tokenPrice[0]).to.closeTo(parseEther('1.537443'), parseEther('0.000001'));
            expect(tokenPrice[1]).to.closeTo(parseEther('1.084136'), parseEther('0.000001'));

            // check NAV and reserve
            currentNAV = await securitizationPoolContract.currentNAV();
            reserve = await securitizationPoolContract.reserve();
            expect(currentNAV).to.closeTo(parseEther('92.946739'), parseEther('0.000001'));
            expect(reserve).equal(parseEther('120'));

            // seniorDebt and seniorBalance
            debtAndBalance = await securitizationPoolContract.seniorDebtAndBalance();
            expect(debtAndBalance[0]).to.closeTo(parseEther('42.588244'), parseEther('0.000001'));
            expect(debtAndBalance[1]).to.closeTo(parseEther('54.984062'), parseEther('0.000001'));
        });

        it('Check state after 1 years', async () => {
            await time.increase(ONE_YEAR);
            // check NAV and reserve
            let currentNAV = await securitizationPoolContract.currentNAV();
            let reserve = await securitizationPoolContract.reserve();
            expect(currentNAV).to.closeTo(parseEther('107.988704'), parseEther('0.000001'));
            expect(reserve).equal(parseEther('120'));

            // Price still the same after rebase
            let tokenPrice = await securitizationPoolContract.calcTokenPrices();
            expect(tokenPrice[0]).to.closeTo(parseEther('1.678201'), parseEther('0.000001'));
            expect(tokenPrice[1]).to.closeTo(parseEther('1.133904'), parseEther('0.000001'));

            // seniorDebt and seniorBalance
            let debtAndBalance = await securitizationPoolContract.seniorDebtAndBalance();
            expect(debtAndBalance[0]).to.closeTo(parseEther('47.067289'), parseEther('0.000001'));
            expect(debtAndBalance[1]).to.closeTo(parseEther('54.984062'), parseEther('0.000001'));
        });
    });

    describe('#Sot investment test', async () => {
        it('Sot investment 1 years', async () => {
            await snapshot.restore();
            await time.increase(ONE_YEAR);
            // check NAV and reserve
            let currentNAV = await securitizationPoolContract.currentNAV();
            let reserve = await securitizationPoolContract.reserve();
            expect(currentNAV).to.closeTo(parseEther('92.946739'), parseEther('0.000001'));
            expect(reserve).equal(parseEther('20'));

            // Price still the same after rebase
            let tokenPrice = await securitizationPoolContract.calcTokenPrices();
            expect(tokenPrice[0]).to.closeTo(parseEther('1.537443'), parseEther('0.000001'));
            expect(tokenPrice[1]).to.closeTo(parseEther('1.084136'), parseEther('0.000001'));

            // seniorDebt and seniorBalance
            let debtAndBalance = await securitizationPoolContract.seniorDebtAndBalance();
            expect(debtAndBalance[0]).to.closeTo(parseEther('79.572306'), parseEther('0.000001'));
            expect(debtAndBalance[1]).to.closeTo(parseEther('18'), parseEther('0.000001'));

            // ACTION: INVEST SOT 100
            await untangledProtocol.buyToken(lenderSigner, sotTGE.address, parseEther('100'));

            // Price still the same after rebase
            tokenPrice = await securitizationPoolContract.calcTokenPrices();
            expect(tokenPrice[0]).to.closeTo(parseEther('1.537443'), parseEther('0.000001'));
            expect(tokenPrice[1]).to.closeTo(parseEther('1.084136'), parseEther('0.000001'));

            // check NAV and reserve
            currentNAV = await securitizationPoolContract.currentNAV();
            reserve = await securitizationPoolContract.reserve();
            expect(currentNAV).to.closeTo(parseEther('92.946739'), parseEther('0.000001'));
            expect(reserve).equal(parseEther('120'));

            // seniorDebt and seniorBalance
            debtAndBalance = await securitizationPoolContract.seniorDebtAndBalance();
            expect(debtAndBalance[0]).to.closeTo(parseEther('86.236125'), parseEther('0.000001'));
            expect(debtAndBalance[1]).to.closeTo(parseEther('111.336181'), parseEther('0.000001'));
        });

        it('Check state after 1 years', async () => {
            await time.increase(ONE_YEAR);
            // check NAV and reserve
            let currentNAV = await securitizationPoolContract.currentNAV();
            let reserve = await securitizationPoolContract.reserve();
            expect(currentNAV).to.closeTo(parseEther('107.988704'), parseEther('0.000001'));
            expect(reserve).equal(parseEther('120'));

            // Price still the same after rebase
            let tokenPrice = await securitizationPoolContract.calcTokenPrices();
            expect(tokenPrice[0]).to.closeTo(parseEther('2.134687'), parseEther('0.000001'));
            expect(tokenPrice[1]).to.closeTo(parseEther('1.133904'), parseEther('0.000001'));

            // seniorDebt and seniorBalance
            let debtAndBalance = await securitizationPoolContract.seniorDebtAndBalance();
            expect(debtAndBalance[0]).to.closeTo(parseEther('95.305658'), parseEther('0.000001'));
            expect(debtAndBalance[1]).to.closeTo(parseEther('111.336181'), parseEther('0.000001'));
        });
    });

    describe('#Sot withdraw test', async () => {
        it('Sot withdraw 1 years', async () => {
            await snapshot.restore();
            await time.increase(ONE_YEAR);
            await noteTokenVault
                .connect(backendAdminSigner)
                .setRedeemDisabled(securitizationPoolContract.address, true);
            // check NAV and reserve
            let currentNAV = await securitizationPoolContract.currentNAV();
            let reserve = await securitizationPoolContract.reserve();
            expect(currentNAV).to.closeTo(parseEther('92.946739'), parseEther('0.000001'));
            expect(reserve).equal(parseEther('20'));

            // Price still the same after rebase
            let tokenPrice = await securitizationPoolContract.calcTokenPrices();
            expect(tokenPrice[0]).to.closeTo(parseEther('1.537443'), parseEther('0.000001'));
            expect(tokenPrice[1]).to.closeTo(parseEther('1.084136'), parseEther('0.000001'));

            // seniorDebt and seniorBalance
            let debtAndBalance = await securitizationPoolContract.seniorDebtAndBalance();
            expect(debtAndBalance[0]).to.closeTo(parseEther('79.572306'), parseEther('0.000001'));
            expect(debtAndBalance[1]).to.closeTo(parseEther('18'), parseEther('0.000001'));

            // ACTION: WITHDRAW SOT WITH VALUE OF 10 USD
            const sotLenderBalance = await sotToken.balanceOf(lenderSigner.address);
            await sotToken.connect(lenderSigner).transfer(noteTokenVault.address, sotLenderBalance);
            let withdrawAmount = parseEther('10');
            let tokenBurnAmount = parseEther('10').mul(parseEther('1')).div(tokenPrice[1]);
            await noteTokenVault
                .connect(backendAdminSigner)
                .preDistribute(
                    securitizationPoolContract.address,
                    withdrawAmount,
                    [sotToken.address],
                    [tokenBurnAmount]
                );

            // Price still the same after rebase
            tokenPrice = await securitizationPoolContract.calcTokenPrices();
            expect(tokenPrice[0]).to.closeTo(parseEther('1.537443'), parseEther('0.000001'));
            expect(tokenPrice[1]).to.closeTo(parseEther('1.084136'), parseEther('0.000001'));

            // check NAV and reserve
            currentNAV = await securitizationPoolContract.currentNAV();
            reserve = await securitizationPoolContract.reserve();
            expect(currentNAV).to.closeTo(parseEther('92.946739'), parseEther('0.000001'));
            expect(reserve).equal(parseEther('10'));

            // seniorDebt and seniorBalance
            debtAndBalance = await securitizationPoolContract.seniorDebtAndBalance();
            expect(debtAndBalance[0]).to.closeTo(parseEther('79.065742'), parseEther('0.000001'));
            expect(debtAndBalance[1]).to.closeTo(parseEther('8.506564'), parseEther('0.000001'));
        });

        it('Check state after 1 years', async () => {
            await time.increase(ONE_YEAR);
            // check NAV and reserve
            let currentNAV = await securitizationPoolContract.currentNAV();
            let reserve = await securitizationPoolContract.reserve();
            expect(currentNAV).to.closeTo(parseEther('107.988704'), parseEther('0.000001'));
            expect(reserve).equal(parseEther('10'));

            // Price still the same after rebase
            let tokenPrice = await securitizationPoolContract.calcTokenPrices();
            expect(tokenPrice[0]).to.closeTo(parseEther('2.210098'), parseEther('0.000001'));
            expect(tokenPrice[1]).to.closeTo(parseEther('1.187081'), parseEther('0.000001'));

            // seniorDebt and seniorBalance
            let debtAndBalance = await securitizationPoolContract.seniorDebtAndBalance();
            expect(debtAndBalance[0]).to.closeTo(parseEther('87.381159'), parseEther('0.000001'));
            expect(debtAndBalance[1]).to.closeTo(parseEther('8.506564'), parseEther('0.000001'));
        });
    });
});
