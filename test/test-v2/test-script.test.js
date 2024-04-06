const { ethers, artifacts } = require('hardhat');
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
        securitizationPoolImpl,
        epochExecutor,
        sotTokenManager,
        jotTokenManager,
        sotAddress,
        jotAddress,
        noteTokenFactory;
    // Wallets
    let adminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner;
    before('setup', async () => {
        [adminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner] = await ethers.getSigners();
        const contracts = await setup();
        ({
            stableCoin,
            securitizationManager,
            uniqueIdentity,
            loanKernel,
            securitizationPoolImpl,
            noteTokenFactory,
            sotTokenManager,
            jotTokenManager,
            epochExecutor,
        } = contracts);
        protocol = Protocol.bind(contracts);
        await stableCoin.transfer(lenderSigner.address, parseEther('1000'));
        await stableCoin.connect(adminSigner).approve(loanKernel.address, unlimitedAllowance);
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
                20000,
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
            securitizationPool.connect(poolCreatorSigner).grantRole(ORIGINATOR_ROLE, originatorSigner.address);
            securitizationPool.connect(poolCreatorSigner).grantRole(ORIGINATOR_ROLE, adminSigner.address);

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

            await protocol.setupRiskScore(poolCreatorSigner, securitizationPool, [riskScore]);
        });
        it('should create note token sale successfully', async () => {
            sotAddress = await protocol.initNoteTokenSale(poolCreatorSigner, {
                pool: securitizationPool.address,
                tokenType: 0,
                minBidAmount: parseEther('50'),
                interestRate: 2,
                ticker: 'SOT_',
            });
            jotAddress = await protocol.initNoteTokenSale(poolCreatorSigner, {
                pool: securitizationPool.address,
                tokenType: 1,
                minBidAmount: parseEther('50'),
                interestRate: 0,
                ticker: 'JOT_',
            });
            expect(await securitizationPool.sotToken()).to.be.eq(sotAddress);
            expect(await securitizationPool.interestRateSOT()).to.be.eq(BigNumber.from(2));
            expect(await securitizationPool.jotToken()).to.be.eq(jotAddress);
        });

        it('should place invest order successfully', async () => {
            expect(await sotTokenManager.getTokenAddress(securitizationPool.address)).to.be.eq(sotAddress);
            expect(await jotTokenManager.getTokenAddress(securitizationPool.address)).to.be.eq(jotAddress);
            await expect(
                sotTokenManager.connect(lenderSigner).investOrder(securitizationPool.address, parseEther('30'))
            ).to.be.revertedWith('NoteTokenManager: invest amount is too low');

            await sotTokenManager.connect(lenderSigner).investOrder(securitizationPool.address, parseEther('60'));
            await jotTokenManager.connect(lenderSigner).investOrder(securitizationPool.address, parseEther('90'));
        });
    });
});
