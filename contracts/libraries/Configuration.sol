// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

/// @title Configuration
/// @author Untangled Team
library Configuration {
    // NEVER EVER CHANGE THE ORDER OF THESE!
    // You can rename or append. But NEVER change the order.
    enum CONTRACT_TYPE {
        SECURITIZATION_MANAGER,
        SECURITIZATION_POOL,
        NOTE_TOKEN_FACTORY,
        SENIOR_TOKEN_MANAGER,
        JUNIOR_TOKEN_MANAGER,
        EPOCH_EXECUTOR,
        DISTRIBUTION_ASSESSOR,
        LOAN_ASSET_TOKEN,
        LOAN_KERNEL,
        SECURITIZATION_POOL_VALUE_SERVICE,
        GO
    }

    enum NOTE_TOKEN_TYPE {
        SENIOR,
        JUNIOR
    }

    enum ASSET_PURPOSE {
        LOAN,
        INVOICE
    }
}
