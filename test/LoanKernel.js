const { ethers, artifacts } = require('hardhat');
const _ = require('lodash');
const dayjs = require('dayjs');
const { expect } = require('chai');
const { impersonateAccount, setBalance } = require('@nomicfoundation/hardhat-network-helpers');

const { parseEther, formatEther, formatBytes32String } = ethers.utils;
const { presignedMintMessage } = require('./shared/uid-helper.js');
const UntangledProtocol = require('./shared/untangled-protocol');

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

const { POOL_ADMIN_ROLE } = require('./constants.js');
const { utils } = require('ethers');
const { ORIGINATOR_ROLE } = require('./constants');
const { ASSET_PURPOSE } = require('./shared/constants');

describe('LoanKernel', () => {
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
    let mintedIncreasingInterestTGE;
    let jotMintedIncreasingInterestTGE;
    let securitizationPoolValueService;
    let factoryAdmin;
    let securitizationPoolImpl;
    let defaultLoanAssetTokenValidator;
    let loanRegistry;
    let untangledProtocol;

    // Wallets
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

        await stableCoin.transfer(lenderSigner.address, parseEther('1000'));

        await stableCoin.connect(untangledAdminSigner).approve(loanRepaymentRouter.address, unlimitedAllowance);

        // Gain UID
        await untangledProtocol.mintUID(lenderSigner);
    });

    describe('#Initialize suit', async () => {
        it('Create pool & TGEs', async () => {
            const OWNER_ROLE = await securitizationManager.OWNER_ROLE();
            await securitizationManager.setRoleAdmin(POOL_ADMIN_ROLE, OWNER_ROLE);

            await securitizationManager.grantRole(OWNER_ROLE, borrowerSigner.address);
            await securitizationManager.connect(borrowerSigner).grantRole(POOL_ADMIN_ROLE, poolCreatorSigner.address);

            const poolParams = {
                currency: 'cUSD',
                minFirstLossCushion: 10,
                validatorRequired: true,
                debtCeiling: 1000,
            };

            const oneDayInSecs = 1 * 24 * 3600;
            const halfOfADay = oneDayInSecs / 2;
            const riskScores = [
                {
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
                },
            ];

            const openingTime = dayjs(new Date()).unix();
            const closingTime = dayjs(new Date()).add(7, 'days').unix();
            const rate = 2;
            const totalCapOfToken = parseEther('100000');
            const initialInterest = 10000;
            const finalInterest = 10000;
            const timeInterval = 1 * 24 * 3600; // seconds
            const amountChangeEachInterval = 0;
            const prefixOfNoteTokenSaleName = 'Ticker_';
            const sotInfo = {
                issuerTokenController: untangledAdminSigner.address,
                saleType: SaleType.MINTED_INCREASING_INTEREST,
                minBidAmount: parseEther('50'),
                openingTime,
                closingTime,
                rate,
                cap: totalCapOfToken,
                initialInterest,
                finalInterest,
                timeInterval,
                amountChangeEachInterval,
                ticker: prefixOfNoteTokenSaleName,
            };

            const initialJOTAmount = parseEther('1');
            const jotInfo = {
                issuerTokenController: untangledAdminSigner.address,
                minBidAmount: parseEther('50'),
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
            mintedIncreasingInterestTGE = await ethers.getContractAt(
                'MintedIncreasingInterestTGE',
                sotCreated.sotTGEAddress
            );
            jotMintedIncreasingInterestTGE = await ethers.getContractAt(
                'MintedIncreasingInterestTGE',
                jotCreated.jotTGEAddress
            );
        });

        it('Should buy tokens successfully', async () => {
            await untangledProtocol.buyToken(lenderSigner, jotMintedIncreasingInterestTGE.address, parseEther('100'));

            await untangledProtocol.buyToken(lenderSigner, mintedIncreasingInterestTGE.address, parseEther('100'));

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
    const principalAmount = 10000000000000000000;

    describe('#LoanKernel', async () => {
        it('No one than LoanKernel can mint', async () => {
            await expect(
                loanAssetTokenContract.connect(untangledAdminSigner)['mint(address,uint256)'](lenderSigner.address, 1)
            ).to.be.revertedWith(
                `AccessControl: account ${untangledAdminSigner.address.toLowerCase()} is missing role 0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6`
            );
        });

        it('SECURITIZATION_POOL is zero address', async () => {
            const orderAddresses = [
                ZERO_ADDRESS,
                stableCoin.address,
                loanRepaymentRouter.address,
                borrowerSigner.address,
            ];
            await expect(
                loanKernel.fillDebtOrder(formatFillDebtOrderParams(orderAddresses, [], [], []))
            ).to.be.revertedWith(`SECURITIZATION_POOL is zero address.`);
        });

        it('REPAYMENT_ROUTER is zero address', async () => {
            const orderAddresses = [
                securitizationPoolContract.address,
                stableCoin.address,
                ZERO_ADDRESS,
                borrowerSigner.address,
            ];
            await expect(
                loanKernel.fillDebtOrder(formatFillDebtOrderParams(orderAddresses, [], [], []))
            ).to.be.revertedWith(`REPAYMENT_ROUTER is zero address.`);
        });

        it('PRINCIPAL_TOKEN_ADDRESS is zero address', async () => {
            const orderAddresses = [
                securitizationPoolContract.address,
                ZERO_ADDRESS,
                loanRepaymentRouter.address,
                borrowerSigner.address,
            ];
            await expect(
                loanKernel.fillDebtOrder(formatFillDebtOrderParams(orderAddresses, [], [], []))
            ).to.be.revertedWith(`PRINCIPAL_TOKEN_ADDRESS is zero address.`);
        });

        it('LoanKernel: Invalid Term Contract params', async () => {
            const orderAddresses = [
                securitizationPoolContract.address,
                stableCoin.address,
                loanRepaymentRouter.address,
                borrowerSigner.address,
            ];
            await expect(
                loanKernel.fillDebtOrder(formatFillDebtOrderParams(orderAddresses, [], [], []))
            ).to.be.revertedWith(`LoanKernel: Invalid Term Contract params`);
        });

        it('LoanKernel: Invalid LAT Token Id', async () => {
            const orderAddresses = [
                securitizationPoolContract.address,
                stableCoin.address,
                loanRepaymentRouter.address,
                borrowerSigner.address,
            ];

            const salt = genSalt();
            const riskScore = '50';
            expirationTimestamps = dayjs(new Date()).add(7, 'days').unix();
            const orderValues = [
                CREDITOR_FEE,
                ASSET_PURPOSE_LOAN,
                principalAmount.toString(),
                expirationTimestamps,
                salt,
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

            const termsContractParameters = [termsContractParameter];

            const salts = saltFromOrderValues(orderValues, termsContractParameters.length);
            const debtors = debtorsFromOrderAddresses(orderAddresses, termsContractParameters.length);

            const tokenIds = ['0x944b447816387dc1f14b1a81dc4d95a77f588c214732772d921e146acd456b2b'];

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
            ).to.be.revertedWith(`LoanKernel: Invalid LAT Token Id`);
        });

        it('Execute fillDebtOrder successfully', async () => {
            const loans = [
                {
                    principalAmount,
                    expirationTimestamp: dayjs(new Date()).add(7, 'days').unix(),
                    assetPurpose: ASSET_PURPOSE.LOAN,
                    termInDays: 10,
                    riskScore: '1',
                    salt: genSalt(),
                },
                {
                    principalAmount,
                    expirationTimestamp: dayjs(new Date()).add(7, 'days').unix(),
                    assetPurpose: ASSET_PURPOSE.LOAN,
                    termInDays: 10,
                    riskScore: '1',
                    salt: genSalt(),
                },
            ];

            await expect(
                untangledProtocol.uploadLoans(
                    untangledAdminSigner,
                    securitizationPoolContract,
                    borrowerSigner,
                    ASSET_PURPOSE.LOAN,
                    loans
                )
            ).to.be.revertedWith(`SecuritizationPool: Only Originator can drawdown`);

            await securitizationPoolContract
                .connect(poolCreatorSigner)
                .grantRole(ORIGINATOR_ROLE, untangledAdminSigner.address);

            let stablecoinBalanceOfAdmin = await stableCoin.balanceOf(untangledAdminSigner.address);
            expect(formatEther(stablecoinBalanceOfAdmin)).equal('99000.0');

            tokenIds = await untangledProtocol.uploadLoans(
                untangledAdminSigner,
                securitizationPoolContract,
                borrowerSigner,
                ASSET_PURPOSE.LOAN,
                loans
            );

            const ownerOfAgreement = await loanAssetTokenContract.ownerOf(tokenIds[0]);
            expect(ownerOfAgreement).equal(securitizationPoolContract.address);

            const balanceOfPool = await loanAssetTokenContract.balanceOf(securitizationPoolContract.address);
            expect(balanceOfPool).equal(tokenIds.length);

            stablecoinBalanceOfAdmin = await stableCoin.balanceOf(untangledAdminSigner.address);
            expect(stablecoinBalanceOfAdmin).to.closeTo(parseEther('99019.000'), parseEther('0.01'));
        });
    });

    describe('Loan asset token', async () => {
        it('#getLoanDebtor', async () => {
            const result = await securitizationPoolContract.getAsset(tokenIds[0]);

            expect(result.debtor).equal(borrowerSigner.address);
        });

        it('#getLoanTermParams', async () => {
            const result = await securitizationPoolContract.getAsset(tokenIds[0]);

            expect(result.termsParam).equal('0x00000000008ac7230489e8000000c35010000000000000000000000f00200000');
        });

        it('#principalPaymentInfo', async () => {
            const result = await securitizationPoolContract.getAsset(tokenIds[0]);

            expect(result.principalTokenAddress).equal(stableCoin.address);
        });
    });

    describe('#concludeLoan', async () => {
        it('No one than LoanKernel contract can burn', async () => {
            await expect(loanAssetTokenContract.connect(untangledAdminSigner).burn(tokenIds[0])).to.be.revertedWith(
                `ERC721: caller is not token owner or approved`
            );
        });

        it('LoanKernel: Invalid creditor account', async () => {
            await impersonateAccount(loanRepaymentRouter.address);
            await setBalance(loanRepaymentRouter.address, ethers.utils.parseEther('1'));
            const signer = await ethers.getSigner(loanRepaymentRouter.address);
            await expect(loanKernel.connect(signer).concludeLoans([ZERO_ADDRESS], [tokenIds[0]])).to.be.revertedWith(
                `Invalid creditor account.`
            );
        });

        it('LoanKernel: Invalid agreement id', async () => {
            const signer = await ethers.getSigner(loanRepaymentRouter.address);
            await expect(
                loanKernel
                    .connect(signer)
                    .concludeLoans([securitizationPoolContract.address], [formatBytes32String('')])
            ).to.be.revertedWith(`Invalid agreement id.`);
        });

        it('Cannot conclude agreement id if caller is not LoanRepaymentRouter', async () => {
            await expect(
                loanKernel.concludeLoans([securitizationPoolContract.address], [tokenIds[0]])
            ).to.be.revertedWith('LoanKernel: Only LoanRepaymentRouter');
        });

        it('only LoanKernel contract can burn', async () => {
            const stablecoinBalanceOfPayerBefore = await stableCoin.balanceOf(untangledAdminSigner.address);
            expect(stablecoinBalanceOfPayerBefore).to.closeTo(parseEther('99019.000'), parseEther('0.01'));

            const stablecoinBalanceOfPoolBefore = await stableCoin.balanceOf(securitizationPoolContract.address);
            expect(stablecoinBalanceOfPoolBefore).to.closeTo(parseEther('181.00'), parseEther('0.01'));

            await loanRepaymentRouter
                .connect(untangledAdminSigner)
                .repayInBatch([tokenIds[0]], [parseEther('100')], stableCoin.address);

            await expect(loanAssetTokenContract.ownerOf(tokenIds[0])).to.be.revertedWith(`ERC721: invalid token ID`);

            const balanceOfPool = await loanAssetTokenContract.balanceOf(securitizationPoolContract.address);
            expect(balanceOfPool).equal(tokenIds.length - 1);

            const stablecoinBalanceOfPayerAfter = await stableCoin.balanceOf(untangledAdminSigner.address);
            expect(stablecoinBalanceOfPoolBefore).to.closeTo(parseEther('181.00'), parseEther('0.01'));

            const stablecoinBalanceOfPoolAfter = await stableCoin.balanceOf(securitizationPoolContract.address);
            expect(stablecoinBalanceOfPoolAfter).to.closeTo(parseEther('190.5'), parseEther('0.01'));
        });

        it('Cannot conclude agreement id again', async () => {
            const signer = await ethers.getSigner(loanRepaymentRouter.address);
            await expect(
                loanKernel.connect(signer).concludeLoans([securitizationPoolContract.address], [tokenIds[0]])
            ).to.be.revertedWith(`ERC721: invalid token ID`);
        });
    });
});
