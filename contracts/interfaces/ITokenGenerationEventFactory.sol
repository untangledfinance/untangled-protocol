// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import '../storage/Registry.sol';
import './INoteToken.sol';

interface ITokenGenerationEventFactory {
    enum SaleType {
        NORMAL_SALE_JOT,
        NORMAL_SALE_SOT
    }

    event UpdateTGEImplAddress(SaleType indexed tgeType, address newImpl);
    event TokenGenerationEventCreated(address indexed tgeInstance);

    /// @notice creates a new TGE instance based on the provided parameters and the sale type
    function createNewSaleInstance(
        address issuerTokenController,
        address token,
        address currency,
        uint8 saleType,
        uint256 openingTime
    ) external returns (address);
}
