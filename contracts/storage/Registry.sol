// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {AccessControlUpgradeable} from '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import {UntangledBase} from '../base/UntangledBase.sol';
import {Configuration} from '../libraries/Configuration.sol';

/**
 * @title Registry
 * @notice This contract stores mappings of useful "protocol config state", giving a central place
 *  for all other contracts to access it. These config vars
 *  are enumerated in the `Configuration` library, and can only be changed by admins of the protocol.
 * @author Untangled Team
 */
contract Registry is UntangledBase {
    mapping(uint8 => address) public contractAddresses;

    event AddressUpdated(address owner, uint8 index, address oldValue, address newValue);

    function initialize() public initializer {
        __UntangledBase__init(_msgSender());
    }

    function _setAddress(uint8 addressIndex, address newAddress) private {
        emit AddressUpdated(_msgSender(), addressIndex, contractAddresses[addressIndex], newAddress);
        contractAddresses[addressIndex] = newAddress;
    }

    function getAddress(uint8 index) public view returns (address) {
        return contractAddresses[index];
    }

    function setSecuritizationManager(address newAddress) public onlyAdmin whenNotPaused {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.SECURITIZATION_MANAGER), newAddress);
    }

    function setSecuritizationPool(address newAddress) public onlyAdmin whenNotPaused {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.SECURITIZATION_POOL), newAddress);
    }

    function setNoteTokenFactory(address newAddress) public onlyAdmin whenNotPaused {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.NOTE_TOKEN_FACTORY), newAddress);
    }

    function setTokenGenerationEventFactory(address newAddress) public onlyAdmin whenNotPaused {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.TOKEN_GENERATION_EVENT_FACTORY), newAddress);
    }

    function setDistributionAssessor(address newAddress) public onlyAdmin whenNotPaused {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.DISTRIBUTION_ASSESSOR), newAddress);
    }

    function setLoanAssetToken(address newAddress) public onlyAdmin whenNotPaused {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.LOAN_ASSET_TOKEN), newAddress);
    }

    function setSecuritizationPoolValueService(address newAddress) public onlyAdmin whenNotPaused {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.SECURITIZATION_POOL_VALUE_SERVICE), newAddress);
    }

    function setLoanRepaymentRouter(address newAddress) public onlyAdmin whenNotPaused {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.LOAN_REPAYMENT_ROUTER), newAddress);
    }

    function setLoanKernel(address newAddress) public onlyAdmin whenNotPaused {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.LOAN_KERNEL), newAddress);
    }

    function setGo(address newAddress) public onlyAdmin whenNotPaused {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.GO), newAddress);
    }

    function setNoteTokenVault(address newAddress) public onlyAdmin whenNotPaused {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.NOTE_TOKEN_VAULT), newAddress);
    }

    uint256[49] private __gap;
}
