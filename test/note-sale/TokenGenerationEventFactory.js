const { artifacts } = require('hardhat');
const { setup } = require('../setup');
const { expect } = require('chai');
const { BigNumber, utils } = require('ethers');
const { keccak256 } = require('@ethersproject/keccak256');
const { parseEther } = ethers.utils;
const dayjs = require('dayjs');

const { POOL_ADMIN_ROLE } = require('../constants.js');
const UntangledProtocol = require('../shared/untangled-protocol');
const { SaleType } = require('../shared/constants.js');

describe('TokenGenerationEventFactory', () => {
    let registry;
    let tokenGenerationEventFactory;
    let securitizationManager;
    let stableCoin;
    let poolCreatorSigner;
    let untangledProtocol;

    before('create fixture', async () => {
        const contracts = await setup();
        untangledProtocol = UntangledProtocol.bind(contracts);
        ({ registry, tokenGenerationEventFactory, stableCoin, securitizationManager } = await setup());

        [untangledAdminSigner, , poolCreatorSigner] = await ethers.getSigners();

        await securitizationManager.grantRole(POOL_ADMIN_ROLE, poolCreatorSigner.address);
    });

    it('#pauseUnpauseTge', async () => {
        const poolAddress = await untangledProtocol.createSecuritizationPool(poolCreatorSigner);

        const [issuer] = await ethers.getSigners();

        const openingTime = dayjs(new Date()).unix();
        const closingTime = dayjs(new Date()).add(7, 'days').unix();
        const rate = 2;
        const totalCapOfToken = parseEther('100000');
        const initialInterest = 10000;
        const finalInterest = 10000;
        const timeInterval = 1 * 24 * 3600; // seconds
        const amountChangeEachInterval = 0;
        const prefixOfNoteTokenSaleName = 'SOT_';

        const transactionSOTSale = await securitizationManager.connect(poolCreatorSigner).setUpTGEForSOT(
            {
                issuerTokenController: untangledAdminSigner.address,
                pool: poolAddress,
                minBidAmount: parseEther('50'),
                saleType: SaleType.MINTED_INCREASING_INTEREST,
                longSale: true,
                ticker: prefixOfNoteTokenSaleName,
            },
            {
                openingTime: openingTime,
                closingTime: closingTime,
                rate: rate,
                cap: totalCapOfToken,
            },
            {
                initialInterest: initialInterest,
                finalInterest: finalInterest,
                timeInterval: timeInterval,
                amountChangeEachInterval: amountChangeEachInterval,
            }
        );
        const receiptSOTSale = await transactionSOTSale.wait();
        const [sotTokenAddress, sotTGEAddress] = receiptSOTSale.events.find((e) => e.event == 'SetupSot').args;

        await expect(tokenGenerationEventFactory.pauseUnpauseTge(sotTGEAddress)).to.not.be.reverted;
    });

    it('#unPauseAllTges', async () => {
        await expect(tokenGenerationEventFactory.pauseUnpauseAllTges()).to.not.be.reverted;
    });
});
