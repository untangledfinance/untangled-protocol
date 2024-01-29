// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {ILoanAssetToken} from './ILoanAssetToken.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {LATValidator} from './LATValidator.sol';
import {Registry} from '../../storage/Registry.sol';
import {LoanAssetInfo, VALIDATOR_ROLE, VALIDATOR_ADMIN_ROLE} from '../ERC721/types.sol';
import {Configuration} from '../../libraries/Configuration.sol';
import {UntangledMath} from '../../libraries/UntangledMath.sol';

/**
 * LoanAssetToken: The representative for ownership of a Loan
 */
contract LoanAssetToken is ILoanAssetToken, LATValidator {
    using ConfigHelper for Registry;

    /** CONSTRUCTOR */
    function initialize(
        Registry _registry,
        string memory name,
        string memory symbol,
        string memory baseTokenURI
    ) public initializer {
        __UntangledERC721__init(name, symbol, baseTokenURI);
        __LATValidator_init();

        registry = _registry;

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        require(
            address(registry.getSecuritizationManager()) != address(0x0),
            'SECURITIZATION_MANAGER is zero address.'
        );

        _setupRole(VALIDATOR_ADMIN_ROLE, address(registry.getSecuritizationManager()));
        _setRoleAdmin(VALIDATOR_ROLE, VALIDATOR_ADMIN_ROLE);

        require(address(registry.getLoanKernel()) != address(0x0), 'LOAN_KERNEL is zero address.');

        _setupRole(MINTER_ROLE, address(registry.getLoanKernel()));
        _revokeRole(MINTER_ROLE, _msgSender());
    }

    function safeMint(
        address creditor,
        LoanAssetInfo calldata latInfo
    ) public virtual override onlyRole(MINTER_ROLE) validateCreditor(creditor, latInfo) {
        for (uint i = 0; i < latInfo.tokenIds.length; i = UntangledMath.uncheckedInc(i)) {
            _safeMint(creditor, latInfo.tokenIds[i]);
        }
    }

    function isValidator(address sender) public view virtual override returns (bool) {
        return hasRole(VALIDATOR_ROLE, sender);
    }

    uint256[50] private __gap;
}
