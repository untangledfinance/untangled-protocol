const { ethers } = require('hardhat');
const { getChainId } = require('hardhat');
const UntangledProtocol = require('./shared/untangled-protocol');
const _ = require('lodash');
const dayjs = require('dayjs');
const { expect } = require('chai');

const { POOL_ADMIN_ROLE, ORIGINATOR_ROLE } = require('./constants');

const { parseEther, formatEther } = ethers.utils;

const {
    unlimitedAllowance,
    ZERO_ADDRESS,
    getPoolByAddress,
} = require('./utils.js');
const { setup } = require('./setup.js');
const { SaleType, ASSET_PURPOSE } = require('./shared/constants.js');

describe('Distribution', () => {
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
    let distributionAssessor;
    let untangledProtocol;

    // Wallets
    let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner;
    before('create fixture', async () => {
        [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner] =
            await ethers.getSigners();

        const contracts = await setup();
        ({
            stableCoin,
            loanAssetTokenContract,
            defaultLoanAssetTokenValidator,
            loanKernel,
            loanRepaymentRouter,
            securitizationManager,
            uniqueIdentity,
            distributionOperator,
            distributionTranche,
            securitizationPoolValueService,
            distributionAssessor,
        } = contracts);
        untangledProtocol = UntangledProtocol.bind(contracts);

        await stableCoin.transfer(lenderSigner.address, parseEther('1000'));

        await stableCoin.connect(untangledAdminSigner).approve(loanRepaymentRouter.address, unlimitedAllowance);

        const chainId = await getChainId();
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
            const riskScores = [{
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
            }];

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
            const [poolAddress, sotCreated, jotCreated] = await untangledProtocol.createFullPool(poolCreatorSigner, poolParams, riskScores, sotInfo, jotInfo);
            securitizationPoolContract = await getPoolByAddress(poolAddress);
            await securitizationPoolContract
              .connect(poolCreatorSigner)
              .grantRole(ORIGINATOR_ROLE, originatorSigner.address);

            await securitizationPoolContract
              .connect(poolCreatorSigner)
              .grantRole(ORIGINATOR_ROLE, untangledAdminSigner.address);
            mintedIncreasingInterestTGE = await ethers.getContractAt('MintedIncreasingInterestTGE', sotCreated.sotTGEAddress);
            jotMintedIncreasingInterestTGE = await ethers.getContractAt('MintedIncreasingInterestTGE', jotCreated.jotTGEAddress);
            sotToken = await ethers.getContractAt('NoteToken', sotCreated.sotTokenAddress);
            jotToken = await ethers.getContractAt('NoteToken', jotCreated.jotTokenAddress);
        });

        it('Should buy tokens successfully', async () => {
            await untangledProtocol.buyToken(lenderSigner, jotMintedIncreasingInterestTGE.address, parseEther('100'));

            await untangledProtocol.buyToken(lenderSigner, mintedIncreasingInterestTGE.address, parseEther('100'));

            const stablecoinBalanceOfPayerAfter = await stableCoin.balanceOf(lenderSigner.address);
            expect(formatEther(stablecoinBalanceOfPayerAfter)).equal('800.0');

            expect(formatEther(await stableCoin.balanceOf(securitizationPoolContract.address))).equal('200.0');
        });
    });

    const principalAmount = 10000000000000000000;

    describe('#LoanKernel', async () => {
        it('Execute fillDebtOrder successfully', async () => {
            const expirationTimestamps = dayjs(new Date()).add(7, 'days').unix();
            const loans = [
                {
                    principalAmount,
                    expirationTimestamp: expirationTimestamps,
                    termInDays: 10,
                    riskScore: '1',
                },
                {
                    principalAmount,
                    expirationTimestamp: expirationTimestamps,
                    termInDays: 10,
                    riskScore: '1',
                }
            ]


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

        });
    });

    describe('#Distribution Accessor', async () => {
        it('#calcCorrespondingTotalAssetValue', async () => {
            let result = await distributionAssessor.calcCorrespondingTotalAssetValue(
                sotToken.address,
                lenderSigner.address
            );
            expect(formatEther(result)).equal('100.0');

            result = await distributionAssessor.calcCorrespondingTotalAssetValue(
                jotToken.address,
                lenderSigner.address
            );

            expect(result).to.closeTo(parseEther('100.18'), parseEther('0.01'));
        });

        it('#calcCorrespondingAssetValue(address,address[])', async () => {
            const result = await distributionAssessor['calcCorrespondingAssetValue(address,address[])'](
                sotToken.address,
                [lenderSigner.address]
            );
            expect(result.map((x) => formatEther(x))).to.deep.equal(['100.0']);
        });

        it('#calcTokenPrice', async () => {
            let result = await distributionAssessor.calcTokenPrice(
                securitizationPoolContract.address,
                sotToken.address
            );
            expect(formatEther(result)).equal('1.0');

            result = await distributionAssessor.calcTokenPrice(securitizationPoolContract.address, jotToken.address);
            expect(result).to.closeTo(parseEther('1.002'), parseEther('0.001'));

            result = await distributionAssessor.calcTokenPrice(securitizationPoolContract.address, ZERO_ADDRESS);
            expect(formatEther(result)).equal('0.0');
        });

        it('#getCashBalance', async () => {
            const result = await distributionAssessor.getCashBalance(securitizationPoolContract.address);
            expect(result).to.closeTo(parseEther('181.000'), parseEther('0.001'));
        });
    });

    describe('Burn agreement', async () => {
        it('only LoanKernel contract can burn', async () => {
            await loanRepaymentRouter
                .connect(untangledAdminSigner)
                .repayInBatch([tokenIds[0]], [parseEther('100')], stableCoin.address);

            await expect(loanAssetTokenContract.ownerOf(tokenIds[0])).to.be.revertedWith(`ERC721: invalid token ID`);
        });
    });
});
