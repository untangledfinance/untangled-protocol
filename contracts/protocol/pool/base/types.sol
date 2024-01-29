// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import '../../../libraries/Configuration.sol';

struct RiskScore {
    uint32 daysPastDue;
    uint32 advanceRate;
    uint32 penaltyRate;
    uint32 interestRate;
    uint32 probabilityOfDefault;
    uint32 lossGivenDefault;
    uint32 writeOffAfterGracePeriod;
    uint32 gracePeriod;
    uint32 collectionPeriod;
    uint32 writeOffAfterCollectionPeriod;
    uint32 discountRate;
}

struct LoanEntry {
    address debtor;
    address principalTokenAddress;
    bytes32 termsParam; // actually inside this param was already included P token address
    uint256 salt;
    uint256 issuanceBlockTimestamp;
    uint256 expirationTimestamp;
    uint8 riskScore;
    Configuration.ASSET_PURPOSE assetPurpose;
}
