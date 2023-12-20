// SPDX-License-Identifier: MIT
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
        NOTE_TOKEN, // deprecated
        TOKEN_GENERATION_EVENT_FACTORY,
        DISTRIBUTION_OPERATOR,
        DISTRIBUTION_ASSESSOR,
        DISTRIBUTION_TRANCHE,
        LOAN_ASSET_TOKEN,
        ACCEPTED_INVOICE_TOKEN,
        LOAN_REGISTRY,
        LOAN_INTEREST_TERMS_CONTRACT,
        LOAN_REPAYMENT_ROUTER,
        LOAN_KERNEL,
        ERC20_TOKEN_REGISTRY,
        ERC20_TOKEN_TRANSFER_PROXY,
        SECURITIZATION_MANAGEMENT_PROJECT,
        SECURITIZATION_POOL_VALUE_SERVICE,
        MINTED_INCREASING_INTEREST_TGE, // depreacated
        MINTED_NORMAL_TGE, // depreacated
        INVOICE_COLLATERALIZER,
        INVOICE_DEBT_REGISTRY,
        INVOICE_FINANCE_INTEREST_TERMS_CONTRACT,
        INVOICE_LOAN_KERNEL,
        INVOICE_LOAN_REPAYMENT_ROUTER,
        GO,
        POOL_NAV_FACTORY,
        NOTE_TOKEN_VAULT
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
