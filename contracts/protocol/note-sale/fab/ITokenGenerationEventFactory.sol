// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import '../../../storage/Registry.sol';
import '../../../interfaces/INoteToken.sol';

abstract contract ITokenGenerationEventFactory {
    enum SaleType {
        MINTED_INCREASING_INTEREST_SOT,
        NORMAL_SALE_JOT,
        NORMAL_SALE_SOT
    }

    event UpdateTGEImplAddress(SaleType indexed tgeType, address newImpl);
    event TokenGenerationEventCreated(address indexed tgeInstance);

    Registry public registry;
    address[] public tgeAddresses;
    mapping(address => bool) public isExistingTge;
    mapping(SaleType => address) public TGEImplAddress;

    /// @notice creates a new TGE instance based on the provided parameters and the sale type
    function createNewSaleInstance(
        address issuerTokenController,
        // address pool,
        address token,
        address currency,
        uint8 saleType,
        bool longSale
    ) external virtual returns (address);

    uint256[46] private __gap;
}
