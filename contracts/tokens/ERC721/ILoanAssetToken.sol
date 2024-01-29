// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import '../../interfaces/IUntangledERC721.sol';
import './types.sol';
import '../../libraries/Configuration.sol';

abstract contract ILoanAssetToken is IUntangledERC721 {

    function safeMint(address creditor, LoanAssetInfo calldata latInfo) external virtual;

    uint256[50] private __gap;
}
