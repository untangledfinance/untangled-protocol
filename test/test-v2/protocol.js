const { utils } = require('ethers');
const { ethers, getChainId } = require('hardhat');
const { BigNumber } = ethers;
const { parseEther } = ethers.utils;
const { RATE_SCALING_FACTOR } = require('../shared/constants');
const { VALIDATOR_ROLE } = require('../constants');
const {
    genLoanAgreementIds,
    saltFromOrderValues,
    debtorsFromOrderAddresses,
    packTermsContractParameters,
    genSalt,
    generateLATMintPayload,
    genRiskScoreParam,
    getPoolByAddress,
    formatFillDebtOrderParams,
    interestRateFixedPoint,
} = require('../utils');

const dayjs = require('dayjs');
const _ = require('lodash');
const { presignedMintMessage } = require('../shared/uid-helper');

function getTokenAddressFromSymbol(symbol) {
    switch (symbol) {
        case 'USDC':
            return this.stableCoin.address;
        case 'USDT':
            return this.stableCoin.address;
    }
}

async function createSecuritizationPool(
    signer,
    minFirstLossCushion = 10,
    debtCeiling = 1000,
    currency = 'USDC',
    validatorRequired = true,
    salt = utils.keccak256(Date.now())
) {
    let transaction = await this.securitizationManager.connect(signer).newPoolInstance(
        salt,
        signer.address,
        utils.defaultAbiCoder.encode(
            [
                {
                    type: 'tuple',
                    components: [
                        { name: 'currency', type: 'address' },
                        { name: 'minFirstLossCushion', type: 'uint32' },
                        { name: 'validatorRequired', type: 'bool' },
                        { name: 'debtCeiling', type: 'uint256' },
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
    let pool = await getPoolByAddress(securitizationPoolAddress);
    await pool.connect(signer).grantRole(VALIDATOR_ROLE, signer.address);
    return securitizationPoolAddress;
}

async function setupRiskScore(signer, securitizationPool, riskScores) {
    const { daysPastDues, ratesAndDefaults, periodsAndWriteOffs } = genRiskScoreParam(...riskScores);

    return await securitizationPool
        .connect(signer)
        .setupRiskScores(daysPastDues, ratesAndDefaults, periodsAndWriteOffs, { gasLimit: 10000000 });
}

async function fillDebtOrder(
    signer,
    securitizationPool,
    borrowSigner,
    assetPurpose,
    loans,
    validatorSigner,
    validatorAddress
) {
    const CREDITOR_FEE = '0';

    const orderAddresses = [
        securitizationPool.address,
        this.stableCoin.address,
        this.loanKernel.address,
        ...new Array(loans.length).fill(borrowSigner.address),
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

    const salt = saltFromOrderValues(orderValues, termsContractParameters.length);
    const debtors = debtorsFromOrderAddresses(orderAddresses, termsContractParameters.length);

    const tokenIds = genLoanAgreementIds(this.loanKernel.address, debtors, termsContractParameters, salt);

    const fillDebtOrderParams = formatFillDebtOrderParams(
        orderAddresses,
        orderValues,
        termsContractParameters,
        await Promise.all(
            tokenIds.map(async (x, i) => ({
                ...(await generateLATMintPayload(
                    this.loanAssetToken,
                    validatorSigner || this.defaultLoanAssetTokenValidator,
                    [x],
                    [loans[i].nonce || (await this.loanAssetToken.nonce(x)).toNumber()],
                    validatorAddress || this.defaultLoanAssetTokenValidator.address
                )),
            }))
        )
    );

    await this.loanKernel.connect(signer).fillDebtOrder(fillDebtOrderParams);
    return tokenIds;
}

async function getLoansValue(
    signer,
    securitizationPool,
    borrowSigner,
    assetPurpose,
    loans,
    validatorSigner,
    validatorAddress
) {
    const CREDITOR_FEE = '0';

    const orderAddresses = [
        securitizationPool.address,
        this.stableCoin.address,
        this.loanKernel.address,
        ...new Array(loans.length).fill(borrowSigner.address),
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

    const salt = saltFromOrderValues(orderValues, termsContractParameters.length);
    const debtors = debtorsFromOrderAddresses(orderAddresses, termsContractParameters.length);

    const tokenIds = genLoanAgreementIds(this.loanKernel.address, debtors, termsContractParameters, salt);
    const fillDebtOrderParams = formatFillDebtOrderParams(
        orderAddresses,
        orderValues,
        termsContractParameters,
        await Promise.all(
            tokenIds.map(async (x, i) => ({
                ...(await generateLATMintPayload(
                    this.loanAssetToken,
                    validatorSigner || this.defaultLoanAssetTokenValidator,
                    [x],
                    [loans[i].nonce || (await this.loanAssetToken.nonce(x)).toNumber()],
                    validatorAddress || this.defaultLoanAssetTokenValidator.address
                )),
            }))
        )
    );
    const res = await this.loanKernel.connect(signer).getLoansValue(fillDebtOrderParams);
    return { tokenIds, expectedLoansValue: res[0] };
}

async function initNoteTokenSale(signer, saleParams) {
    const transaction = await this.securitizationManager
        .connect(signer)
        .setupNoteTokenSale(
            saleParams.pool,
            saleParams.tokenType,
            saleParams.minBidAmount,
            saleParams.interestRate,
            saleParams.ticker
        );
    const receipt = await transaction.wait();
    const [poolAddress, tokenAddress] = receipt.events.find((e) => e.event == 'NewTokenCreated').args;

    return tokenAddress;
}

async function placeSOTInvestOrder(signer, pool, amount) {
    const transaction = await this.sotTokenManager.connect(signer).investOrder(pool, amount);
    const receipt = await transaction.wait();
    // const [poolAddress, sender, amount] = receipt.events.find((e) => e.event == 'InvestOrder');
    // return { poolAddress, sender, amount };
}

async function placeJOTInvestOrder(signer, pool, amount) {
    const transaction = await this.jotTokenManager.connect(signer).investOrder(pool, amount);
    const receipt = await transaction.wait();
    // const [poolAddress, sender, amount] = receipt.events.find((e) => e.event == 'InvestOrder');
    // return { poolAddress, sender, amount };
}

async function placeSOTWithdrawOrder(signer, pool, amount) {
    const transaction = await this.sotTokenManager.connect(signer).withdrawOrder(pool, amount);
    const receipt = await transaction.wait();
    // const [poolAddress, amount] = receipt.events.find((e) => e.event == 'WithdrawOrderPlaced');
    // return { poolAddress, amount };
}

async function placeJOTWithdrawOrder(signer, pool, amount) {
    const transaction = await this.jotTokenManager.connect(signer).withdrawOrder(pool, amount);
    const receipt = await transaction.wait();
    // const [poolAddress, amount] = receipt.events.find((e) => e.event == 'WithdrawOrderPlaced');
    // return { poolAddress, amount };
}

async function mintUID(signer) {
    const UID_TYPE = 0;
    const chainID = await getChainId();
    const expiredAt = dayjs().unix() + 86400 * 1000;
    const nonce = 0;
    const ethRequired = parseEther('0.00083');

    const uidMintMsg = presignedMintMessage(
        signer.address,
        UID_TYPE,
        expiredAt,
        this.uniqueIdentity.address,
        nonce,
        chainID
    );

    const signature = await this.adminSigner.signMessage(uidMintMsg);
    await this.uniqueIdentity.connect(signer).mint(UID_TYPE, expiredAt, signature, { value: ethRequired });
}

const bind = (contracts) => {
    return {
        createSecuritizationPool: createSecuritizationPool.bind(contracts),
        setupRiskScore: setupRiskScore.bind(contracts),
        fillDebtOrder: fillDebtOrder.bind(contracts),
        getLoansValue: getLoansValue.bind(contracts),
        initNoteTokenSale: initNoteTokenSale.bind(contracts),
        mintUID: mintUID.bind(contracts),
        placeJOTInvestOrder: placeJOTInvestOrder.bind(contracts),
        placeSOTInvestOrder: placeSOTInvestOrder.bind(contracts),
        placeJOTWithdrawOrder: placeJOTWithdrawOrder.bind(contracts),
        placeSOTWithdrawOrder: placeSOTWithdrawOrder.bind(contracts),
    };
};

module.exports.bind = bind;
