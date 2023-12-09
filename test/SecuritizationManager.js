const { ethers } = require('hardhat');
const { deployments } = require('hardhat');
const { BigNumber, utils } = require('ethers');
const dayjs = require('dayjs');
const { parseEther, formatEther } = ethers.utils;

const { expect } = require('chai');
const { setup } = require('./setup.js');
const { unlimitedAllowance, getPoolByAddress } = require('./utils.js');
const { presignedMintMessage } = require('./shared/uid-helper.js');
const { POOL_ADMIN_ROLE } = require('./constants.js');
const { OWNER_ROLE } = require('./constants');

const RATE_SCALING_FACTOR = 10 ** 4;

const SaleType = {
    MINTED_INCREASING_INTEREST: 0,
    NORMAL_SALE: 1,
};

describe('SecuritizationManager', () => {
    let stableCoin;
    let securitizationManager;
    let securitizationPoolContract;
    let uniqueIdentity;
    // Wallets
    let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner;
    before('create fixture', async () => {
        [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner] =
            await ethers.getSigners();

        ({ stableCoin, securitizationManager, uniqueIdentity } = await setup());

        await stableCoin.transfer(lenderSigner.address, parseEther('1000'));
    });

    it('should emit RoleGranted event with an address', async function () {
        const transaction = await securitizationManager.grantRole(POOL_ADMIN_ROLE, poolCreatorSigner.address);
        await transaction.wait();
        await expect(transaction)
            .to.emit(securitizationManager, 'RoleGranted')
            .withArgs(POOL_ADMIN_ROLE, poolCreatorSigner.address, untangledAdminSigner.address);
    });
    describe('#newPoolInstance', async () => {
        it('Should create new pool instance', async function () {
            const minFirstLostCushion = 10 * RATE_SCALING_FACTOR;

            const transaction = await securitizationManager.connect(poolCreatorSigner).newPoolInstance(
                utils.keccak256(Date.now()),

                poolCreatorSigner.address,
                utils.defaultAbiCoder.encode(
                    [
                        {
                            type: 'tuple',
                            components: [
                                {
                                    name: 'currency',
                                    type: 'address',
                                },
                                {
                                    name: 'minFirstLossCushion',
                                    type: 'uint32',
                                },
                                {
                                    name: 'validatorRequired',
                                    type: 'bool',
                                },
                                {
                                    name: 'debtCeiling',
                                    type: 'uint256',
                                },
                            ],
                        },
                    ],
                    [
                        {
                            currency: stableCoin.address,
                            minFirstLossCushion: minFirstLostCushion,
                            validatorRequired: true,
                            debtCeiling: parseEther('1000').toString(),
                        },
                    ]
                )
            );
            const receipt = await transaction.wait();
            const [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;
            expect(securitizationPoolAddress).to.be.properAddress;

            securitizationPoolContract = await getPoolByAddress(securitizationPoolAddress);
            expect(await securitizationPoolContract.underlyingCurrency()).to.equal(stableCoin.address);
            expect(await securitizationPoolContract.minFirstLossCushion()).to.equal(minFirstLostCushion);
            expect(await securitizationManager.isExistingPools(securitizationPoolAddress)).to.equal(true);
            expect(await securitizationPoolContract.hasRole(OWNER_ROLE, poolCreatorSigner.address)).to.equal(true);
        });

        it('revert if minFistLossCushion >= 100%', async () => {
            const minFirstLostCushion = 101 * RATE_SCALING_FACTOR;

            await expect(
                securitizationManager.connect(poolCreatorSigner).newPoolInstance(
                    utils.keccak256(Date.now()),

                    poolCreatorSigner.address,
                    utils.defaultAbiCoder.encode(
                        [
                            {
                                type: 'tuple',
                                components: [
                                    {
                                        name: 'currency',
                                        type: 'address',
                                    },
                                    {
                                        name: 'minFirstLossCushion',
                                        type: 'uint32',
                                    },
                                    {
                                        name: 'validatorRequired',
                                        type: 'bool',
                                    },
                                    {
                                        name: 'debtCeiling',
                                        type: 'uint256',
                                    },
                                ],
                            },
                        ],
                        [
                            {
                                currency: stableCoin.address,
                                minFirstLossCushion: minFirstLostCushion,
                                validatorRequired: true,
                                debtCeiling: parseEther('1000').toString(),
                            },
                        ]
                    )
                )
            ).to.be.revertedWith(`minFirstLossCushion is greater than 100`);
        });

        it('only pool creator role can create pool', async () => {
            await expect(
                securitizationManager.connect(lenderSigner).newPoolInstance(
                    utils.keccak256(Date.now()),

                    lenderSigner.address,
                    utils.defaultAbiCoder.encode(
                        [
                            {
                                type: 'tuple',
                                components: [
                                    {
                                        name: 'currency',
                                        type: 'address',
                                    },
                                    {
                                        name: 'minFirstLossCushion',
                                        type: 'uint32',
                                    },
                                    {
                                        name: 'validatorRequired',
                                        type: 'bool',
                                    },
                                ],
                            },
                        ],
                        [
                            {
                                currency: stableCoin.address,
                                minFirstLossCushion: '100000',
                                validatorRequired: true,
                            },
                        ]
                    )
                )
            ).to.be.revertedWith(
                `AccessControl: account ${lenderSigner.address.toLowerCase()} is missing role 0x3e9c05fb0f9da4414e033bb9bf190a6e2072adf7e3077394fce683220513b8d7`
            );
        });
    });
    describe('#setUpTGEForSOT', async () => {
        let mintedIncreasingInterestTGE;
        let sotTokenAddress;

        it('Should set up TGE for SOT successfully', async () => {
            const openingTime = dayjs(new Date()).unix();
            const closingTime = dayjs(new Date()).add(7, 'days').unix();
            const rate = 2;
            const totalCapOfToken = parseEther('100000');
            const initialInterest = 100000;
            const finalInterest = 100000;
            const timeInterval = 1 * 24 * 3600; // seconds
            const amountChangeEachInterval = 0;
            const prefixOfNoteTokenSaleName = 'SOT_';

            const transaction = await securitizationManager.connect(poolCreatorSigner).setUpTGEForSOT(
                {
                    issuerTokenController: untangledAdminSigner.address,
                    pool: securitizationPoolContract.address,
                    minBidAmount: parseEther('1'),
                    saleType: SaleType.MINTED_INCREASING_INTEREST,
                    longSale: true,
                    ticker: prefixOfNoteTokenSaleName,
                },
                { openingTime: openingTime, closingTime: closingTime, rate: rate, cap: totalCapOfToken },
                {
                    initialInterest,
                    finalInterest,
                    timeInterval,
                    amountChangeEachInterval,
                }
            );

            const receipt = await transaction.wait();

            const [tgeAddress] = receipt.events.find((e) => e.event == 'NewTGECreated').args;
            expect(tgeAddress).to.be.properAddress;

            mintedIncreasingInterestTGE = await ethers.getContractAt('MintedIncreasingInterestTGE', tgeAddress);

            [sotTokenAddress] = receipt.events.find((e) => e.event == 'NewNotesTokenCreated').args;
            expect(sotTokenAddress).to.be.properAddress;
        });

        it('Get SOT info', async () => {
            const poolLength = await securitizationManager.getPoolsLength();
            expect(poolLength).equal(1);

            const isExistingPools = await securitizationManager.isExistingPools(securitizationPoolContract.address);
            expect(isExistingPools).equal(true);

            const pools = await securitizationManager.pools(0);
            expect(pools).equal(securitizationPoolContract.address);

            const poolToSOT = await securitizationPoolContract.sotToken();
            expect(poolToSOT).equal(sotTokenAddress);

            const isExistingTGEs = await securitizationManager.isExistingTGEs(mintedIncreasingInterestTGE.address);
            expect(isExistingTGEs).equal(true);
        });

        it('Can not buy token if not has valid UUID', async () => {
            await expect(
                securitizationManager
                    .connect(lenderSigner)
                    .buyTokens(mintedIncreasingInterestTGE.address, parseEther('100'))
            ).to.be.revertedWith('Unauthorized. Must have correct UID');
        });
        it('Register UID', async () => {
            // Gain UID
            const UID_TYPE = 0;
            const chainId = await getChainId();
            const expiredAt = dayjs().unix() + 86400 * 1000;
            const nonce = 0;
            const ethRequired = parseEther('0.00083');

            const uidMintMessage = presignedMintMessage(
                lenderSigner.address,
                UID_TYPE,
                expiredAt,
                uniqueIdentity.address,
                nonce,
                chainId
            );
            const signature = await untangledAdminSigner.signMessage(uidMintMessage);
            await uniqueIdentity.connect(lenderSigner).mint(UID_TYPE, expiredAt, signature, { value: ethRequired });

            await stableCoin.connect(lenderSigner).approve(mintedIncreasingInterestTGE.address, unlimitedAllowance);
        });

        it('Should buy tokens failed if buy sot first', async () => {
            await expect(
                securitizationManager
                    .connect(lenderSigner)
                    .buyTokens(mintedIncreasingInterestTGE.address, parseEther('100'))
            ).to.be.revertedWith(`Crowdsale: sale not started`);
        });
    });

    describe('#setUpTGEForJOT', async () => {
        let mintedIncreasingInterestTGE;
        let jotTokenAddress;

        it('Should set up TGE for JOT successfully', async () => {
            const openingTime = dayjs(new Date()).unix();
            const closingTime = dayjs(new Date()).add(7, 'days').unix();
            const rate = 2;
            const totalCapOfToken = parseEther('100000');
            const prefixOfNoteTokenSaleName = 'JOT_';
            const initialJOTAmount = parseEther('100');

            // JOT only has SaleType.NORMAL_SALE
            const transaction = await securitizationManager.connect(poolCreatorSigner).setUpTGEForJOT(
                {
                    issuerTokenController: untangledAdminSigner.address,
                    pool: securitizationPoolContract.address,
                    minBidAmount: parseEther('50'),
                    saleType: SaleType.NORMAL_SALE,
                    longSale: true,
                    ticker: prefixOfNoteTokenSaleName,
                },
                { openingTime: openingTime, closingTime: closingTime, rate: rate, cap: totalCapOfToken },
                initialJOTAmount
            );
            const receipt = await transaction.wait();

            const [tgeAddress] = receipt.events.find((e) => e.event == 'NewTGECreated').args;
            expect(tgeAddress).to.be.properAddress;

            mintedIncreasingInterestTGE = await ethers.getContractAt('MintedIncreasingInterestTGE', tgeAddress);

            [jotTokenAddress] = receipt.events.find((e) => e.event == 'NewNotesTokenCreated').args;
            expect(jotTokenAddress).to.be.properAddress;
        });

        it('Get JOT info', async () => {
            const isExistingPools = await securitizationManager.isExistingPools(securitizationPoolContract.address);
            expect(isExistingPools).equal(true);

            const pools = await securitizationManager.pools(0);
            expect(pools).equal(securitizationPoolContract.address);

            const poolToJOT = await securitizationPoolContract.jotToken(); //await securitizationManager.poolToJOT(securitizationPoolContract.address);
            expect(poolToJOT).equal(jotTokenAddress);

            const isExistingTGEs = await securitizationManager.isExistingTGEs(mintedIncreasingInterestTGE.address);
            expect(isExistingTGEs).equal(true);
        });

        // it('Should pause all pools', async () => {
        //   await stableCoin.connect(lenderSigner).approve(mintedIncreasingInterestTGE.address, unlimitedAllowance);
        //   await securitizationManager.connect(poolCreatorSigner).pauseAllPools();

        //   await expect(
        //     securitizationManager.connect(lenderSigner).buyTokens(mintedIncreasingInterestTGE.address, parseEther('100'))
        //   ).to.be.revertedWith(`Pausable: paused`);
        // });

        // it('Should un-pause all pools', async () => {
        //   await securitizationManager.connect(poolCreatorSigner).unpauseAllPools();
        // });

        it('Should buy tokens successfully', async () => {
            await stableCoin.connect(lenderSigner).approve(mintedIncreasingInterestTGE.address, unlimitedAllowance);
            await securitizationManager
                .connect(lenderSigner)
                .buyTokens(mintedIncreasingInterestTGE.address, parseEther('100'));

            let stablecoinBalanceOfPayerAfter = await stableCoin.balanceOf(lenderSigner.address);
            expect(formatEther(stablecoinBalanceOfPayerAfter)).equal('900.0');

            expect(formatEther(await stableCoin.balanceOf(securitizationPoolContract.address))).equal('100.0');

            await securitizationManager
                .connect(lenderSigner)
                .buyTokens(mintedIncreasingInterestTGE.address, parseEther('100'));

            stablecoinBalanceOfPayerAfter = await stableCoin.balanceOf(lenderSigner.address);
            expect(formatEther(stablecoinBalanceOfPayerAfter)).equal('800.0');

            expect(formatEther(await stableCoin.balanceOf(securitizationPoolContract.address))).equal('200.0');
        });

        it('Should pause pool', async () => {
            await securitizationPoolContract.connect(poolCreatorSigner).pause();
            // await securitizationManager.connect(poolCreatorSigner).pausePool(securitizationPoolContract.address);

            await expect(
                securitizationManager
                    .connect(lenderSigner)
                    .buyTokens(mintedIncreasingInterestTGE.address, parseEther('100'))
            ).to.be.revertedWith(`Pausable: paused`);
        });

        it('Should un-pause pool', async () => {
            // await securitizationManager.connect(poolCreatorSigner).unpausePool(securitizationPoolContract.address);
            await securitizationPoolContract.connect(poolCreatorSigner).unpause();
        });
    });
});
