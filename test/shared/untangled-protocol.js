const { utils } = require('ethers');
const { ethers } = require('hardhat');
const { getChainId } = require('hardhat');
const { BigNumber } = ethers;
const { parseEther, formatEther } = ethers.utils;
const { RATE_SCALING_FACTOR } = require('../shared/constants.js');

const {
    genLoanAgreementIds,
    saltFromOrderValues,
    debtorsFromOrderAddresses,
    packTermsContractParameters,
    interestRateFixedPoint,
    genSalt,
    generateLATMintPayload,
    genRiskScoreParam,
    getPoolByAddress,
    formatFillDebtOrderParams,
    ZERO_ADDRESS,
} = require('../utils.js');
const dayjs = require('dayjs');
const _ = require('lodash');
const { presignedMintMessage } = require('./uid-helper.js');

function getTokenAddressFromSymbol(symbol) {
    switch (symbol) {
        case 'cUSD':
            return this.stableCoin.address;
        case 'USDT':
            return this.stableCoin.address;
        case 'USDC':
            return this.stableCoin.address;
    }
}

async function createSecuritizationPool(
    signer,
    minFirstLossCushion = 10,
    debtCeiling = 1000,
    currency = 'cUSD',
    validatorRequired = true,
    salt = utils.keccak256(Date.now())
) {
    let transaction = await this.securitizationManager
        .connect(signer)

        .newPoolInstance(
            salt,

            signer.address,
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
                        currency: getTokenAddressFromSymbol.call(this, currency),
                        minFirstLossCushion: BigNumber.from(minFirstLossCushion * RATE_SCALING_FACTOR),
                        validatorRequired: validatorRequired,
                        debtCeiling: parseEther(debtCeiling.toString()).toString(),
                    },
                ]
            )
        );

    const receipt = await transaction.wait();
    const [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;
    return securitizationPoolAddress;
}

async function createFullPool(signer, poolParams, riskScores, sotInfo, jotInfo) {
    const poolAddress = await createSecuritizationPool.call(
        this,
        signer,
        poolParams.minFirstLossCushion,
        poolParams.debtCeiling,
        poolParams.currency,
        poolParams.validatorRequired
    );
    const securitizationPoolContract = await getPoolByAddress(poolAddress);
    await setupRiskScore.call(this, signer, securitizationPoolContract, riskScores);
    const sotCreated =
        sotInfo && (await initSOTSale.call(this, signer, { ...sotInfo, pool: securitizationPoolContract.address }));
    const jotCreated =
        jotInfo && (await initJOTSale.call(this, signer, { ...jotInfo, pool: securitizationPoolContract.address }));
    return [poolAddress, sotCreated, jotCreated];
}

async function setupRiskScore(signer, securitizationPoolContract, riskScores) {
    const { daysPastDues, ratesAndDefaults, periodsAndWriteOffs } = genRiskScoreParam(...riskScores);

    return securitizationPoolContract
        .connect(signer)
        .setupRiskScores(daysPastDues, ratesAndDefaults, periodsAndWriteOffs);
}

async function fillDebtOrder(
    signer,
    securitizationPoolContract,
    borrowerSigner,
    assetPurpose,
    loans,
    validatorSigner,
    validatorAddress
) {
    const CREDITOR_FEE = '0';

    const orderAddresses = [
        securitizationPoolContract.address,
        this.stableCoin.address,
        this.loanRepaymentRouter.address,
        // borrower 1
        // borrower 2
        // ...
        ...new Array(loans.length).fill(borrowerSigner.address),
    ];

    const orderValues = [
        CREDITOR_FEE,
        assetPurpose,
        ...loans.map((l) => parseEther(l.principalAmount.toString())),
        ...loans.map((l) => l.expirationTimestamp),
        ...loans.map((l) => l.salt || genSalt()),
        ...loans.map((l) => l.riskScore),
    ];

    const interestRatePercentage = 5;

    const termsContractParameters = loans.map((l) =>
        packTermsContractParameters({
            amortizationUnitType: 1,
            gracePeriodInDays: 2,
            principalAmount: l.principalAmount,
            termLengthUnits: _.ceil(l.termInDays * 24),
            interestRateFixedPoint: interestRateFixedPoint(interestRatePercentage),
        })
    );

    const salts = saltFromOrderValues(orderValues, termsContractParameters.length);
    const debtors = debtorsFromOrderAddresses(orderAddresses, termsContractParameters.length);

    const tokenIds = genLoanAgreementIds(this.loanRepaymentRouter.address, debtors, termsContractParameters, salts);

    const fillDebtOrderParams = formatFillDebtOrderParams(
        orderAddresses,
        orderValues,
        termsContractParameters,
        await Promise.all(
            tokenIds.map(async (x, i) => ({
                ...(await generateLATMintPayload(
                    this.loanAssetTokenContract,
                    validatorSigner || this.defaultLoanAssetTokenValidator,
                    [x],
                    [loans[i].nonce || (await this.loanAssetTokenContract.nonce(x)).toNumber()],
                    validatorAddress || this.defaultLoanAssetTokenValidator.address
                )),
            }))
        )
    );
    await this.loanKernel.connect(signer).fillDebtOrder(fillDebtOrderParams);
    return tokenIds;
}

async function initSOTSale(signer, saleParameters) {
    const transactionSOTSale = await this.securitizationManager.connect(signer).setUpTGEForSOT(
        {
            issuerTokenController: saleParameters.issuerTokenController,
            pool: saleParameters.pool,
            minBidAmount: saleParameters.minBidAmount,
            saleType: saleParameters.saleType,
            longSale: true,
            ticker: saleParameters.ticker,
        },
        {
            openingTime: saleParameters.openingTime,
            closingTime: saleParameters.closingTime,
            rate: saleParameters.rate,
            cap: saleParameters.cap,
        },
        {
            initialInterest: saleParameters.initialInterest,
            finalInterest: saleParameters.finalInterest,
            timeInterval: saleParameters.timeInterval,
            amountChangeEachInterval: saleParameters.amountChangeEachInterval,
        }
    );
    const receiptSOTSale = await transactionSOTSale.wait();
    const [sotTokenAddress, sotTGEAddress] = receiptSOTSale.events.find((e) => e.event == 'SetupSot').args;

    return { sotTGEAddress, sotTokenAddress };
}

async function initJOTSale(signer, saleParameters) {
    const transactionJOTSale = await this.securitizationManager.connect(signer).setUpTGEForJOT(
        {
            issuerTokenController: saleParameters.issuerTokenController,
            pool: saleParameters.pool,
            minBidAmount: saleParameters.minBidAmount,
            saleType: saleParameters.saleType,
            longSale: true,
            ticker: saleParameters.ticker,
        },
        {
            openingTime: saleParameters.openingTime,
            closingTime: saleParameters.closingTime,
            rate: saleParameters.rate,
            cap: saleParameters.cap,
        },
        saleParameters.initialJOTAmount
    );
    const receiptJOTSale = await transactionJOTSale.wait();
    const [jotTokenAddress, jotTGEAddress] = receiptJOTSale.events.find((e) => e.event == 'SetupJot').args;

    return { jotTGEAddress, jotTokenAddress };
}

async function buyToken(signer, tgeAddress, currencyAmount) {
    await this.stableCoin.connect(signer).approve(tgeAddress, currencyAmount);
    return this.securitizationManager.connect(signer).buyTokens(tgeAddress, currencyAmount);
}

/**
 * Generates a unique identifier to signer.
 * @param  signer - The signer that signed transaction and received the unique identifier.
 */
async function mintUID(signer) {
    const UID_TYPE = 0;
    const chainId = await getChainId();
    const expiredAt = dayjs().unix() + 86400 * 1000;
    const nonce = 0;
    const ethRequired = parseEther('0.00083');

    const uidMintMessage = presignedMintMessage(
        signer.address,
        UID_TYPE,
        expiredAt,
        this.uniqueIdentity.address,
        nonce,
        chainId
    );
    const signature = await this.untangledAdminSigner.signMessage(uidMintMessage);
    await this.uniqueIdentity.connect(signer).mint(UID_TYPE, expiredAt, signature, { value: ethRequired });
}
function bind(contracts) {
    return {
        createSecuritizationPool: createSecuritizationPool.bind(contracts),
        setupRiskScore: setupRiskScore.bind(contracts),
        uploadLoans: fillDebtOrder.bind(contracts),
        initSOTSale: initSOTSale.bind(contracts),
        initJOTSale: initJOTSale.bind(contracts),
        buyToken: buyToken.bind(contracts),
        mintUID: mintUID.bind(contracts),
        createFullPool: createFullPool.bind(contracts),
    };
}

module.exports.bind = bind;
