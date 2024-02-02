// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {UntangledBase} from '../../base/UntangledBase.sol';
import {Registry} from '../../storage/Registry.sol';

abstract contract ILoanRepaymentRouter is UntangledBase {
    Registry public registry;

    function initialize(Registry _registry) public virtual;

    event AssetRepay(
        bytes32 indexed agreementId,
        address indexed payer,
        address indexed pool,
        uint256 amount,
        uint256 outstandingAmount,
        address token
    );

    /// @notice allows batch repayment of multiple loans by iterating over the given agreement IDs and amounts
    /// @dev calls _assertRepaymentRequest and _doRepay for each repayment, and emits the LogRepayments event to indicate the successful batch repayment
    function repayInBatch(
        bytes32[] calldata agreementIds,
        uint256[] calldata amounts,
        address tokenAddress
    ) external virtual returns (bool);

    uint256[49] private __gap;
}
