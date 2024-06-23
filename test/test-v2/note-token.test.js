const { ethers, artifacts } = require('hardhat');
const { time } = require('@nomicfoundation/hardhat-network-helpers');
const { setup } = require('./setup');
const Protocol = require('./protocol');
const { parseEther, formatEther } = ethers.utils;
const { expect } = require('chai');
const dayjs = require('dayjs');
const { POOL_ADMIN_ROLE, OWNER_ROLE, ORIGINATOR_ROLE } = require('../constants');
const { SaleType } = require('../shared/constants');
const { getPoolByAddress, unlimitedAllowance, genSalt, getPoolAbi } = require('../utils');
const { utils, Contract, BigNumber } = require('ethers');

const RATE_SCALING_FACTOR = 10 ** 4;

describe('Untangled-v2', async () => {
    let stableCoin,
        securitizationManager,
        securitizationPool,
        protocol,
        uniqueIdentity,
        loanKernel,
        loanAssetToken,
        securitizationPoolImpl,
        epochExecutor,
        sotTokenManager,
        jotTokenManager,
        sotAddress,
        jotAddress,
        sotToken,
        jotToken,
        noteTokenFactory,
        tokenIds;
    // Wallets
    let adminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, potWallet;
    const drawdownAmount = 80000000000000000000000n;
    before('setup', async () => {
        [adminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, potWallet] =
            await ethers.getSigners();
        const contracts = await setup();
        protocol = Protocol.bind(contracts);
        ({
            stableCoin,
            securitizationManager,
            uniqueIdentity,
            loanKernel,
            loanAssetToken,
            securitizationPoolImpl,
            noteTokenFactory,
            sotTokenManager,
            jotTokenManager,
            epochExecutor,
        } = contracts);
        await stableCoin.transfer(lenderSigner.address, parseEther('1000000'));

        await stableCoin.connect(borrowerSigner).approve(loanKernel.address, unlimitedAllowance);

        await protocol.mintUID(lenderSigner);
    });
    describe('security pool', async () => {
        it('create pool', async () => {
            await securitizationManager.setRoleAdmin(POOL_ADMIN_ROLE, OWNER_ROLE);
            await securitizationManager.grantRole(OWNER_ROLE, borrowerSigner.address);
            await securitizationManager.connect(borrowerSigner).grantRole(POOL_ADMIN_ROLE, poolCreatorSigner.address);

            const salt = utils.keccak256(Date.now());
            let securitizationPoolAddress = await protocol.createSecuritizationPool(
                poolCreatorSigner,
                10,
                200000,
                'USDC',
                true,
                salt
            );

            const { bytecode } = await artifacts.readArtifact('TransparentUpgradeableProxy');

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

            securitizationPool = await getPoolByAddress(securitizationPoolAddress);
            await securitizationPool.connect(poolCreatorSigner).grantRole(ORIGINATOR_ROLE, originatorSigner.address);
            await securitizationPool.connect(poolCreatorSigner).grantRole(ORIGINATOR_ROLE, adminSigner.address);

            await securitizationPool.connect(poolCreatorSigner).setPot(potWallet.address);
            await stableCoin.connect(potWallet).approve(securitizationPool.address, unlimitedAllowance);
            expect(await securitizationPool.pot()).to.be.eq(potWallet.address);

            const oneDayInSecs = 1 * 24 * 3600;
            const halfOfADay = oneDayInSecs / 2;
            const riskScore = {
                daysPastDue: oneDayInSecs,
                advanceRate: 1000000,
                penaltyRate: 900000,
                interestRate: 150000,
                probabilityOfDefault: 30000,
                lossGivenDefault: 500000,
                gracePeriod: halfOfADay,
                collectionPeriod: halfOfADay,
                writeOffAfterGracePeriod: halfOfADay,
                writeOffAfterCollectionPeriod: halfOfADay,
                discountRate: 100000,
            };

            await protocol.setupRiskScore(poolCreatorSigner, securitizationPool, [riskScore]);
        });

        it('should create note token sale successfully', async () => {
            sotAddress = await protocol.initNoteTokenSale(poolCreatorSigner, {
                pool: securitizationPool.address,
                tokenType: 0,
                minBidAmount: parseEther('5000'),
                interestRate: 2,
                ticker: 'SOT_',
            });
            jotAddress = await protocol.initNoteTokenSale(poolCreatorSigner, {
                pool: securitizationPool.address,
                tokenType: 1,
                minBidAmount: parseEther('5000'),
                interestRate: 0,
                ticker: 'JOT_',
            });
            expect(await securitizationPool.sotToken()).to.be.eq(sotAddress);
            expect(await securitizationPool.interestRateSOT()).to.be.eq(BigNumber.from(2));
            expect(await securitizationPool.jotToken()).to.be.eq(jotAddress);
            sotToken = await ethers.getContractAt('NoteToken', sotAddress);
            jotToken = await ethers.getContractAt('NoteToken', jotAddress);
            await securitizationPool.calcTokenPrices();
        });

        it('should place invest order successfully', async () => {
            expect(await sotTokenManager.getTokenAddress(securitizationPool.address)).to.be.eq(sotAddress);
            expect(await jotTokenManager.getTokenAddress(securitizationPool.address)).to.be.eq(jotAddress);
            await stableCoin.connect(lenderSigner).approve(sotTokenManager.address, parseEther('100000'));
            await stableCoin.connect(lenderSigner).approve(jotTokenManager.address, parseEther('100000'));
            await expect(
                sotTokenManager.connect(lenderSigner).investOrder(securitizationPool.address, parseEther('3000'))
            ).to.be.revertedWith('NoteTokenManager: invest amount is too low');

            await sotTokenManager.connect(lenderSigner).investOrder(securitizationPool.address, parseEther('60000'));
            await jotTokenManager.connect(lenderSigner).investOrder(securitizationPool.address, parseEther('90000'));
        });
        it('should close investment epoch ', async () => {
            await epochExecutor.closeEpoch(securitizationPool.address);

            await sotTokenManager.disburse(securitizationPool.address, lenderSigner.address);
            await jotTokenManager.disburse(securitizationPool.address, lenderSigner.address);

            expect(await epochExecutor.currentEpoch(securitizationPool.address)).to.be.eq(1);

            expect(await securitizationPool.reserve()).to.be.eq(parseEther('150000'));
            expect(await stableCoin.balanceOf(potWallet.address)).to.be.eq(parseEther('150000'));

            expect(await sotToken.balanceOf(lenderSigner.address)).to.be.eq(parseEther('60000'));
            expect(await jotToken.balanceOf(lenderSigner.address)).to.be.eq(parseEther('90000'));
        });

        it('should drawdown', async () => {
            const loans = [
                {
                    principalAmount: drawdownAmount,
                    expirationTimestamp: (await time.latest()) + 3600 * 24 * 90,
                    assetPurpose: '0',
                    termInDays: 90,
                    riskScore: '1',
                    salt: genSalt(),
                },
            ];
            await securitizationPool.connect(poolCreatorSigner).grantRole(ORIGINATOR_ROLE, borrowerSigner.address);
            const { expectedLoansValue } = await protocol.getLoansValue(
                borrowerSigner,
                securitizationPool,
                borrowerSigner,
                '0',
                loans
            );
            expect(expectedLoansValue).to.be.eq(parseEther('80000'));

            tokenIds = await protocol.fillDebtOrder(borrowerSigner, securitizationPool, borrowerSigner, '0', loans);

            time.increase(30 * 3600 * 24); // 30 days later
        });

        it('should repay', async () => {
            const totalDebt = await securitizationPool.debt(tokenIds[0]);
            const repayAmount = BigNumber.from(totalDebt).sub(drawdownAmount);

            await loanKernel.connect(borrowerSigner).repayInBatch([tokenIds[0]], [repayAmount], stableCoin.address);
            expect(await securitizationPool.debt(tokenIds[0])).to.be.closeTo(drawdownAmount, parseEther('0.01'));
            console.log('capital reserve: ', formatEther(await securitizationPool.capitalReserve()));
            console.log('income reserve: ', formatEther(await securitizationPool.incomeReserve()));
            console.log(await securitizationPool.calcTokenPrices());
        });
    });
});
