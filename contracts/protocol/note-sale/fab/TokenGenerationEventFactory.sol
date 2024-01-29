// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {UntangledBase} from '../../../base/UntangledBase.sol';
import {ITokenGenerationEventFactory} from './ITokenGenerationEventFactory.sol';
import {ConfigHelper} from '../../../libraries/ConfigHelper.sol';
import {Factory} from '../../../base/Factory.sol';
import {Registry} from '../../../storage/Registry.sol';
import {UntangledMath} from '../../../libraries/UntangledMath.sol';
import {MintedIncreasingInterestTGE} from '../MintedIncreasingInterestTGE.sol';
import {MintedNormalTGE} from '../MintedNormalTGE.sol';
import {Registry} from '../../../storage/Registry.sol';

interface INoteTokenLike {
    function poolAddress() external view returns (address);
}

contract TokenGenerationEventFactory is ITokenGenerationEventFactory, UntangledBase, Factory {
    using ConfigHelper for Registry;

    bytes4 constant TGE_INIT_FUNC_SELECTOR = bytes4(keccak256('initialize(address,address,address,address,bool)'));

    function __TokenGenerationEventFactory_init(Registry _registry, address _factoryAdmin) internal onlyInitializing {
        __UntangledBase__init(_msgSender());
        __Factory__init(_factoryAdmin);

        registry = _registry;
    }

    function initialize(Registry _registry, address _factoryAdmin) public initializer {
        __TokenGenerationEventFactory_init(_registry, _factoryAdmin);
    }

    function setFactoryAdmin(address _factoryAdmin) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setFactoryAdmin(_factoryAdmin);
    }

    function setTGEImplAddress(SaleType tgeType, address newImpl) public {
        require(
            isAdmin() || hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            'UntangledBase: Must have admin role to perform this action'
        );
        require(newImpl != address(0), 'TokenGenerationEventFactory: TGEImplAddress cannot be zero');
        TGEImplAddress[tgeType] = newImpl;
        emit UpdateTGEImplAddress(tgeType, newImpl);
    }

    function createNewSaleInstance(
        address issuerTokenController,
        address token,
        address currency,
        uint8 saleType,
        bool longSale
    ) external override whenNotPaused nonReentrant returns (address) {
        registry.requireSecuritizationManager(_msgSender());

        address pool = INoteTokenLike(token).poolAddress();

        if (saleType == uint8(SaleType.MINTED_INCREASING_INTEREST_SOT)) {
            return
                _newSale(
                    TGEImplAddress[SaleType.MINTED_INCREASING_INTEREST_SOT],
                    issuerTokenController,
                    pool,
                    token,
                    currency,
                    longSale
                );
        }

        if (saleType == uint8(SaleType.NORMAL_SALE_JOT)) {
            return
                _newSale(
                    TGEImplAddress[SaleType.NORMAL_SALE_JOT],
                    issuerTokenController,
                    pool,
                    token,
                    currency,
                    longSale
                );
        }

        if (saleType == uint8(SaleType.NORMAL_SALE_SOT)) {
            return
                _newSale(
                    TGEImplAddress[SaleType.NORMAL_SALE_SOT],
                    issuerTokenController,
                    pool,
                    token,
                    currency,
                    longSale
                );
        }

        revert('Unknown sale type');
    }

    function _newSale(
        address tgeImpl,
        address issuerTokenController,
        address pool,
        address token,
        address currency,
        bool longSale
    ) private returns (address) {
        bytes memory _initialData = abi.encodeWithSelector(
            TGE_INIT_FUNC_SELECTOR,
            registry,
            pool,
            token,
            currency,
            longSale
        );

        address tgeAddress = _deployInstance(tgeImpl, _initialData);
        UntangledBase tge = UntangledBase(tgeAddress);

        tge.grantRole(tge.OWNER_ROLE(), issuerTokenController);
        tge.renounceRole(tge.OWNER_ROLE(), address(this));

        tgeAddresses.push(tgeAddress);
        isExistingTge[tgeAddress] = true;

        emit TokenGenerationEventCreated(tgeAddress);

        return tgeAddress;
    }

    function pauseUnpauseTge(address tgeAdress) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isExistingTge[tgeAdress], 'TokenGenerationEventFactory: tge does not exist');
        MintedIncreasingInterestTGE tge = MintedIncreasingInterestTGE(tgeAdress);
        if (tge.paused()) {
            tge.unpause();
        } else {
            tge.pause();
        }
    }

    function pauseUnpauseAllTges() external whenNotPaused nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 tgeAddressesLength = tgeAddresses.length;
        for (uint256 i = 0; i < tgeAddressesLength; i = UntangledMath.uncheckedInc(i)) {
            MintedIncreasingInterestTGE tge = MintedIncreasingInterestTGE(tgeAddresses[i]);
            if (tge.paused()) {
                tge.unpause();
            } else {
                tge.pause();
            }
        }
    }

    uint256[50] private __gap;
}
