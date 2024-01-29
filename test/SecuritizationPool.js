const { ethers, artifacts } = require('hardhat');
const _ = require('lodash');
const dayjs = require('dayjs');
const { expect } = require('chai');
const { time } = require('@nomicfoundation/hardhat-network-helpers');

const { parseEther, formatEther } = ethers.utils;
const UntangledProtocol = require('./shared/untangled-protocol');

const {
    unlimitedAllowance,
    genSalt,
    getPoolByAddress,
    getPoolAbi,
} = require('./utils.js');
const { setup } = require('./setup.js');
const { SaleType } = require('./shared/constants.js');

const { POOL_ADMIN_ROLE, ORIGINATOR_ROLE } = require('./constants.js');
const { utils, Contract } = require('ethers');
const { ASSET_PURPOSE } = require('./shared/constants');

const RATE_SCALING_FACTOR = 10 ** 4;

describe('SecuritizationPool', () => {
    let stableCoin;
    let loanAssetTokenContract;
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
    let untangledProtocol;

    // Wallets
    let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner;
    before('create fixture', async () => {
        [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner] =
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
        } = contracts);

        await stableCoin.transfer(lenderSigner.address, parseEther('1000'));

        await stableCoin.connect(untangledAdminSigner).approve(loanRepaymentRouter.address, unlimitedAllowance);

        // Gain UID
        await untangledProtocol.mintUID(lenderSigner);
    });

    describe('#security pool', async () => {
        it('Create pool', async () => {
            const OWNER_ROLE = await securitizationManager.OWNER_ROLE();
            await securitizationManager.setRoleAdmin(POOL_ADMIN_ROLE, OWNER_ROLE);

            await securitizationManager.grantRole(OWNER_ROLE, borrowerSigner.address);
            await securitizationManager.connect(borrowerSigner).grantRole(POOL_ADMIN_ROLE, poolCreatorSigner.address);

            const salt = utils.keccak256(Date.now());

            // Create new pool
            let securitizationPoolAddress = await untangledProtocol.createSecuritizationPool(poolCreatorSigner, 10, 99, "cUSD", true, salt);

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

            securitizationPoolAddress = await untangledProtocol.createSecuritizationPool(poolCreatorSigner);

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
            await untangledProtocol.setupRiskScore(poolCreatorSigner, securitizationPoolContract, [riskScore]);
        });

        it('Wrong risk scores', async () => {
            const oneDayInSecs = 1 * 24 * 3600;
            const halfOfADay = oneDayInSecs / 2;

            const riskScore = {
                daysPastDue: oneDayInSecs,
                advanceRate: 950000,
                penaltyRate: 900000,
                interestRate: 910000,
                probabilityOfDefault: 800000,
                lossGivenDefault: 810000,
                discountRate: 100000,
                gracePeriod: halfOfADay,
                collectionPeriod: halfOfADay,
                writeOffAfterGracePeriod: halfOfADay,
                writeOffAfterCollectionPeriod: halfOfADay,
            };

            await expect(
                untangledProtocol
                    .setupRiskScore(poolCreatorSigner, securitizationPoolContract, [riskScore, riskScore])
            ).to.be.revertedWith(`SecuritizationPool: Risk scores must be sorted`);
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

            const { sotTGEAddress, sotTokenAddress } = await untangledProtocol.initSOTSale(poolCreatorSigner, {
                issuerTokenController: untangledAdminSigner.address,
                pool: securitizationPoolContract.address,
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
                ticker: prefixOfNoteTokenSaleName
            })
            expect(sotTGEAddress).to.be.properAddress;

            mintedIncreasingInterestTGE = await ethers.getContractAt('MintedIncreasingInterestTGE', sotTGEAddress);

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
            const { jotTGEAddress, jotTokenAddress } = await untangledProtocol.initJOTSale(poolCreatorSigner, {
                issuerTokenController: untangledAdminSigner.address,
                pool: securitizationPoolContract.address,
                minBidAmount: parseEther('50'),
                saleType: SaleType.NORMAL_SALE,
                longSale: true,
                ticker: prefixOfNoteTokenSaleName,
                openingTime: openingTime,
                closingTime: closingTime,
                rate: rate,
                cap: totalCapOfToken,
                initialJOTAmount,
            });

            expect(jotTGEAddress).to.be.properAddress;

            jotMintedIncreasingInterestTGE = await ethers.getContractAt('MintedIncreasingInterestTGE', jotTGEAddress);

            expect(jotTokenAddress).to.be.properAddress;

            jotToken = await ethers.getContractAt('NoteToken', jotTokenAddress);
        });

        it('Should buy tokens failed if buy sot first', async () => {
            await expect(
                untangledProtocol.buyToken(lenderSigner, mintedIncreasingInterestTGE.address, parseEther('100'))
            ).to.be.revertedWith(`Crowdsale: sale not started`);
        });

        it('Should buy tokens failed if exceeds debt ceiling', async () => {
            await expect(
                untangledProtocol.buyToken(lenderSigner, jotMintedIncreasingInterestTGE.address, parseEther('100'))
            ).to.be.revertedWith('Crowdsale: Exceeds Debt Ceiling');
        });
        it('set debt ceiling', async () => {
            await securitizationPoolContract.connect(poolCreatorSigner).setDebtCeiling(parseEther('300'));
            expect(await securitizationPoolContract.debtCeiling()).equal(parseEther('300'));
            // Set again
            await securitizationPoolContract.connect(poolCreatorSigner).setDebtCeiling(parseEther('200'));
            expect(await securitizationPoolContract.debtCeiling()).equal(parseEther('200'));
        });
        it('Should buy tokens failed if under min bid amount', async () => {
            await expect(
                untangledProtocol.buyToken(lenderSigner, jotMintedIncreasingInterestTGE.address, parseEther('30'))
            ).to.be.revertedWith('Crowdsale: Less than minBidAmount');
        });
        it('Should buy tokens successfully', async () => {
            await untangledProtocol.buyToken(lenderSigner, jotMintedIncreasingInterestTGE.address, parseEther('100'));
            await untangledProtocol.buyToken(lenderSigner, mintedIncreasingInterestTGE.address, parseEther('100'))

            const stablecoinBalanceOfPayerAfter = await stableCoin.balanceOf(lenderSigner.address);
            expect(formatEther(stablecoinBalanceOfPayerAfter)).equal('800.0');

            expect(formatEther(await stableCoin.balanceOf(securitizationPoolContract.address))).equal('200.0');
        });
    });

    describe('#Pool value service', async () => {
        it('#getExpectedAssetsValue', async () => {
            const result = await securitizationPoolValueService.getExpectedAssetsValue(
                securitizationPoolContract.address
            );

            expect(formatEther(result)).equal('0.0');
        });

        it('#getSeniorAsset', async () => {
            const result = await securitizationPoolValueService.getSeniorAsset(securitizationPoolContract.address);

            expect(formatEther(result)).equal('100.0');
        });

        it('#getJuniorAsset', async () => {
            const result = await securitizationPoolValueService.getJuniorAsset(securitizationPoolContract.address);

            expect(formatEther(result)).equal('100.0');
        });

        it('#getJuniorRatio', async () => {
            const result = await securitizationPoolValueService.getJuniorRatio(securitizationPoolContract.address);

            expect(result.toNumber() / RATE_SCALING_FACTOR).equal(50);
        });
    });

    let expirationTimestamps;
    const CREDITOR_FEE = '0';
    const inputAmount = 10;
    const inputPrice = 15;
    const principalAmount = _.round(inputAmount * inputPrice * 100);

    describe('#LoanKernel', async () => {
        it('Execute fillDebtOrder successfully', async () => {
            const loans = [
                {
                    principalAmount,
                    expirationTimestamp: dayjs(new Date()).add(7, 'days').unix(),
                    termInDays: 10,
                    riskScore: '1',
                    salt: genSalt()
                },
                {
                    principalAmount,
                    expirationTimestamp: dayjs(new Date()).add(7, 'days').unix(),
                    termInDays: 10,
                    riskScore: '1',
                    salt: genSalt()
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

            await expect(
                untangledProtocol.uploadLoans(
                    untangledAdminSigner,
                    securitizationPoolContract,
                    borrowerSigner,
                    ASSET_PURPOSE.LOAN,
                    loans
                )
            ).to.be.revertedWith(`ERC721: token already minted`);
        });

        it('Execute fillDebtOrder successfully with Pledge', async () => {
            const loans = [
                {
                    principalAmount,
                    expirationTimestamp: dayjs(new Date()).add(7, 'days').unix(),
                    termInDays: 10,
                    riskScore: '1'
                }
            ]

            const pledgeTokenIds = await untangledProtocol.uploadLoans(
                untangledAdminSigner,
                securitizationPoolContract,
                borrowerSigner,
                ASSET_PURPOSE.INVOICE,
                loans
            );

            const ownerOfAgreement = await loanAssetTokenContract.ownerOf(pledgeTokenIds[0]);
            expect(ownerOfAgreement).equal(securitizationPoolContract.address);

            tokenIds.push(...pledgeTokenIds);
            const balanceOfPool = await loanAssetTokenContract.balanceOf(securitizationPoolContract.address);
            expect(balanceOfPool).equal(tokenIds.length);
        });
    });

    describe('Pool value after loan kernel executed', async () => {
        it('#getExpectedAssetsValue', async () => {
            const result = await securitizationPoolValueService.getExpectedAssetsValue(
                securitizationPoolContract.address
            );
            expect(result.toString()).equal('43164');
        });
    });

    describe('Upgradeables', async () => {
        it('Should upgrade to new Implementation successfully', async () => {
            const SecuritizationPoolV2 = await ethers.getContractFactory('SecuritizationPoolV2');
            const spV2Impl = await SecuritizationPoolV2.deploy();

            const spImpl = await factoryAdmin.getProxyImplementation(securitizationPoolContract.address);

            expect(securitizationPoolImpl.address).to.be.eq(spImpl);

            // Update new logic
            await factoryAdmin
                .connect(untangledAdminSigner)
                .upgrade(securitizationPoolContract.address, spV2Impl.address);

            const newSpImpl = await factoryAdmin.getProxyImplementation(securitizationPoolContract.address);

            expect(spV2Impl.address).to.be.eq(newSpImpl);

            securitizationPoolContract = new Contract(
                securitizationPoolContract.address,
                [...(await getPoolAbi()), ...(await artifacts.readArtifact('SecuritizationPoolV2')).abi],
                ethers.provider
            );

            const result = await securitizationPoolContract.hello();

            expect(result).to.be.eq('Hello world');
        });
    });

    describe('Get Info after Upgrade', async () => {
        it('#getExpectedAssetsValue', async () => {
            const result = await securitizationPoolValueService.getExpectedAssetsValue(
                securitizationPoolContract.address
            );
            expect(result.toString()).equal('43164');
        });

        it('#getAssetInterestRate', async () => {
            const result = await securitizationPoolValueService.getAssetInterestRate(
                securitizationPoolContract.address,
                tokenIds[0]
            );

            // expect(result.toString()).equal('43164');
        });
    });

    describe('#Securitization Pool', async () => {
        it('#exportAssets', async () => {
            await securitizationPoolContract
                .connect(poolCreatorSigner)
                .exportAssets(loanAssetTokenContract.address, secondSecuritizationPool.address, [tokenIds[1]]);

            const ownerOfAgreement = await loanAssetTokenContract.ownerOf(tokenIds[1]);
            expect(ownerOfAgreement).equal(secondSecuritizationPool.address);

            const balanceOfPool = await loanAssetTokenContract.balanceOf(secondSecuritizationPool.address);
            expect(balanceOfPool).equal(1);

            await expect(
                securitizationPoolContract
                    .connect(poolCreatorSigner)
                    .exportAssets(stableCoin.address, secondSecuritizationPool.address, [tokenIds[1]])
            ).to.be.revertedWith(`SecuritizationPool: Asset does not exist`);
        });

        it('#setPot', async () => {
            await securitizationPoolContract.connect(poolCreatorSigner).setPot(secondSecuritizationPool.address);
            expect(await securitizationPoolContract.pot()).equal(secondSecuritizationPool.address);

            // Set again
            await securitizationPoolContract.connect(poolCreatorSigner).setPot(securitizationPoolContract.address);
            expect(await securitizationPoolContract.pot()).equal(securitizationPoolContract.address);
        });

        it('#withdrawAssets', async () => {
            await secondSecuritizationPool
                .connect(poolCreatorSigner)
                .withdrawAssets([loanAssetTokenContract.address], [tokenIds[1]], [originatorSigner.address]);

            const ownerOfAgreement = await loanAssetTokenContract.ownerOf(tokenIds[1]);
            expect(ownerOfAgreement).equal(originatorSigner.address);

            const balanceOfPoolCreator = await loanAssetTokenContract.balanceOf(originatorSigner.address);
            expect(balanceOfPoolCreator).equal(1);
        });

        it('#disburse', async () => {
            await expect(
                securitizationPoolContract.connect(poolCreatorSigner).disburse(lenderSigner.address, parseEther('1'))
            ).to.be.revertedWith('SecuritizationPool: Caller must be NoteTokenVault');
        });

        it('#claimCashRemain', async () => {
            expect(formatEther(await stableCoin.balanceOf(poolCreatorSigner.address))).equal('0.0');
            expect(formatEther(await sotToken.totalSupply())).equal('100.0');
            await expect(
                securitizationPoolContract.connect(poolCreatorSigner).claimCashRemain(poolCreatorSigner.address)
            ).to.be.revertedWith(`SecuritizationPool: SOT still remain`);

            // Force burn to test
            await sotToken.connect(lenderSigner).burn(parseEther('100'));
            expect(formatEther(await sotToken.totalSupply())).equal('0.0');

            await expect(
                securitizationPoolContract.connect(poolCreatorSigner).claimCashRemain(poolCreatorSigner.address)
            ).to.be.revertedWith(`SecuritizationPool: JOT still remain`);

            // Force burn to test
            await jotToken.connect(lenderSigner).burn(parseEther('100'));
            expect(formatEther(await jotToken.totalSupply())).equal('0.0');

            await securitizationPoolContract.connect(poolCreatorSigner).claimCashRemain(poolCreatorSigner.address);
        });

        it('#startCycle', async () => {
            expect(await stableCoin.balanceOf(poolCreatorSigner.address)).to.closeTo(
                parseEther('199.9999'),
                parseEther('0.001')
            );
            await expect(
                securitizationPoolContract
                    .connect(poolCreatorSigner)
                    .startCycle()
            ).to.be.revertedWith(`FinalizableCrowdsale: not closed`);

            await time.increaseTo(dayjs(new Date()).add(8, 'days').unix());

            await expect(mintedIncreasingInterestTGE.finalize(false, untangledAdminSigner.address)).to.be.revertedWith(
                `FinalizableCrowdsale: Only pool contract can finalize`
            );

            await securitizationPoolContract
                .connect(poolCreatorSigner)
                .startCycle();
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

    describe('Get Info', async () => {
        it('set new min first loss', async () => {
            const currentMinFirstLoss = await securitizationPoolContract.minFirstLossCushion();
            expect(currentMinFirstLoss).equal(100000);
            await securitizationPoolContract.connect(poolCreatorSigner).setMinFirstLossCushion('150000');
            const newMinFirstLoss = await securitizationPoolContract.minFirstLossCushion();
            expect(newMinFirstLoss).equal(150000);
        });
    });
});
