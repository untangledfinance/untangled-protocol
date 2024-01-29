const SaleType = {
  MINTED_INCREASING_INTEREST: 0,
  NORMAL_SALE: 1,
};

const ONE_DAY_IN_SECONDS = 86400;
// A
const riskScoreA = {
  daysPastDue: ONE_DAY_IN_SECONDS,
  advanceRate: 950000, // 95%
  penaltyRate: 900000,
  interestRate: 80000, // 8%
  probabilityOfDefault: 10000, // 1%
  lossGivenDefault: 810000, // 25%
  discountRate: 100000, // 10%
  gracePeriod: ONE_DAY_IN_SECONDS*5,
  collectionPeriod: ONE_DAY_IN_SECONDS*30,
  writeOffAfterGracePeriod: 250000, // 25%
  writeOffAfterCollectionPeriod: 1000000, // 100%
};
// B
const riskScoreB = {
  daysPastDue: ONE_DAY_IN_SECONDS * 30,
  advanceRate: 900000, // 90%
  penaltyRate: 1500000,
  interestRate: 100000, // 10%
  probabilityOfDefault: 20000, // 2%
  lossGivenDefault: 500000, // 50%
  discountRate: 100000, // 10%
  gracePeriod: ONE_DAY_IN_SECONDS*5,
  collectionPeriod: ONE_DAY_IN_SECONDS*30,
  writeOffAfterGracePeriod: 500000, // 50%
  writeOffAfterCollectionPeriod: 1000000, // 100%
};
// C
const riskScoreC = {
  daysPastDue: ONE_DAY_IN_SECONDS * 60,
  advanceRate: 900000, // 90%
  penaltyRate: 1500000,
  interestRate: 120000, // 12%
  probabilityOfDefault: 30000, // 3%
  lossGivenDefault: 500000, // 50%
  discountRate: 100000, // 10%
  gracePeriod: ONE_DAY_IN_SECONDS * 5,
  collectionPeriod: ONE_DAY_IN_SECONDS * 30,
  writeOffAfterGracePeriod: 500000, // 50%
  writeOffAfterCollectionPeriod: 1000000, // 100%
};
// D
const riskScoreD = {
  daysPastDue: ONE_DAY_IN_SECONDS * 90,
  advanceRate: 800000, // 80%
  penaltyRate: 1500000,
  interestRate: 120000, // 12%
  probabilityOfDefault: 40000, // 3%
  lossGivenDefault: 750000, // 50%
  discountRate: 100000, // 10%
  gracePeriod: ONE_DAY_IN_SECONDS * 5,
  collectionPeriod: ONE_DAY_IN_SECONDS * 30,
  writeOffAfterGracePeriod: 500000, // 50%
  writeOffAfterCollectionPeriod: 1000000, // 100%
};
// E
const riskScoreE = {
  daysPastDue: ONE_DAY_IN_SECONDS * 120,
  advanceRate: 800000, // 80%
  penaltyRate: 1500000,
  interestRate: 140000, // 12%
  probabilityOfDefault: 50000, // 3%
  lossGivenDefault: 1000000, // 50%
  discountRate: 100000, // 10%
  gracePeriod: ONE_DAY_IN_SECONDS * 5,
  collectionPeriod: ONE_DAY_IN_SECONDS * 30,
  writeOffAfterGracePeriod: 1000000, // 100%
  writeOffAfterCollectionPeriod: 1000000, // 100%
};

// F
const riskScoreF = {
  daysPastDue: ONE_DAY_IN_SECONDS * 365,
  advanceRate: 0, // 0%
  penaltyRate: 1500000,
  interestRate: 100000, // 100%
  probabilityOfDefault: 100000, // 100%
  lossGivenDefault: 1000000, // 100%
  discountRate: 100000, // 10%
  gracePeriod: ONE_DAY_IN_SECONDS * 5,
  collectionPeriod: ONE_DAY_IN_SECONDS * 30,
  writeOffAfterGracePeriod: 1000000, // 100%
  writeOffAfterCollectionPeriod: 1000000, // 100%
};

const RISK_SCORES = {
  riskScoreA,
  riskScoreB,
  riskScoreC,
  riskScoreD,
  riskScoreE,
  riskScoreF,
}

const ASSET_PURPOSE = {
  LOAN: '0',
  INVOICE: '1'
}

const LAT_BASE_URI = "https://api.example.com/token/"

const RATE_SCALING_FACTOR = 10000;

module.exports = {
  SaleType,
  RISK_SCORES,
  LAT_BASE_URI,
  ASSET_PURPOSE,
  RATE_SCALING_FACTOR
};
