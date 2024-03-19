// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;
interface IEpochExecutor {
    struct OrderSummary {
        uint256 sotWithdraw;
        uint256 jotWithdraw;
        uint256 sotInvest;
        uint256 jotInvest;
    }

    struct EpochInformation {
        uint256 lastEpochClosed;
        uint256 minimumEpochTime;
        uint256 lastEpochExecuted;
        uint256 currentEpoch;
        uint256 bestSubScore;
        uint256 sotPrice;
        uint256 jotPrice;
        uint256 epochNAV;
        uint256 epochSeniorAsset;
        uint256 epochCapitalReserve;
        uint256 epochIncomeReserve;
        uint256 minChallengePeriodEnd;
        uint256 challengeTime;
        uint256 bestRatioImprovement;
        uint256 bestReserveImprovement;
        bool poolClosing;
        bool submitPeriod;
        bool gotFullValidation;
        OrderSummary order;
        OrderSummary bestSubmission;
    }

    function setupPool() external;
    function setParam(address pool, bytes32 name, uint256 value) external;
    function setParam(address pool, bytes32 name, bool value) external;
    function closeEpoch(address pool) external returns (bool epochExecuted);
    function validate(
        address pool,
        uint256 seniorWithdraw,
        uint256 juniorWithdraw,
        uint256 seniorInvest,
        uint256 juniorInvest
    ) external view returns (int256 err);
    function calcNewReserve(
        address pool,
        uint256 sotWithdraw,
        uint256 jotWithdraw,
        uint256 sotInvest,
        uint256 jotInvest
    ) external view returns (uint256 reserve);
    function currentEpoch(address pool) external view returns (uint256);
    function lastEpochExecuted(address pool) external view returns (uint256);
    function getNoteTokenAddress(address pool) external view returns (address, address);
}
