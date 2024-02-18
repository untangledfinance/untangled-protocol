// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// import {PausableUpgradeable} from '../../base/PauseableUpgradeable.sol';
import {IUntangledERC721} from '../../interfaces/IUntangledERC721.sol';
import {IMintedNormalTGE} from '../../interfaces/IMintedNormalTGE.sol';
// import {ISecuritizationPool} from '../../interfaces/ISecuritizationPool.sol';
// import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {UntangledMath} from '../../libraries/UntangledMath.sol';
// import {Registry} from '../../storage/Registry.sol';
// import {POOL_ADMIN, ORIGINATOR_ROLE, RATE_SCALING_FACTOR} from './types.sol';
// import {ISecuritizationPoolStorage} from "../../interfaces/ISecuritizationPoolStorage.sol";
// import {ISecuritizationPoolNAV} from '../../protocol/pool/ISecuritizationPoolNAV.sol';
// import {SecuritizationAccessControl} from './SecuritizationAccessControl.sol';
// import {ISecuritizationAccessControl} from "../../interfaces/ISecuritizationAccessControl.sol";
// import {RiskScore, LoanEntry} from './base/types.sol';
// import {SecuritizationPoolStorage} from './SecuritizationPoolStorage.sol';fcollectAssets
// import {ISecuritizationPoolExtension, SecuritizationPoolExtension} from './SecuritizationPoolExtension.sol';
import {DataTypes} from '../DataTypes.sol';
import {TransferHelper} from '../TransferHelper.sol';
import './PoolNAVLogic.sol';
/**
 * @title Untangled's SecuritizationPoolAsset contract
 * @notice Provides pool's asset related functions
 * @author Untangled Team
 */
library PoolAssetLogic {
    // using ConfigHelper for Registry;
    // using AddressUpgradeable for address;

    // function supportsInterface(
    //     bytes4 interfaceId
    // )
    //     public
    //     view
    //     virtual
    //     override(ERC165Upgradeable, SecuritizationAccessControl, SecuritizationPoolStorage)
    //     returns (bool)
    // {
    //     return
    //         super.supportsInterface(interfaceId) ||
    //         interfaceId == type(IERC721ReceiverUpgradeable).interfaceId ||
    //         interfaceId == type(ISecuritizationPool).interfaceId ||
    //         interfaceId == type(ISecuritizationPoolExtension).interfaceId ||
    //         interfaceId == type(ISecuritizationAccessControl).interfaceId ||
    //         interfaceId == type(ISecuritizationPoolStorage).interfaceId;
    // }
    event ExportNFTAsset(address tokenAddress, address toPoolAddress, uint256[] tokenIds);
    event WithdrawNFTAsset(address[] tokenAddresses, uint256[] tokenIds, address[] recipients);
    event UpdateOpeningBlockTimestamp(uint256 newTimestamp);
    event CollectNFTAsset(uint256[] tokenIds, uint256 expectedAssetsValue);
    event CollectERC20Asset(address token);
    event WithdrawERC20Asset(address[] tokenAddresses, address[] recipients, uint256[] amounts);
    event SetRiskScore(DataTypes.RiskScore[] riskscores);
    /** UTILITY FUNCTION */
    function _removeNFTAsset(
        DataTypes.NFTAsset[] storage _nftAssets,
        address tokenAddress,
        uint256 tokenId
    ) private returns (bool) {
        // NFTAsset[] storage _nftAssets = _getStorage().nftAssets;
        uint256 nftAssetsLength = _nftAssets.length;
        for (uint256 i = 0; i < nftAssetsLength; i = UntangledMath.uncheckedInc(i)) {
            if (_nftAssets[i].tokenAddress == tokenAddress && _nftAssets[i].tokenId == tokenId) {
                // Remove i element from nftAssets
                _removeNFTAssetIndex(_nftAssets, i);
                return true;
            }
        }

        return false;
    }

    function _removeNFTAssetIndex(DataTypes.NFTAsset[] storage _nftAssets, uint256 indexToRemove) private {
        _nftAssets[indexToRemove] = _nftAssets[_nftAssets.length - 1];

        // NFTAsset storage nft = _nftAssets[_nftAssets.length - 1];

        _nftAssets.pop();
    }

    function _pushTokenAssetAddress(
        mapping(address => bool) storage existsTokenAssetAddress,
        address[] storage tokenAssetAddresses,
        address tokenAddress
    ) private {
        if (!existsTokenAssetAddress[tokenAddress]) tokenAssetAddresses.push(tokenAddress);
        existsTokenAssetAddress[tokenAddress] = true;
    }

    // function onERC721Received(address, address, uint256 tokenId, bytes memory) external returns (bytes4) {
    //     address token = _msgSender();
    //     require(
    //         token == address(registry().getLoanAssetToken()),
    //         'SecuritizationPool: Must be token issued by Untangled'
    //     );
    //     NFTAsset[] storage _nftAssets = _getStorage().nftAssets;
    //     _nftAssets.push(NFTAsset({tokenAddress: token, tokenId: tokenId}));
    //     emit InsertNFTAsset(token, tokenId);

    //     return this.onERC721Received.selector;
    // }

    // TODO have to use modifier in main contract
    function setupRiskScores(
        DataTypes.Storage storage _poolStorage,
        uint32[] calldata _daysPastDues,
        uint32[] calldata _ratesAndDefaults,
        uint32[] calldata _periodsAndWriteOffs
    ) external {
        uint256 _daysPastDuesLength = _daysPastDues.length;
        require(
            _daysPastDuesLength * 6 == _ratesAndDefaults.length &&
                _daysPastDuesLength * 4 == _periodsAndWriteOffs.length,
            'SecuritizationPool: Riskscore params length is not equal'
        );

        delete _poolStorage.riskScores;

        for (uint256 i = 0; i < _daysPastDuesLength; i = UntangledMath.uncheckedInc(i)) {
            require(
                i == 0 || _daysPastDues[i] > _daysPastDues[i - 1],
                'SecuritizationPool: Risk scores must be sorted'
            );
            uint32 _interestRate = _ratesAndDefaults[i + _daysPastDuesLength * 2];
            uint32 _writeOffAfterGracePeriod = _periodsAndWriteOffs[i + _daysPastDuesLength * 2];
            uint32 _writeOffAfterCollectionPeriod = _periodsAndWriteOffs[i + _daysPastDuesLength * 3];
            _poolStorage.riskScores.push(
                DataTypes.RiskScore({
                    daysPastDue: _daysPastDues[i],
                    advanceRate: _ratesAndDefaults[i],
                    penaltyRate: _ratesAndDefaults[i + _daysPastDuesLength],
                    interestRate: _interestRate,
                    probabilityOfDefault: _ratesAndDefaults[i + _daysPastDuesLength * 3],
                    lossGivenDefault: _ratesAndDefaults[i + _daysPastDuesLength * 4],
                    discountRate: _ratesAndDefaults[i + _daysPastDuesLength * 5],
                    gracePeriod: _periodsAndWriteOffs[i],
                    collectionPeriod: _periodsAndWriteOffs[i + _daysPastDuesLength],
                    writeOffAfterGracePeriod: _writeOffAfterGracePeriod,
                    writeOffAfterCollectionPeriod: _periodsAndWriteOffs[i + _daysPastDuesLength * 3]
                })
            );
            PoolNAVLogic.file(
                _poolStorage,
                'writeOffGroup',
                _interestRate,
                _writeOffAfterGracePeriod,
                _periodsAndWriteOffs[i],
                _ratesAndDefaults[i + _daysPastDuesLength],
                i
            );
            PoolNAVLogic.file(
                _poolStorage,
                'writeOffGroup',
                _interestRate,
                _writeOffAfterCollectionPeriod,
                _periodsAndWriteOffs[i + _daysPastDuesLength],
                _ratesAndDefaults[i + _daysPastDuesLength],
                i
            );
        }

        // Set discount rate
        PoolNAVLogic.file(_poolStorage, 'discountRate', _poolStorage.riskScores[0].discountRate);

        emit SetRiskScore(_poolStorage.riskScores);
    }

    // TODO have to use modifier in main contract
    function exportAssets(
        DataTypes.NFTAsset[] storage _nftAssets,
        address tokenAddress,
        address toPoolAddress,
        uint256[] calldata tokenIds
    ) external {
        // registry().requirePoolAdminOrOwner(address(this), _msgSender());

        uint256 tokenIdsLength = tokenIds.length;
        for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
            require(_removeNFTAsset(_nftAssets, tokenAddress, tokenIds[i]), 'SecuritizationPool: Asset does not exist');
        }

        for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
            IUntangledERC721(tokenAddress).safeTransferFrom(address(this), toPoolAddress, tokenIds[i]);
        }

        emit ExportNFTAsset(tokenAddress, toPoolAddress, tokenIds);
    }

    // TODO have to use modifier in main contract
    function withdrawAssets(
        DataTypes.NFTAsset[] storage _nftAssets,
        address[] calldata tokenAddresses,
        uint256[] calldata tokenIds,
        address[] calldata recipients
    ) external {
        uint256 tokenIdsLength = tokenIds.length;
        require(tokenAddresses.length == tokenIdsLength, 'tokenAddresses length and tokenIds length are not equal');
        require(
            tokenAddresses.length == recipients.length,
            'tokenAddresses length and recipients length are not equal'
        );

        for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
            require(
                _removeNFTAsset(_nftAssets, tokenAddresses[i], tokenIds[i]),
                'SecuritizationPool: Asset does not exist'
            );
        }
        for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
            IUntangledERC721(tokenAddresses[i]).safeTransferFrom(address(this), recipients[i], tokenIds[i]);
        }

        emit WithdrawNFTAsset(tokenAddresses, tokenIds, recipients);
    }

    // TODO have to use modifier in main contract
    function collectAssets(
        DataTypes.Storage storage _poolStorage,
        uint256[] calldata tokenIds,
        DataTypes.LoanEntry[] calldata loanEntries
    ) external returns (uint256) {
        // registry().requireLoanKernel(_msgSender());
        uint256 tokenIdsLength = tokenIds.length;
        uint256 expectedAssetsValue = 0;
        for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
            expectedAssetsValue = expectedAssetsValue + PoolNAVLogic.addLoan(_poolStorage, tokenIds[i], loanEntries[i]);
        }

        // Storage storage $ = _getStorage();

        if (_poolStorage.firstAssetTimestamp == 0) {
            _poolStorage.firstAssetTimestamp = uint64(block.timestamp);
            _setUpOpeningBlockTimestamp(_poolStorage);
        }
        if (_poolStorage.openingBlockTimestamp == 0) {
            // If openingBlockTimestamp is not set
            _setOpeningBlockTimestamp(_poolStorage, uint64(block.timestamp));
        }

        emit CollectNFTAsset(tokenIds, expectedAssetsValue);
        return expectedAssetsValue;
    }

    // TODO have to use modifier in main contract
    function collectERC20Asset(DataTypes.Storage storage _poolStorgae, address tokenAddress) external {
        // registry().requireSecuritizationManager(_msgSender());

        _pushTokenAssetAddress(_poolStorgae.existsTokenAssetAddress, _poolStorgae.tokenAssetAddresses, tokenAddress);

        if (_poolStorgae.openingBlockTimestamp == 0) {
            // If openingBlockTimestamp is not set
            _setOpeningBlockTimestamp(_poolStorgae, uint64(block.timestamp));
        }

        emit CollectERC20Asset(tokenAddress);
    }
    // TODO have to use modifier in main contract
    function withdrawERC20Assets(
        mapping(address => bool) storage existsTokenAssetAddress,
        address[] calldata tokenAddresses,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external {
        // registry().requirePoolAdminOrOwner(address(this), _msgSender());

        uint256 tokenAddressesLength = tokenAddresses.length;
        require(tokenAddressesLength == recipients.length, 'tokenAddresses length and tokenIds length are not equal');
        require(tokenAddressesLength == amounts.length, 'tokenAddresses length and recipients length are not equal');

        // mapping(address => bool) storage existsTokenAssetAddress = _getStorage().existsTokenAssetAddress;
        for (uint256 i = 0; i < tokenAddressesLength; i = UntangledMath.uncheckedInc(i)) {
            require(existsTokenAssetAddress[tokenAddresses[i]], 'SecuritizationPool: note token asset does not exist');
            TransferHelper.safeTransfer(tokenAddresses[i], recipients[i], amounts[i]);
            // require(
            //     IERC20Upgradeable(tokenAddresses[i]).transfer(recipients[i], amounts[i]),
            //     'SecuritizationPool: Transfer failed'
            // );
        }

        emit WithdrawERC20Asset(tokenAddresses, recipients, amounts);
    }

    // function firstAssetTimestamp() public view returns (uint64) {
    //     return _getStorage().firstAssetTimestamp;
    // }

    // TODO have to use modifier in main contract
    function setUpOpeningBlockTimestamp(DataTypes.Storage storage _poolStorage) public {
        // require(_msgSender() == tgeAddress(), 'SecuritizationPool: Only tge address');
        _setUpOpeningBlockTimestamp(_poolStorage);
    }

    /// @dev Set the opening block timestamp
    function _setUpOpeningBlockTimestamp(DataTypes.Storage storage _poolStorage) private {
        address tgeAddress = _poolStorage.tgeAddress;
        if (tgeAddress == address(0)) return;
        uint64 _firstNoteTokenMintedTimestamp = uint64(IMintedNormalTGE(tgeAddress).firstNoteTokenMintedTimestamp());
        uint64 _firstAssetTimestamp = _poolStorage.firstAssetTimestamp;
        if (_firstNoteTokenMintedTimestamp > 0 && _firstAssetTimestamp > 0) {
            // Pick the later
            if (_firstAssetTimestamp > _firstNoteTokenMintedTimestamp) {
                _setOpeningBlockTimestamp(_poolStorage, _firstAssetTimestamp);
            } else {
                _setOpeningBlockTimestamp(_poolStorage, _firstNoteTokenMintedTimestamp);
            }
        }
    }

    function _setOpeningBlockTimestamp(DataTypes.Storage storage _poolStorage, uint64 _openingBlockTimestamp) internal {
        _poolStorage.openingBlockTimestamp = _openingBlockTimestamp;
        emit UpdateOpeningBlockTimestamp(_openingBlockTimestamp);
    }

    // function riskScores(uint256 idx) public view virtual override returns (RiskScore memory) {
    //     return _getStorage().riskScores[idx];
    // }

    // function nftAssets(uint256 idx) public view virtual override returns (NFTAsset memory) {
    //     return _getStorage().nftAssets[idx];
    // }

    // function tokenAssetAddresses(uint256 idx) public view virtual override returns (address) {
    //     return _getStorage().tokenAssetAddresses[idx];
    // }

    // function pause() public virtual override {
    //     registry().requirePoolAdminOrOwner(address(this), _msgSender());
    //     _pause();
    // }

    // function unpause() public virtual override {
    //     registry().requirePoolAdminOrOwner(address(this), _msgSender());
    //     _unpause();
    // }
}
