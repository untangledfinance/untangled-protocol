// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// import {ERC165CheckerUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol';
// import {StringsUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol';
// import {ERC165Upgradeable} from '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol';
// import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {Registry} from '../../storage/Registry.sol';
import {OWNER_ROLE} from './types.sol';
// import {RegistryInjection} from './RegistryInjection.sol';
// import {ISecuritizationPoolStorage} from "../../interfaces/ISecuritizationPoolStorage.sol";
// import {AddressUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol';
// import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {ISecuritizationPoolExtension} from './SecuritizationPoolExtension.sol';
// import {StorageSlot} from '@openzeppelin/contracts/utils/StorageSlot.sol';
// import {IPool} from '../../interfaces/IPool.sol';
import {PoolStorage} from './PoolStorage.sol';
import {DataTypes} from '../../libraries/DataTypes.sol';
import {UntangledBase} from "../../base/UntangledBase.sol";
import {PoolNAVLogic} from '../../libraries/logic/PoolNAVLogic.sol';
import {PoolAssetLogic} from '../../libraries/logic/PoolAssetLogic.sol';
import {TGELogic} from '../../libraries/logic/TGELogic.sol';
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
contract Pool is PoolStorage, UntangledBase{
    // using AddressUpgradeable for address;
    // using ERC165CheckerUpgradeable for address;
    // event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    Registry public registry;
    // mapping(address => mapping(bytes32 => bool)) privateRoles;

    // modifier onlyCallInOriginal() {
    //     require(original == address(this), 'Only call in original contract');
    //     _;
    // }

    // constructor() {
    //     original = address(this); // default original
    //     _setPrivateRole(OWNER_ROLE, msg.sender);
    // }

    // function hasPrivateRole(bytes32 role, address account) public view returns (bool) {
    //     return privateRoles[account][role];
    // }

    // function _setPrivateRole(bytes32 role, address account) internal virtual {
    //     privateRoles[account][role] = true;
    //     emit RoleGranted(role, account, msg.sender);
    // }

    /** CONSTRUCTOR */
    function initialize(address _registryAddress) public initializer {
        __UntangledBase__init(_msgSender());
        require(_registryAddress != address(0), 'Registry address cannot be empty');
        registry = Registry(_registryAddress);
    }
    function getNFTAssetsLength() external view returns (uint256){
        return _poolStorage.nftAssets.length;
    }

    /// @notice A view function that returns an array of token asset addresses
    function getTokenAssetAddresses() external view returns (address[] memory){
        return _poolStorage.tokenAssetAddresses;
    }

    /// @notice A view function that returns the length of the token asset addresses array
    function getTokenAssetAddressesLength() external view returns (uint256){
        return _poolStorage.tokenAssetAddresses.length;
    }

    /// @notice Riks scores length
    /// @return the length of the risk scores array
    function getRiskScoresLength() external view returns (uint256){
        return _poolStorage.riskScores.length;
    }

    function riskScores(uint256 index) external view returns (DataTypes.RiskScore memory){
        return _poolStorage.riskScores[index];
    }
    function nftAssets(uint256 idx) external view returns (DataTypes.NFTAsset memory){
        return _poolStorage.nftAssets[idx];
    }

    function tokenAssetAddresses(uint256 idx) external view returns (address){
        return _poolStorage.tokenAssetAddresses[idx];
    }
    /// @notice sets up the risk scores for the contract for pool
    function setupRiskScores(
        uint32[] calldata _daysPastDues,
        uint32[] calldata _ratesAndDefaults,
        uint32[] calldata _periodsAndWriteOffs
    ) external{

    }

    /// @notice exports NFT assets to another pool address
    function exportAssets(address tokenAddress, address toPoolAddress, uint256[] calldata tokenIds) external{}

    /// @notice withdraws NFT assets from the contract and transfers them to recipients
    function withdrawAssets(
        address[] calldata tokenAddresses,
        uint256[] calldata tokenIds,
        address[] calldata recipients
    ) external{}

    /// @notice collects NFT assets from a specified address
    function collectAssets(uint256[] calldata tokenIds, DataTypes.LoanEntry[] calldata loanEntries) external returns (uint256){}

    /// @notice collects ERC20 assets from specified senders
    function collectERC20Asset(address tokenAddresss) external{}

    /// @notice withdraws ERC20 assets from the contract and transfers them to recipients\
    function withdrawERC20Assets(
        address[] calldata tokenAddresses,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external{}


    /// @dev Trigger set up opening block timestamp
    function setUpOpeningBlockTimestamp() external{}

    // function pause() external{}

    // function unpause() external{}    
    
    
}
