const { genRiskScoreParam } = require('../test/utils');
const { ethers } = require('hardhat');

module.exports = async ({ getNamedAccounts, deployments }) => {
    const pool = await ethers.getContractAt('Pool', network.config.pool);

    const oneDayInSecs = 1 * 24 * 3600;
    const halfOfADay = oneDayInSecs / 2;
    const riskScores = [
        {
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
        },
    ];
    const { daysPastDues, ratesAndDefaults, periodsAndWriteOffs } = genRiskScoreParam(...riskScores);

    await pool.setupRiskScores(daysPastDues, ratesAndDefaults, periodsAndWriteOffs, { gasLimit: 10000000 });
};

module.exports.tags = ['SetupRiskscores'];
