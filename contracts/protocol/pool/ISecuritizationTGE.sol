// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Configuration} from '../../libraries/Configuration.sol';

interface ISecuritizationTGE {
    event UpdateTGEAddress(address tge, Configuration.NOTE_TOKEN_TYPE noteType);
    event UpdatePaidPrincipalAmountSOTByInvestor(address indexed user, uint256 currencyAmount);
    event IncreaseReserve(uint256 increasingAmount, uint256 currencyAmount);
    event DecreaseReserve(uint256 decreasingAmount, uint256 currencyAmount);
    event UpdateInterestRateSOT(uint32 _interestRateSOT);
    event UpdateDebtCeiling(uint256 _debtCeiling);
    event UpdateMintFirstLoss(uint32 _mintFirstLoss);
    event Withdraw(address originatorAddress, uint256 amount);
    event ClaimCashRemain(address pot, address recipientWallet, uint256 balance);
    event StartCycle(uint32 interestRateSOT);

    /// @notice sets the pot address for the contract
    function setPot(address _pot) external;

    /// @notice sets debt ceiling value
    function setDebtCeiling(uint256 _debtCeiling) external;

    /// @notice sets mint first loss value
    function setMinFirstLossCushion(uint32 _minFirstLossCushion) external;

    // function pot() external view returns (address);

    /// @dev trigger update reserve when buy note token action happens
    function increaseReserve(uint256 currencyAmount) external;

    /// @dev trigger update reserve
    function decreaseReserve(uint256 currencyAmount) external;

    // function tgeAddress() external view returns (address);

    // function secondTGEAddress() external view returns (address);

    function sotToken() external view returns (address);

    function jotToken() external view returns (address);

    function underlyingCurrency() external view returns (address);

    function paidPrincipalAmountSOT() external view returns (uint256);

    function paidPrincipalAmountSOTByInvestor(address user) external view returns (uint256);

    function reserve() external view returns (uint256);

    function debtCeiling() external view returns (uint256);

    function interestRateSOT() external view returns (uint32); // Annually, support 4 decimals num

    function minFirstLossCushion() external view returns (uint32);

    function totalAssetRepaidCurrency() external view returns (uint256); // Total $ (cUSD) paid for Asset repayment - repayInBatch

    /// @notice injects the address of the Token Generation Event (TGE) and the associated token address
    function injectTGEAddress(
        address _tgeAddress,
        // address _tokenAddress,
        Configuration.NOTE_TOKEN_TYPE _noteToken
    ) external;

    /// @dev trigger update asset value repaid
    function increaseTotalAssetRepaidCurrency(uint256 amount) external;

    /// @dev Disburses a specified amount of currency to the given user.
    /// @param usr The address of the user to receive the currency.
    /// @param currencyAmount The amount of currency to disburse.
    function disburse(address usr, uint256 currencyAmount) external;

    /// @notice checks if the redemption process has finished
    function hasFinishedRedemption() external view returns (bool);

    ///@notice check current debt ceiling is valid
    function isDebtCeilingValid() external view returns (bool);

    /// @notice sets the interest rate for the senior tranche of tokens
    function setInterestRateForSOT(uint32 _interestRateSOT) external;

    function claimCashRemain(address recipientWallet) external;

    // function openingBlockTimestamp() external view returns (uint64);

    function startCycle() external;

    /// @notice allows the originator to withdraw from reserve
    function withdraw(address to, uint256 amount) external;
}
