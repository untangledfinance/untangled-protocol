// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {AddressUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol';
import {AccessControlUpgradeable} from '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import {ECDSAUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol';

contract AAWallet is AccessControlUpgradeable {
    using ECDSAUpgradeable for bytes32;

    // bytes4(keccak256("isValidSignature(bytes32,bytes)")
    bytes4 internal constant MAGICVALUE = 0x1626ba7e;

    bytes32 public constant VALIDATOR_ROLE = keccak256('VALIDATOR_ROLE');

    function initialize() public initializer {
        __AccessControl_init_unchained();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /**
     * @dev Should return whether the signature provided is valid for the provided hash
     * @param _hash      Hash of the data to be signed
     * @param _signature Signature byte array associated with _hash
     *
     * MUST return the bytes4 magic value 0x1626ba7e when function passes.
     * MUST NOT modify state (using STATICCALL for solc < 0.5, view modifier for solc > 0.5)
     * MUST allow external calls
     */
    function isValidSignature(bytes32 _hash, bytes memory _signature) public view returns (bytes4 magicValue) {
        // Validate signatures
        address signer = _hash.recover(_signature);
        if (hasRole(VALIDATOR_ROLE, signer)) {
            return 0x1626ba7e;
        } else {
            return 0xffffffff;
        }
    }

    function execute(address target, bytes memory data) external returns (bytes memory) {
        return AddressUpgradeable.functionCall(target, data);
    }
}
