// // SPDX-License-Identifier: AGPL-3.0-only
// pragma solidity 0.8.19;

// import {ERC165Upgradeable} from '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol';
// import {ContextUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol';
// import {RegistryInjection} from './RegistryInjection.sol';

// import {OWNER_ROLE, ORIGINATOR_ROLE} from './types.sol';

// import {ISecuritizationAccessControl} from "../../interfaces/ISecuritizationAccessControl.sol";
// import {ISecuritizationPoolStorage} from "../../interfaces/ISecuritizationPoolStorage.sol";
// import {ISecuritizationPoolExtension, SecuritizationPoolExtension} from './SecuritizationPoolExtension.sol';

// contract SecuritizationAccessControl is
//     ERC165Upgradeable,
//     RegistryInjection,
//     ContextUpgradeable,
//     ISecuritizationAccessControl,
//     SecuritizationPoolExtension
// {
//     // keccak256(abi.encode(uint256(keccak256("untangled.storage.SecuritizationAccessControl")) - 1)) & ~bytes32(uint256(0xff))
//     bytes32 private constant SecuritizationAccessControlStorageLocation =
//         0xb38e00afe21f8bf8961a30ad85d453b5f474f19414b8973dee80c89fb0d97b00;

//     /// @custom:storage-location erc7201:untangled.storage.SecuritizationAccessControl
//     struct SecuritizationAccessControlStorage {
//         mapping(address => mapping(bytes32 => bool)) roles;
//     }

//     function _getSecuritizationAccessControl() private pure returns (SecuritizationAccessControlStorage storage $) {
//         assembly {
//             $.slot := SecuritizationAccessControlStorageLocation
//         }
//     }

//     modifier onlyOwner() {
//         address account = _msgSender();

//         require(isOwner(account), 'AccessControl: caller is not an owner');
//         _;
//     }

//     modifier onlyRole(bytes32 role) {
//         require(hasRole(role, _msgSender()), 'AccessControl: caller is not an originator');
//         _;
//     }

//     function installExtension(bytes memory params) public virtual override onlyCallInTargetPool {
//         __SecuritizationAccessControl_init_unchained(_msgSender());
//     }

//     function __SecuritizationAccessControl_init_unchained(address _owner) internal {
//         _setRole(OWNER_ROLE, _owner);
//     }

//     function hasRole(bytes32 role, address account) public view override returns (bool) {
//         SecuritizationAccessControlStorage storage $ = _getSecuritizationAccessControl();
//         return $.roles[account][role];
//     }

//     function isOwner(address account) public view override returns (bool) {
//         return hasRole(OWNER_ROLE, account);
//     }

//     function grantRole(bytes32 role, address account) public virtual override onlyOwner {
//         SecuritizationAccessControlStorage storage $ = _getSecuritizationAccessControl();
//         $.roles[account][role] = true;
//         emit RoleGranted(role, account, _msgSender());
//     }

//     function revokeRole(bytes32 role, address account) public virtual override onlyOwner {
//         SecuritizationAccessControlStorage storage $ = _getSecuritizationAccessControl();
//         $.roles[account][role] = false;
//         emit RoleRevoked(role, account, _msgSender());
//     }

//     function _setRole(bytes32 role, address account) internal virtual {
//         SecuritizationAccessControlStorage storage $ = _getSecuritizationAccessControl();
//         $.roles[account][role] = true;
//         emit RoleRevoked(role, account, _msgSender());
//     }

//     function _revokeRole(bytes32 role, address account) internal virtual {
//         SecuritizationAccessControlStorage storage $ = _getSecuritizationAccessControl();
//         $.roles[account][role] = false;
//         emit RoleRevoked(role, account, _msgSender());
//     }

//     function renounceRole(bytes32 role, address account) public virtual override {
//         require(account == _msgSender(), 'AccessControl: can only renounce roles for self');
//         _revokeRole(role, account);
//     }

//     function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
//         return
//             super.supportsInterface(interfaceId) ||
//             type(ISecuritizationAccessControl).interfaceId == interfaceId ||
//             type(ISecuritizationPoolExtension).interfaceId == interfaceId;
//     }

//     function getFunctionSignatures() public view virtual override returns (bytes4[] memory) {
//         bytes4[] memory _functionSignatures = new bytes4[](6);

//         _functionSignatures[0] = this.hasRole.selector;
//         _functionSignatures[1] = this.isOwner.selector;
//         _functionSignatures[2] = this.renounceRole.selector;
//         _functionSignatures[3] = this.grantRole.selector;
//         _functionSignatures[4] = this.revokeRole.selector;
//         _functionSignatures[5] = this.supportsInterface.selector;

//         return _functionSignatures;
//     }
// }
