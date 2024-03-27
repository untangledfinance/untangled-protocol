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
                {
                    daysPastDue: oneDayInSecs + 1,
                    advanceRate: 1000000, // LTV
                    penaltyRate: 0,
                    interestRate: 150000,
                    probabilityOfDefault: 100000,
                    lossGivenDefault: 1000000,
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
            const initialJOTAmount = parseEther('1');
            const sotInfo = undefined;
            const jotInfo = {
                issuerTokenController: untangledAdminSigner.address,
                minBidAmount: 0,
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
            jotTGE = await ethers.getContractAt('MintedNormalTGE', jotCreated.jotTGEAddress);
            jotToken = await ethers.getContractAt('NoteToken', await jotTGE.token());

            await noteTokenVault.connect(untangledAdminSigner).grantRole(BACKEND_ADMIN, backendAdminSigner.address);
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

    describe('#Test case pool has only JOT', async () => {
        it('Should buy tokens successfully: Only jot', async () => {
            await untangledProtocol.buyToken(lenderSigner, jotTGE.address, parseEther('100'));

            let debtAndBalance = await securitizationPoolContract.seniorDebtAndBalance();
            expect(debtAndBalance[0]).equal(parseEther('0'));
            expect(debtAndBalance[1]).equal(parseEther('0'));

            let ratio = await securitizationPoolContract.calcJuniorRatio();
            expect(ratio).equal(BigNumber.from(1000000));

            const stablecoinBalanceOfPayerAfter = await stableCoin.balanceOf(lenderSigner.address);
            expect(formatEther(stablecoinBalanceOfPayerAfter)).equal('900.0');

            expect(formatEther(await stableCoin.balanceOf(securitizationPoolContract.address))).equal('100.0');
        });

        it('Execute fillDebtOrder successfully', async () => {
            const loans = [
                {
                    principalAmount: principalAmount1,
                    expirationTimestamp: dayjs(new Date()).add(900, 'days').unix(), // due day
                    assetPurpose: ASSET_PURPOSE.LOAN,
                    termInDays: 900, // expirationTimestamp - block.timestamp
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
            expect(tokenPrice[1]).equal(parseEther('0'));

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
            expect(tokenPrice[1]).equal(parseEther('0'));

            // seniorDebt and seniorBalance
            let debtAndBalance = await securitizationPoolContract.seniorDebtAndBalance();
            expect(debtAndBalance[0]).equal(parseEther('0'));
            expect(debtAndBalance[1]).equal(parseEther('0'));

            snapshot = await takeSnapshot();
        });

        it('Test rebase after an year', async () => {
            await time.increase(ONE_YEAR);

            tokenPrice = await securitizationPoolContract.calcTokenPrices();
            expect(tokenPrice[0]).to.closeTo(parseEther('1.129467'), parseEther('0.000001'));
            expect(tokenPrice[1]).equal(parseEther('0'));

            await securitizationPoolContract.connect(poolCreatorSigner).rebase();

            // check NAV and reserve
            currentNAV = await securitizationPoolContract.currentNAV();
            expect(currentNAV).to.closeTo(parseEther('92.946739'), parseEther('0.000001'));
            reserve = await securitizationPoolContract.reserve();
            expect(reserve).equal(parseEther('20'));

            // Price still the same after rebase
            tokenPrice = await securitizationPoolContract.calcTokenPrices();
            expect(tokenPrice[0]).to.closeTo(parseEther('1.129467'), parseEther('0.000001'));
            expect(tokenPrice[1]).equal(parseEther('0'));

            // seniorDebt and seniorBalance
            let debtAndBalance = await securitizationPoolContract.seniorDebtAndBalance();
            expect(debtAndBalance[0]).equal(parseEther('0'));
            expect(debtAndBalance[1]).equal(parseEther('0'));
        });
    });
});
