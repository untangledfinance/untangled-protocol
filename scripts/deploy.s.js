const { ethers, upgrades } = require('hardhat');
const { OWNER_ROLE, POOL_ADMIN_ROLE, ORIGINATOR_ROLE, VALIDATOR_ROLE, BACKEND_ADMIN } = require('../test/constants');
const { LAT_BASE_URI } = require('../test/shared/constants');
const dayjs = require('dayjs');
const {
    genRiskScoreParam,
    genLoanAgreementIds,
    saltFromOrderValues,
    debtorsFromOrderAddresses,
    packTermsContractParameters,
    interestRateFixedPoint,
    genSalt,
    generateLATMintPayload,
    getPoolByAddress,
    formatFillDebtOrderParams,
    unlimitedAllowance,
} = require('../test/utils');
const { presignedMintMessage } = require('../test/shared/uid-helper.js');
async function main() {
    const backendAdress = '0x39870fb7417307f602dc2e9d997e3f1d20762669';
    const [deployer] = await ethers.getSigners();
    console.log('deployer: ', deployer.address);
    const Registry = await ethers.getContractFactory('Registry');
    const registry = await upgrades.deployProxy(Registry, []);

    const admin = await upgrades.admin.getInstance();
    const factoryAdmin = await ethers.getContractAt('ProxyAdmin', admin.address);

    const tokenFactory = await ethers.getContractFactory('TestERC20');
    const USDC = await tokenFactory.deploy('USDC', 'USDC', ethers.utils.parseEther('10000000'));

    await USDC.transfer(deployer.address, ethers.utils.parseEther('2000000'));
    const SecuritizationManager = await ethers.getContractFactory('SecuritizationManager');
    const securitizationManager = await upgrades.deployProxy(SecuritizationManager, [
        registry.address,
        factoryAdmin.address,
    ]);
    await securitizationManager.grantRole(POOL_ADMIN_ROLE, deployer.address);
    await registry.setSecuritizationManager(securitizationManager.address);

    const SecuritizationPoolValueService = await ethers.getContractFactory('SecuritizationPoolValueService');
    const securitizationPoolValueService = await upgrades.deployProxy(SecuritizationPoolValueService, [
        registry.address,
    ]);
    await registry.setSecuritizationPoolValueService(securitizationPoolValueService.address);

    // setup NoteTokenFatory
    const NoteTokenFactory = await ethers.getContractFactory('NoteTokenFactory');
    const noteTokenFactory = await upgrades.deployProxy(NoteTokenFactory, [registry.address, factoryAdmin.address]);
    const NoteToken = await ethers.getContractFactory('NoteToken');
    const noteTokenImpl = await NoteToken.deploy();
    await noteTokenFactory.setNoteTokenImplementation(noteTokenImpl.address);
    await registry.setNoteTokenFactory(noteTokenFactory.address);

    // setup TokenGenerationEventFactory
    const TokenGenerationEventFactory = await ethers.getContractFactory('TokenGenerationEventFactory');
    const tokenGenerationEventFactory = await upgrades.deployProxy(TokenGenerationEventFactory, [
        registry.address,
        factoryAdmin.address,
    ]);

    const MintedNormalTGE = await ethers.getContractFactory('MintedNormalTGE');
    const mintedNormalTGEImpl = await MintedNormalTGE.deploy();

    await tokenGenerationEventFactory.setTGEImplAddress(0, mintedNormalTGEImpl.address);

    await tokenGenerationEventFactory.setTGEImplAddress(1, mintedNormalTGEImpl.address);

    await registry.setTokenGenerationEventFactory(tokenGenerationEventFactory.address);
    // setup Pool
    const PoolNAVLogic = await ethers.getContractFactory('PoolNAVLogic');
    const poolNAVLogic = await PoolNAVLogic.deploy();
    await poolNAVLogic.deployed();
    const PoolAssetLogic = await ethers.getContractFactory('PoolAssetLogic', {
        libraries: {
            PoolNAVLogic: poolNAVLogic.address,
        },
    });
    const poolAssetLogic = await PoolAssetLogic.deploy();
    await poolAssetLogic.deployed();
    const TGELogic = await ethers.getContractFactory('TGELogic');
    const tgeLogic = await TGELogic.deploy();
    await tgeLogic.deployed();

    const RebaseLogic = await ethers.getContractFactory('RebaseLogic');
    const rebaseLogic = await RebaseLogic.deploy();
    await rebaseLogic.deployed();

    const SecuritizationPool = await ethers.getContractFactory('Pool', {
        libraries: {
            PoolAssetLogic: poolAssetLogic.address,
            PoolNAVLogic: poolNAVLogic.address,
            TGELogic: tgeLogic.address,
            RebaseLogic: rebaseLogic.address,
        },
    });
    const securitizationPoolImpl = await SecuritizationPool.deploy();
    await securitizationPoolImpl.deployed();
    await registry.setSecuritizationPool(securitizationPoolImpl.address);

    const UniqueIdentity = await ethers.getContractFactory('UniqueIdentity');
    const uniqueIdentity = await upgrades.deployProxy(UniqueIdentity, [deployer.address, '']);
    await uniqueIdentity.setSupportedUIDTypes([0, 1, 2, 3], [true, true, true, true]);
    await securitizationManager.setAllowedUIDTypes([0, 1, 2, 3]);

    const Go = await ethers.getContractFactory('Go');
    const go = await upgrades.deployProxy(Go, [deployer.address, uniqueIdentity.address]);
    await registry.setGo(go.address);

    const LoanKernel = await ethers.getContractFactory('LoanKernel');
    const loanKernel = await upgrades.deployProxy(LoanKernel, [registry.address]);
    await registry.setLoanKernel(loanKernel.address);

    const NoteTokenVault = await ethers.getContractFactory('NoteTokenVault');
    const noteTokenVault = await upgrades.deployProxy(NoteTokenVault, []);
    await registry.setNoteTokenVault(noteTokenVault.address);

    const LoanAssetToken = await ethers.getContractFactory('LoanAssetToken');
    const loanAssetTokenContract = await upgrades.deployProxy(
        LoanAssetToken,
        [registry.address, 'TEST', 'TST', LAT_BASE_URI],
        {
            initializer: 'initialize(address,string,string,string)',
        }
    );
    await registry.setLoanAssetToken(loanAssetTokenContract.address);

    console.log('NoteTokenVault: ', noteTokenVault.address);
    console.log('LoanKernel: ', loanKernel.address);
    console.log('USDC: ', USDC.address);

    await securitizationManager.grantRole(OWNER_ROLE, deployer.address);

    // create pool
    const poolParams = {
        salt: ethers.utils.keccak256(Date.now()),
        debtCeiling: 10000000,
        minFirstLossCushion: 10,
        currencyAddress: USDC.address,
        validatorRequired: false,
    };
    const tx = await securitizationManager.connect(deployer).newPoolInstance(
        poolParams.salt,
        deployer.address,
        ethers.utils.defaultAbiCoder.encode(
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
                    currency: poolParams.currencyAddress,
                    minFirstLossCushion: poolParams.minFirstLossCushion * 10000,
                    validatorRequired: poolParams.validatorRequired,
                    debtCeiling: ethers.utils.parseEther(poolParams.debtCeiling.toString()).toString(),
                },
            ]
        )
    );

    const receipt = await tx.wait();
    const [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;
    const pool = await ethers.getContractAt('Pool', securitizationPoolAddress);
    await pool.connect(deployer).grantRole(VALIDATOR_ROLE, deployer.address);

    console.log('Pool: ', securitizationPoolAddress);

    // setup riskscore
    const riskScores = [
        {
            daysPastDue: 24 * 3600, // one day
            advanceRate: 1000000, // 100%
            penaltyRate: 900000, // 90%
            interestRate: 157000, // 15.7%
            probabilityOfDefault: 1000, // 0.1%
            lossGivenDefault: 250000, // 25%
            gracePeriod: 12 * 3600, // haft a day
            collectionPeriod: 12 * 3600, // haft a day
            writeOffAfterGracePeriod: 12 * 3600, // haft a day
            writeOffAfterCollectionPeriod: 12 * 3600, // haft a day
            discountRate: 157000, // 15.7%
        },
    ];
    const { daysPastDues, ratesAndDefaults, periodsAndWriteOffs } = genRiskScoreParam(...riskScores);
    await pool
        .connect(deployer)
        .setupRiskScores(daysPastDues, ratesAndDefaults, periodsAndWriteOffs, { gasLimit: 10000000 });

    // mint UID
    const UID_TYPE = 0;
    const chainId = (await ethers.provider.getNetwork()).chainId;
    const expiredAt = dayjs().unix() + 86400 * 1000;
    const nonce = 0;
    const ethRequired = ethers.utils.parseEther('0.00083');

    const uidMintMessage = presignedMintMessage(
        deployer.address,
        UID_TYPE,
        expiredAt,
        uniqueIdentity.address,
        nonce,
        chainId
    );
    const signature = await deployer.signMessage(uidMintMessage);
    await uniqueIdentity.connect(deployer).mint(UID_TYPE, expiredAt, signature, { value: ethRequired });

    // create note token sale
    const openingTime = dayjs(new Date()).unix();
    const closingTime = dayjs(new Date()).add(7, 'days').unix();
    const rate = 2;
    const totalCapOfToken = ethers.utils.parseEther('10000000');
    const interestRate = 10000; // 1%
    const timeInterval = 24 * 3600; // seconds
    const amountChangeEachInterval = 0;
    const prefixOfNoteTokenSaleName = 'Ticker_';
    const sotInfo = {
        issuerTokenController: deployer.address,
        saleType: 0,
        minBidAmount: ethers.utils.parseEther('5000'),
        openingTime,
        closingTime,
        rate,
        cap: totalCapOfToken,
        timeInterval,
        amountChangeEachInterval,
        ticker: prefixOfNoteTokenSaleName,
        interestRate,
    };

    const initialJOTAmount = ethers.utils.parseEther('100');
    const jotInfo = {
        issuerTokenController: deployer.address,
        minBidAmount: ethers.utils.parseEther('5000'),
        saleType: 1,
        longSale: true,
        ticker: prefixOfNoteTokenSaleName,
        openingTime: openingTime,
        closingTime: closingTime,
        rate: rate,
        cap: totalCapOfToken,
        initialJOTAmount,
    };

    const transactionJOTSale = await securitizationManager.connect(deployer).setUpTGEForJOT(
        {
            issuerTokenController: jotInfo.issuerTokenController,
            pool: pool.address,
            minBidAmount: jotInfo.minBidAmount,
            totalCap: jotInfo.cap,
            openingTime: jotInfo.openingTime,
            saleType: jotInfo.saleType,
            longSale: true,
            ticker: jotInfo.ticker,
        },
        jotInfo.initialJOTAmount
    );
    const receiptJOTSale = await transactionJOTSale.wait();

    const [jotTokenAddress, jotTGEAddress] = receiptJOTSale.events.find((e) => e.event == 'SetupJot').args;
    console.log('JOT: ', jotTokenAddress);
    console.log('JOT TGE: ', jotTGEAddress);

    const transactionSOTSale = await securitizationManager.connect(deployer).setUpTGEForSOT(
        {
            issuerTokenController: sotInfo.issuerTokenController,
            pool: pool.address,
            minBidAmount: sotInfo.minBidAmount,
            totalCap: sotInfo.cap,
            openingTime: sotInfo.openingTime,
            saleType: sotInfo.saleType,
            ticker: sotInfo.ticker,
        },
        sotInfo.interestRate
    );
    const receiptSOTSale = await transactionSOTSale.wait();
    const [sotTokenAddress, sotTGEAddress] = receiptSOTSale.events.find((e) => e.event == 'SetupSot').args;
    console.log('SOT: ', sotTokenAddress);
    console.log('SOT TGE: ', sotTGEAddress);

    const investAmount = ethers.utils.parseEther('500000');
    // 500,000$ invest in JOT
    await USDC.connect(deployer).approve(jotTGEAddress, investAmount);

    await securitizationManager.connect(deployer).buyTokens(jotTGEAddress, investAmount);

    // 500,000$ invest in SOT
    await USDC.connect(deployer).approve(sotTGEAddress, investAmount);

    await securitizationManager.connect(deployer).buyTokens(sotTGEAddress, investAmount);
    // upload loan
    await pool.connect(deployer).grantRole(ORIGINATOR_ROLE, deployer.address);
    const loans = [
        {
            principalAmount: 100000000000000000000000n,
            expirationTimestamp: dayjs(new Date()).unix() + 3600 * 24 * 900,
            assetPurpose: 0,
            termInDays: 900,
            riskScore: '1',
            salt: ethers.utils.keccak256(Date.now()),
        },
    ];

    const CREDITOR_FEE = '0';
    const orderAddresses = [
        pool.address,
        USDC.address,
        loanKernel.address,
        // borrower 1
        // borrower 2
        // ...
        ...new Array(loans.length).fill(deployer.address),
    ];
    const orderValues = [
        CREDITOR_FEE,
        0,
        ...loans.map((l) => ethers.utils.parseEther(l.principalAmount.toString())),
        ...loans.map((l) => l.expirationTimestamp),
        ...loans.map((l) => l.salt || 0),
        ...loans.map((l) => l.riskScore),
    ];

    const interestRatePercentage = 5;

    const termsContractParameters = loans.map((l) =>
        packTermsContractParameters({
            amortizationUnitType: 1,
            gracePeriodInDays: 2,
            principalAmount: l.principalAmount,
            termLengthUnits: l.termInDays * 24,
            interestRateFixedPoint: interestRateFixedPoint(interestRatePercentage),
        })
    );

    const salts = saltFromOrderValues(orderValues, termsContractParameters.length);
    const debtors = debtorsFromOrderAddresses(orderAddresses, termsContractParameters.length);

    const tokenIds = genLoanAgreementIds(loanKernel.address, debtors, termsContractParameters, salts);
    const fillDebtOrderParams = formatFillDebtOrderParams(
        orderAddresses,
        orderValues,
        termsContractParameters,
        await Promise.all(
            tokenIds.map(async (x, i) => ({
                ...(await generateLATMintPayload(
                    loanKernel,
                    deployer,
                    [x],
                    [loans[i].nonce || (await loanAssetTokenContract.nonce(x)).toNumber()],
                    deployer.address
                )),
            }))
        )
    );

    await loanKernel.connect(deployer).fillDebtOrder(fillDebtOrderParams);

    await noteTokenVault.grantRole(BACKEND_ADMIN, backendAdress);
    const sotToken = await ethers.getContractAt('NoteToken', sotTokenAddress);
    const jotToken = await ethers.getContractAt('NoteToken', jotTokenAddress);

    await sotToken.connect(deployer).approve(noteTokenVault.address, unlimitedAllowance);
    await jotToken.connect(deployer).approve(noteTokenVault.address, unlimitedAllowance);

    await noteTokenVault.connect(deployer).createOrder(securitizationPoolAddress, {
        sotCurrencyAmount: ethers.utils.parseEther('2000'),
        jotCurrencyAmount: ethers.utils.parseEther('3000'),
        allSOTIncomeOnly: false,
        allJOTIncomeOnly: false,
    });

    console.log(await noteTokenVault.getOrder(securitizationPoolAddress, deployer.address));
}

main();
