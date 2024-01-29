// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

contract LoanTyping {
    enum LoanTypes {
        WAREHOUSE_RECEIPT,
        INPUT_FINANCE,
        INVOICE_FINANCE,
        INVENTORY_FINANCE
    }
}
