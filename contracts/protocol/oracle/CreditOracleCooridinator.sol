// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import '../../interfaces/ILogAutomation.sol';
import './CreditOracleConsumerBase.sol';
import {IHalo2Verifier} from '../../interfaces/IVerifier.sol';

contract CreditOracleCoordinator is ILogAutomation {
    address private immutable verifier;

    event CreditRequested(
        address indexed sender,
        uint16 monthOnBool,
        uint16 interestRateAdj,
        uint16 term,
        uint16 originalPrincipalBalance,
        uint16 outstandingPrincipalBalance
    );
    event FulfillProof(address indexed sender, bytes proof, uint256[] pubInputs);
    event FulfillProof(address indexed sender, bytes proofAndPubInputs);
    event PerformUpkeep(address indexed to, bytes data);
    error InvalidProof();

    constructor(address _verifier) {
        verifier = _verifier;
    }

    function requestCredit(
        uint16 monthOnBook,
        uint16 interestRateAdj,
        uint16 term,
        uint16 originalPrincipalBalance,
        uint16 outstandingPrincipalBalance
    ) external {
        emit CreditRequested(
            msg.sender,
            monthOnBook,
            interestRateAdj,
            term,
            originalPrincipalBalance,
            outstandingPrincipalBalance
        );
    }

    // for current testnet
    function fulfillProof(address sender, bytes calldata proof, uint256[] calldata pubInputs, uint256 loan) external {
        if (!IHalo2Verifier(verifier).verifyProof(proof, pubInputs)) revert InvalidProof();
        CreditOracleConsumerBase(sender).rawFulfillCredit(pubInputs, loan);
        emit FulfillProof(sender, proof, pubInputs);
    }

    // for integrate with chainlink, proofAndPubInputs = abi.encode(proof,pubInputs off-chain);
    function fulfillProof(address sender, bytes calldata proofAndPubInputs) external {
        emit FulfillProof(sender, proofAndPubInputs);
    }

    function checkLog(
        Log calldata log,
        bytes memory
    ) external view returns (bool upkeepNeeded, bytes memory performData) {
        address to = address(uint160(uint256(log.topics[0])));
        (bytes memory proof, uint256[] memory pubInputs) = abi.decode(log.data, (bytes, uint256[]));
        if (!IHalo2Verifier(verifier).verifyProof(proof, pubInputs)) revert InvalidProof();
        performData = abi.encode(to, pubInputs);
        return (true, performData);
    }

    /**
     * @notice method that is actually executed by the keepers, via the registry.
     * The data returned by the checkUpkeep simulation will be passed into
     * this method to actually be executed.
     * @dev The input to this method should not be trusted, and the caller of the
     * method should not even be restricted to any single registry. Anyone should
     * be able call it, and the input should be validated, there is no guarantee
     * that the data passed in is the performData returned from checkUpkeep. This
     * could happen due to malicious keepers, racing keepers, or simply a state
     * change while the performUpkeep transaction is waiting for confirmation.
     * Always validate the data passed in.
     * @param performData is the data which was passed back from the checkData
     * simulation. If it is encoded, it can easily be decoded into other types by
     * calling `abi.decode`. This data should not be trusted, and should be
     * validated against the contract's current state.
     */
    function performUpkeep(bytes calldata performData) external {
        // need check condition later
        (address to, uint256 loan, uint256[] memory pubInputs) = abi.decode(performData, (address, uint256, uint256[]));
        CreditOracleConsumerBase(to).rawFulfillCredit(pubInputs, loan);
        emit PerformUpkeep(to, performData);
    }
}
