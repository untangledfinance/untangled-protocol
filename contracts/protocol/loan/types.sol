// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

struct LoanIssuance {
    address version;
    address termsContract;
    address[] debtors;
    bytes32[] termsContractParameters; // for different loans
    bytes32[] agreementIds;
    uint256[] salts;
}

struct LoanOrder {
    LoanIssuance issuance;
    address principalTokenAddress;
    uint256[] principalAmounts;
    uint256 creditorFee;
    address relayer;
    uint256[] expirationTimestampInSecs;
    bytes32[] debtOrderHashes;
    uint8[] riskScores;
    uint8 assetPurpose;
}
