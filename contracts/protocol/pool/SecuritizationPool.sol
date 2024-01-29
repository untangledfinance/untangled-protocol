// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {ERC165CheckerUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol';
import {StringsUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol';
import {ERC165Upgradeable} from '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {Registry} from '../../storage/Registry.sol';
import {OWNER_ROLE} from './types.sol';
import {RegistryInjection} from './RegistryInjection.sol';
import {ISecuritizationPoolStorage} from './ISecuritizationPoolStorage.sol';
import {AddressUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {ISecuritizationPoolExtension} from './SecuritizationPoolExtension.sol';
import {StorageSlot} from '@openzeppelin/contracts/utils/StorageSlot.sol';

/**
 * @title Untangled's SecuritizationPool contract
 * @notice Main entry point for senior LPs (a.k.a. capital providers)
 *  Automatically invests across borrower pools using an adjustable strategy.
 * @author Untangled Team
 */
// is
// RegistryInjection,
// SecuritizationAccessControl,
// SecuritizationPoolStorage,
// SecuritizationTGE,
// SecuritizationPoolAsset,
// SecuritizationPoolNAV
contract SecuritizationPool is Initializable, RegistryInjection, ERC165Upgradeable {
    using ConfigHelper for Registry;
    using AddressUpgradeable for address;
    using ERC165CheckerUpgradeable for address;

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    address public original;
    address[] public extensions;
    mapping(bytes4 => address) public delegates;
    mapping(address => bytes4[]) public extensionSignatures;
    mapping(address => mapping(bytes32 => bool)) privateRoles;

    function extensionsLength() public view returns (uint256) {
        return extensions.length;
    }

    modifier onlyCallInOriginal() {
        require(original == address(this), 'Only call in original contract');
        _;
    }

    constructor() {
        original = address(this); // default original
        _setPrivateRole(OWNER_ROLE, msg.sender);
    }

    function hasPrivateRole(bytes32 role, address account) public view returns (bool) {
        return privateRoles[account][role];
    }

    function _setPrivateRole(bytes32 role, address account) internal virtual {
        privateRoles[account][role] = true;
        emit RoleGranted(role, account, msg.sender);
    }

    function registerExtension(address ext) public onlyCallInOriginal {
        _registerExtension(ext);
    }

    function _registerExtension(address ext) internal {
        extensions.push(ext);

        bytes4[] memory signatures = ISecuritizationPoolExtension(ext).getFunctionSignatures();
        for (uint i = 0; i < signatures.length; i++) {
            delegates[signatures[i]] = ext;
        }

        extensionSignatures[ext] = signatures;
    }

    function _installExtension(address ext, bytes memory data) internal {
        // function installExtension(bytes)
        ext.functionDelegateCall(abi.encodeWithSelector(0x326cd970, data));
    }

    // bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    /**
     * @dev Returns the current implementation address.
     */
    function _getImplementation() internal view returns (address) {
        // EIP 1967
        return StorageSlot.getAddressSlot(0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc).value;
    }

    /** CONSTRUCTOR */
    function initialize(Registry registry_, bytes memory params) public initializer {
        __ERC165_init_unchained();

        address poolImpl = address(_getImplementation());
        require(poolImpl != address(0), 'SecuritizationPool: No pool implementation');
        original = poolImpl;

        _setRegistry(registry_);

        uint256 exLength = SecuritizationPool(payable(original)).extensionsLength();

        for (uint i = 0; i < exLength; ++i) {
            address ext = SecuritizationPool(payable(original)).extensions(i);
            _installExtension(ext, params);
        }
    }

    fallback() external payable {
        address delegate = SecuritizationPool(payable(original)).delegates(msg.sig);

        require(
            delegate != address(0),
            string(
                abi.encodePacked(
                    'Can not delegate call to ',
                    StringsUpgradeable.toHexString(delegate),
                    ' with method ',
                    StringsUpgradeable.toHexString(uint32(msg.sig), 32)
                )
            )
        );

        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr, 0, calldatasize())
            let result := delegatecall(gas(), delegate, ptr, calldatasize(), 0, 0)
            let size := returndatasize()
            returndatacopy(ptr, 0, size)
            switch result
            case 0 {
                revert(ptr, size)
            }
            default {
                return(ptr, size)
            }
        }
    }

    receive() external payable {}

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        uint256 length = SecuritizationPool(payable(original)).extensionsLength();

        for (uint i = 0; i < length; ++i) {
            if (SecuritizationPool(payable(original)).extensions(i).supportsInterface(interfaceId)) {
                return true;
            }
        }

        return false;
    }
}
