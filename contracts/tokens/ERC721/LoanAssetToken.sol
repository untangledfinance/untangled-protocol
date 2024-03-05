// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {UntangledERC721} from './UntangledERC721.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {LATValidator} from './LATValidator.sol';
import {Registry} from '../../storage/Registry.sol';
import {DataTypes, VALIDATOR_ROLE} from '../../libraries/DataTypes.sol';
import {UntangledMath} from '../../libraries/UntangledMath.sol';
import {IAccessControlUpgradeable} from '@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol';

/**
 * LoanAssetToken: The representative for ownership of a Loan
 */
contract LoanAssetToken is UntangledERC721, LATValidator {
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

        require(address(registry.getLoanKernel()) != address(0x0), 'LOAN_KERNEL is zero address.');

        _setupRole(MINTER_ROLE, address(registry.getLoanKernel()));
        _revokeRole(MINTER_ROLE, _msgSender());
    }

    function safeMint(
        address creditor,
        DataTypes.LoanAssetInfo calldata latInfo
    ) public onlyRole(MINTER_ROLE) validateCreditor(creditor, latInfo) {
        for (uint i = 0; i < latInfo.tokenIds.length; i = UntangledMath.uncheckedInc(i)) {
            _safeMint(creditor, latInfo.tokenIds[i]);
        }
    }

    function isValidator(address pool, address sender) public view virtual override returns (bool) {
        return IAccessControlUpgradeable(pool).hasRole(VALIDATOR_ROLE, sender);
    }
}
