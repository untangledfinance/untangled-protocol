# Untangled Protocol

Untangled is a decentralized lending and liquidity protocol for real world asset collaterals.

Untangled protocol code has been inspired by Centrifuge, Goldfinch and MakerDao, among others. Untangled protocol contracts are under AGPL license.

## Installing

#### Packages

Run the following to install all package dependencies:

```shell
# Just the first time
npm install
```

## Developing

### Smart Contract Development

All contracts are located under `contracts`

1. Make your changes
2. Write tests, which should be placed under `test`
3. Write great commit messages, and put up your PR!

### Directory structure

[to update]

### Contributing

-   See the [`CONTRIBUTING.MD`](./CONTRIBUTING.MD)

### Code of Conduct

-   See the [`CODE_OF_CONDUCT.MD`](./CODE_OF_CONDUCT.MD)

### Testing

Run `npm test` to run tests for all contracts.

### Stress test

Run `REPORT_GAS=true hardhat test stress/FillDebtOrder.js` to stress test fillDebtOrder function with gas report 
shown in console

### Compiling Smart Contracts

```
npm run compile
```

### Deployment

For interactions or contract deployments on public testnets / mainnet, create a .env file specifying your private key and infura api key, with the `.env.example` format.

```
yarn deploy --tags [..] --network [..]
```

`truffle migrate --reset --compile-all --network development`

## To run Slither, in project folder run

`slither .`

## To create checklist

`slither . --checklist --markdown-root https://github.com/untangledfinance/untangled-protocol-open/blob/a57c20d7e2a04b26655fec9bb099db70bb053088/`
