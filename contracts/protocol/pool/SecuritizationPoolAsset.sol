// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {AccessControlEnumerableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol';
import {ERC165Upgradeable} from '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol';
import {IERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol';
import {ERC20BurnableUpgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
import {IERC721ReceiverUpgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC721ReceiverUpgradeable.sol';
import {IAccessControlUpgradeable} from '@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol';
import {AddressUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol';
import {ReentrancyGuardUpgradeable} from '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import {PausableUpgradeable} from '../../base/PauseableUpgradeable.sol';
import {IUntangledERC721} from '../../interfaces/IUntangledERC721.sol';
import {INoteToken} from '../../interfaces/INoteToken.sol';
import {ICrowdSale} from '../note-sale/crowdsale/ICrowdSale.sol';

import {ISecuritizationPool} from './ISecuritizationPool.sol';
import {ISecuritizationPoolValueService} from './ISecuritizationPoolValueService.sol';

import {MintedIncreasingInterestTGE} from '../note-sale/MintedIncreasingInterestTGE.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {Configuration} from '../../libraries/Configuration.sol';
import {UntangledMath} from '../../libraries/UntangledMath.sol';
import {Registry} from '../../storage/Registry.sol';
import {FinalizableCrowdsale} from './../note-sale/crowdsale/FinalizableCrowdsale.sol';
import {POOL_ADMIN, ORIGINATOR_ROLE, RATE_SCALING_FACTOR} from './types.sol';

import {ISecuritizationPoolStorage} from './ISecuritizationPoolStorage.sol';
import {ISecuritizationLockDistribution} from './ISecuritizationLockDistribution.sol';
import {SecuritizationLockDistribution} from './SecuritizationLockDistribution.sol';
import {SecuritizationTGE} from './SecuritizationTGE.sol';
import {ISecuritizationTGE} from './ISecuritizationTGE.sol';
import {RegistryInjection} from './RegistryInjection.sol';

import {SecuritizationAccessControl} from './SecuritizationAccessControl.sol';
import {ISecuritizationAccessControl} from './ISecuritizationAccessControl.sol';

import {RiskScore} from './base/types.sol';

import {SecuritizationPoolStorage} from './SecuritizationPoolStorage.sol';
import {ISecuritizationPoolExtension, SecuritizationPoolExtension} from './SecuritizationPoolExtension.sol';
import {IPoolNAV} from './IPoolNAV.sol';
import {IPoolNAVFactory} from './IPoolNAVFactory.sol';

/**
 * @title Untangled's SecuritizationPool contract
 * @notice Main entry point for senior LPs (a.k.a. capital providers)
 *  Automatically invests across borrower pools using an adjustable strategy.
 * @author Untangled Team
 */
contract SecuritizationPoolAsset is
    ERC165Upgradeable,
    RegistryInjection,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    IERC721ReceiverUpgradeable,
    ISecuritizationPool,
    SecuritizationPoolStorage,
    SecuritizationAccessControl
{
    using ConfigHelper for Registry;
    using AddressUpgradeable for address;

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC165Upgradeable, SecuritizationAccessControl, SecuritizationPoolStorage)
        returns (bool)
    {
        return
            super.supportsInterface(interfaceId) ||
            interfaceId == type(IERC721ReceiverUpgradeable).interfaceId ||
            interfaceId == type(ISecuritizationPool).interfaceId ||
            interfaceId == type(ISecuritizationPoolExtension).interfaceId ||
            interfaceId == type(ISecuritizationAccessControl).interfaceId ||
            interfaceId == type(ISecuritizationPoolStorage).interfaceId;
    }

    function installExtension(
        bytes memory params
    ) public virtual override(SecuritizationAccessControl, SecuritizationPoolStorage) onlyCallInTargetPool {
        __SecuritizationPoolAsset_init_unchained(abi.decode(params, (NewPoolParams)));
    }

    function __SecuritizationPoolAsset_init_unchained(NewPoolParams memory newPoolParams) internal {
        _getStorage().validatorRequired = newPoolParams.validatorRequired;

        require(
            IERC20Upgradeable(newPoolParams.currency).approve(pot(), type(uint256).max),
            'SecuritizationPool: Currency approval failed'
        );
        registry().getLoanAssetToken().setApprovalForAll(address(registry().getLoanKernel()), true);
    }

    /** GETTER */
    function getNFTAssetsLength() public view override returns (uint256) {
        return _getStorage().nftAssets.length;
    }

    function getTokenAssetAddresses() public view override returns (address[] memory) {
        return _getStorage().tokenAssetAddresses;
    }

    function getTokenAssetAddressesLength() public view override returns (uint256) {
        return _getStorage().tokenAssetAddresses.length;
    }

    function getRiskScoresLength() public view override returns (uint256) {
        return _getStorage().riskScores.length;
    }

    /** UTILITY FUNCTION */
    function _removeNFTAsset(address tokenAddress, uint256 tokenId) private returns (bool) {
        NFTAsset[] storage _nftAssets = _getStorage().nftAssets;
        uint256 nftAssetsLength = _nftAssets.length;
        for (uint256 i = 0; i < nftAssetsLength; i = UntangledMath.uncheckedInc(i)) {
            if (_nftAssets[i].tokenAddress == tokenAddress && _nftAssets[i].tokenId == tokenId) {
                // Remove i element from nftAssets
                _removeNFTAssetIndex(i);
                return true;
            }
        }

        return false;
    }

    function _removeNFTAssetIndex(uint256 indexToRemove) private {
        NFTAsset[] storage _nftAssets = _getStorage().nftAssets;

        _nftAssets[indexToRemove] = _nftAssets[_nftAssets.length - 1];

        NFTAsset storage nft = _nftAssets[_nftAssets.length - 1];
        emit RemoveNFTAsset(nft.tokenAddress, nft.tokenId);
        _nftAssets.pop();
    }

    function _pushTokenAssetAddress(address tokenAddress) private {
        Storage storage $ = _getStorage();

        if (!$.existsTokenAssetAddress[tokenAddress]) $.tokenAssetAddresses.push(tokenAddress);
        $.existsTokenAssetAddress[tokenAddress] = true;
        emit AddTokenAssetAddress(tokenAddress);
    }

    function onERC721Received(address, address, uint256 tokenId, bytes memory) external returns (bytes4) {
        address token = _msgSender();
        require(
            token == address(registry().getLoanAssetToken()),
            'SecuritizationPool: Must be token issued by Untangled'
        );
        NFTAsset[] storage _nftAssets = _getStorage().nftAssets;
        _nftAssets.push(NFTAsset({tokenAddress: token, tokenId: tokenId}));
        emit InsertNFTAsset(token, tokenId);

        return this.onERC721Received.selector;
    }

    /// @inheritdoc ISecuritizationPool
    function setupRiskScores(
        uint32[] calldata _daysPastDues,
        uint32[] calldata _ratesAndDefaults,
        uint32[] calldata _periodsAndWriteOffs
    ) external override whenNotPaused notClosingStage {
        registry().requirePoolAdmin(_msgSender());

        uint256 _daysPastDuesLength = _daysPastDues.length;
        require(
            _daysPastDuesLength * 6 == _ratesAndDefaults.length &&
                _daysPastDuesLength * 4 == _periodsAndWriteOffs.length,
            'SecuritizationPool: Riskscore params length is not equal'
        );

        Storage storage $ = _getStorage();
        delete $.riskScores;

        for (uint256 i = 0; i < _daysPastDuesLength; i = UntangledMath.uncheckedInc(i)) {
            require(
                i == 0 || _daysPastDues[i] > _daysPastDues[i - 1],
                'SecuritizationPool: Risk scores must be sorted'
            );
            uint32 _interestRate = _ratesAndDefaults[i + _daysPastDuesLength * 2];
            uint32 _writeOffAfterGracePeriod = _periodsAndWriteOffs[i + _daysPastDuesLength * 2];
            uint32 _writeOffAfterCollectionPeriod = _periodsAndWriteOffs[i + _daysPastDuesLength * 3];
            $.riskScores.push(
                RiskScore({
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
            IPoolNAV(poolNAV()).file(
                'writeOffGroup',
                _interestRate,
                _writeOffAfterGracePeriod,
                _periodsAndWriteOffs[i],
                _ratesAndDefaults[i + _daysPastDuesLength],
                i
            );
            IPoolNAV(poolNAV()).file(
                'writeOffGroup',
                _interestRate,
                _writeOffAfterCollectionPeriod,
                _periodsAndWriteOffs[i + _daysPastDuesLength],
                _ratesAndDefaults[i + _daysPastDuesLength],
                i
            );
        }

        // Set discount rate
        IPoolNAV(poolNAV()).file('discountRate', $.riskScores[0].discountRate);
    }

    /// @inheritdoc ISecuritizationPool
    function exportAssets(
        address tokenAddress,
        address toPoolAddress,
        uint256[] calldata tokenIds
    ) external override whenNotPaused nonReentrant notClosingStage {
        registry().requirePoolAdminOrOwner(address(this), _msgSender());

        uint256 tokenIdsLength = tokenIds.length;
        for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
            require(_removeNFTAsset(tokenAddress, tokenIds[i]), 'SecuritizationPool: Asset does not exist');
        }

        for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
            IUntangledERC721(tokenAddress).safeTransferFrom(address(this), toPoolAddress, tokenIds[i]);
        }
    }

    /// @inheritdoc ISecuritizationPool
    function withdrawAssets(
        address[] calldata tokenAddresses,
        uint256[] calldata tokenIds,
        address[] calldata recipients
    ) external override whenNotPaused nonReentrant onlyOwner {
        uint256 tokenIdsLength = tokenIds.length;
        require(tokenAddresses.length == tokenIdsLength, 'tokenAddresses length and tokenIds length are not equal');
        require(
            tokenAddresses.length == recipients.length,
            'tokenAddresses length and recipients length are not equal'
        );

        for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
            require(_removeNFTAsset(tokenAddresses[i], tokenIds[i]), 'SecuritizationPool: Asset does not exist');
        }
        for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
            IUntangledERC721(tokenAddresses[i]).safeTransferFrom(address(this), recipients[i], tokenIds[i]);
        }
    }

    /// @inheritdoc ISecuritizationPool
    function collectAssets(uint256[] calldata tokenIds) external override whenNotPaused returns (uint256) {
        registry().requireLoanKernel(_msgSender());
        uint256 tokenIdsLength = tokenIds.length;
        uint256 expectedAssetsValue = 0;
        for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
            IPoolNAV(poolNAV()).addLoan(tokenIds[i]);
            expectedAssetsValue = expectedAssetsValue + IPoolNAV(poolNAV()).debt(tokenIds[i]);
        }

        Storage storage $ = _getStorage();

        if (firstAssetTimestamp() == 0) {
            $.firstAssetTimestamp = uint64(block.timestamp);
            _setUpOpeningBlockTimestamp();
        }
        if (openingBlockTimestamp() == 0) {
            // If openingBlockTimestamp is not set
            _setOpeningBlockTimestamp(openingBlockTimestamp());
        }

        emit CollectAsset(expectedAssetsValue);
        return expectedAssetsValue;
    }

    // function amountOwedToOriginator() public view returns (uint256) {
    //     return _getStorage().amountOwedToOriginator;
    // }

    /// @inheritdoc ISecuritizationPool
    function collectERC20Assets(
        address[] calldata tokenAddresses,
        address[] calldata senders,
        uint256[] calldata amounts
    ) external override whenNotPaused notClosingStage onlyRole(ORIGINATOR_ROLE) {
        uint256 tokenAddressesLength = tokenAddresses.length;
        require(
            tokenAddressesLength == senders.length && senders.length == amounts.length,
            'SecuritizationPool: Params length are not equal'
        );

        // check
        for (uint256 i = 0; i < tokenAddressesLength; i = UntangledMath.uncheckedInc(i)) {
            require(
                registry().getNoteTokenFactory().isExistingTokens(tokenAddresses[i]),
                'SecuritizationPool: unknown-token-address'
            );
        }

        for (uint256 i = 0; i < tokenAddressesLength; i = UntangledMath.uncheckedInc(i)) {
            _pushTokenAssetAddress(tokenAddresses[i]);
        }

        for (uint256 i = 0; i < tokenAddressesLength; i = UntangledMath.uncheckedInc(i)) {
            require(
                IERC20Upgradeable(tokenAddresses[i]).transferFrom(senders[i], address(this), amounts[i]),
                'SecuritizationPool: Transfer failed'
            );
        }

        if (openingBlockTimestamp() == 0) {
            // If openingBlockTimestamp is not set
            _setOpeningBlockTimestamp(uint64(block.timestamp));
        }
    }

    /// @inheritdoc ISecuritizationPool
    function withdrawERC20Assets(
        address[] calldata tokenAddresses,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external override whenNotPaused nonReentrant {
        registry().requirePoolAdminOrOwner(address(this), _msgSender());

        uint256 tokenAddressesLength = tokenAddresses.length;
        require(tokenAddressesLength == recipients.length, 'tokenAddresses length and tokenIds length are not equal');
        require(tokenAddressesLength == amounts.length, 'tokenAddresses length and recipients length are not equal');

        mapping(address => bool) storage existsTokenAssetAddress = _getStorage().existsTokenAssetAddress;
        for (uint256 i = 0; i < tokenAddressesLength; i = UntangledMath.uncheckedInc(i)) {
            require(existsTokenAssetAddress[tokenAddresses[i]], 'SecuritizationPool: note token asset does not exist');
            require(
                IERC20Upgradeable(tokenAddresses[i]).transfer(recipients[i], amounts[i]),
                'SecuritizationPool: Transfer failed'
            );
        }
    }

    function firstAssetTimestamp() public view returns (uint64) {
        return _getStorage().firstAssetTimestamp;
    }

    /// @inheritdoc ISecuritizationPool
    function setUpOpeningBlockTimestamp() public override whenNotPaused {
        require(_msgSender() == tgeAddress(), 'SecuritizationPool: Only tge address');
        _setUpOpeningBlockTimestamp();
    }

    /// @dev Set the opening block timestamp
    function _setUpOpeningBlockTimestamp() private {
        if (tgeAddress() == address(0)) return;
        uint64 _firstNoteTokenMintedTimestamp = ICrowdSale(tgeAddress()).firstNoteTokenMintedTimestamp();
        uint64 _firstAssetTimestamp = firstAssetTimestamp();
        if (_firstNoteTokenMintedTimestamp > 0 && _firstAssetTimestamp > 0) {
            // Pick the later
            if (_firstAssetTimestamp > _firstNoteTokenMintedTimestamp) {
                _setOpeningBlockTimestamp(_firstAssetTimestamp);
            } else {
                _setOpeningBlockTimestamp(_firstNoteTokenMintedTimestamp);
            }
        }

        emit UpdateOpeningBlockTimestamp(openingBlockTimestamp());
    }

    function _setOpeningBlockTimestamp(uint64 _openingBlockTimestamp) internal {
        Storage storage $ = _getStorage();
        $.openingBlockTimestamp = _openingBlockTimestamp;
        emit UpdateOpeningBlockTimestamp(_openingBlockTimestamp);
    }

    function riskScores(uint256 idx) public view virtual override returns (RiskScore memory) {
        return _getStorage().riskScores[idx];
    }

    function nftAssets(uint256 idx) public view virtual override returns (NFTAsset memory) {
        return _getStorage().nftAssets[idx];
    }

    function tokenAssetAddresses(uint256 idx) public view virtual override returns (address) {
        return _getStorage().tokenAssetAddresses[idx];
    }

    function pause() public virtual override {
        registry().requirePoolAdminOrOwner(address(this), _msgSender());
        _pause();
    }

    function unpause() public virtual override {
        registry().requirePoolAdminOrOwner(address(this), _msgSender());
        _unpause();
    }

    function getFunctionSignatures()
        public
        view
        virtual
        override(SecuritizationAccessControl, SecuritizationPoolStorage)
        returns (bytes4[] memory)
    {
        bytes4[] memory _functionSignatures = new bytes4[](19);

        _functionSignatures[0] = this.getNFTAssetsLength.selector;
        _functionSignatures[1] = this.getTokenAssetAddresses.selector;
        _functionSignatures[2] = this.getTokenAssetAddressesLength.selector;
        _functionSignatures[3] = this.getRiskScoresLength.selector;
        _functionSignatures[4] = this.riskScores.selector;
        _functionSignatures[5] = this.setupRiskScores.selector;
        _functionSignatures[6] = this.exportAssets.selector;
        _functionSignatures[7] = this.withdrawAssets.selector;
        _functionSignatures[8] = this.collectAssets.selector;
        _functionSignatures[9] = this.collectERC20Assets.selector;
        _functionSignatures[10] = this.withdrawERC20Assets.selector;
        _functionSignatures[11] = this.nftAssets.selector;
        _functionSignatures[12] = this.tokenAssetAddresses.selector;
        _functionSignatures[13] = this.setUpOpeningBlockTimestamp.selector;
        _functionSignatures[14] = this.supportsInterface.selector;
        _functionSignatures[15] = this.onERC721Received.selector;
        _functionSignatures[16] = this.pause.selector;
        _functionSignatures[17] = this.unpause.selector;
        _functionSignatures[18] = this.paused.selector;

        return _functionSignatures;
    }
}
