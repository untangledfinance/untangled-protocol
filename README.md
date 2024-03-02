## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Install and Build

```shell
$ forge install
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```
### .env
```shell
$ cp .env.example .env
```
To set up, copy the .env file and populate the RPC FETCH section.
### Anvil forge to local
```shell
$ source .env
$ anvil --fork-url $FETCH_RPC
```

### Run update script test
This is a script that pranks the owner's address of the contract proxy admin. It then simulates a transaction to update the contract logic.
Have to run Anvil using the FETCH RPC initially.Then
```shell
$ source .env
$ forge script script/Update.s.sol --rpc-url $ANVIL
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
