require('solidity-coverage');
require('@nomiclabs/hardhat-web3');
require('@nomiclabs/hardhat-ethers');
require('hardhat-contract-sizer');
require('hardhat-deploy');
require('@openzeppelin/hardhat-upgrades');
require('@nomicfoundation/hardhat-chai-matchers');
require('hardhat-gas-reporter');
require('hardhat-abi-exporter');
require('hardhat-if-gen');

require('dotenv').config();
require('./tasks');
const { networks } = require('./networks');

const MNEMONIC = process.env.MNEMONIC;
const PRIVATEKEY = process.env.PRIVATEKEY;

const accounts = [PRIVATEKEY];
module.exports = {
    solidity: {
        compilers: [
            {
                version: '0.8.19',
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
        ],
        overrides: {
            'contracts/protocol/pool/SecuritizationPool.sol': {
                version: '0.8.19',
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
        },
    },
    defaultNetwork: 'hardhat',
    namedAccounts: {
        deployer: 0,
        invoiceOperator: '0x5380e40aFAd8Cdec0B841c4740985F1735Aa5aCB',
    },
    networks: {
        hardhat: {
            blockGasLimit: 50000000,
            saveDeployments: true,
            allowUnlimitedContractSize: false,
            accounts: {
                mnemonic: MNEMONIC,
            },
            kycAdmin: '0x9C469Ff6d548D0219575AAc9c26Ac041314AE2bA',
            superAdmin: '0x4363daA50a24eb451acdF7DA963233F6b78fc2c9',
            // forking: {
            //     url: 'https://alfajores-forno.celo-testnet.org',
            //     // url: 'https://rpc.ankr.com/polygon',
            //     blockNumber: 22829184,
            // },
            // chainId: 44787,
        },
        celo: {
            saveDeployments: true,
            accounts,
            loggingEnabled: true,
            url: `https://forno.celo.org`,
            cusdToken: '0x765DE816845861e75A25fCA122bb6898B8B1282a',
            usdcToken: '0xef4229c8c3250c675f21bcefa42f58efbff6002a',
            kycAdmin: '0x9C469Ff6d548D0219575AAc9c26Ac041314AE2bA',
        },
        alfajores: {
            saveDeployments: true,
            accounts: accounts,
            loggingEnabled: true,
            url: `https://alfajores-forno.celo-testnet.org`,
            cusdToken: '0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1',
            usdcToken: '',
            kycAdmin: '0x9C469Ff6d548D0219575AAc9c26Ac041314AE2bA',
            superAdmin: '0x60e7b40B1f46971B800cd00200371fFd35c09Da9',
            beSigner: '0x39870FB7417307f602dc2e9D997e3f1D20762669',
            beAdmin: '0x39870FB7417307f602dc2e9D997e3f1D20762669',
        },
        alfajores_v2: {
            saveDeployments: true,
            accounts: accounts,
            loggingEnabled: true,
            url: `https://alfajores-forno.celo-testnet.org`,
            cusdToken: '0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1',
            usdcToken: '',
            kycAdmin: '0x9C469Ff6d548D0219575AAc9c26Ac041314AE2bA',
        },
        alfajores_v3: {
            saveDeployments: true,
            accounts: accounts,
            loggingEnabled: true,
            url: `https://alfajores-forno.celo-testnet.org`,
            cusdToken: '0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1',
            usdcToken: '',
            kycAdmin: '0x9C469Ff6d548D0219575AAc9c26Ac041314AE2bA',
            superAdmin: '0x60e7b40B1f46971B800cd00200371fFd35c09Da9',
            beSigner: '0x39870FB7417307f602dc2e9D997e3f1D20762669',
            beAdmin: '0x39870FB7417307f602dc2e9D997e3f1D20762669',
        },
        rinkeby: {
            saveDeployments: true,
            accounts,
            loggingEnabled: true,
            url: `https://rinkeby.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161`,
        },
        arbSepolia: {
            saveDeployments: true,
            accounts: accounts,
            loggingEnabled: true,
            url: 'https://public.stackup.sh/api/v1/node/arbitrum-sepolia',
            kycAdmin: '0x4363daA50a24eb451acdF7DA963233F6b78fc2c9',
            superAdmin: '0x4363daA50a24eb451acdF7DA963233F6b78fc2c9',
            beAdmin: '0x4363daA50a24eb451acdF7DA963233F6b78fc2c9',
        },
        ...networks,
    },
    etherscan: {
        apiKey: {
            alfajores: process.env.ALFAJORES_SCAN_API_KEY,
            polygon_v2: process.env.POLYGON_SCAN_API_KEY,
        },
        customChains: [
            {
                network: 'alfajores',
                chainId: 44787,
                urls: {
                    apiURL: 'https://api-alfajores.celoscan.io/api',
                    browserURL: 'https://api-alfajores.celoscan.io',
                },
            },
            {
                network: 'polygon_v2',
                chainId: 137,
                urls: {
                    apiURL: 'https://api.polygonscan.com/api',
                    browserURL: 'https://api.polygonscan.com',
                },
            },
        ],
    },
    mocha: {
        timeout: 200000,
    },
    paths: {
        sources: './contracts',
        tests: './test',
        artifacts: './artifacts',
        cache: './cache',
    },
    contractSizer: {
        alphaSort: true,
        runOnCompile: true,
        disambiguatePaths: false,
    },

    abiExporter: [
        {
            path: './abi/json',
            format: 'json',
        },
        {
            path: './abi/minimal',
            format: 'minimal',
        },
        // {
        //     path: './abi/fullName',
        //     format: "fullName",
        // },
    ],
    gasReporter: {
        enabled: process.env.REPORT_GAS ? true : false,
        currency: 'USD',
        onlyCalledMethods: true,
        coinmarketcap: 'b7703f84-a44a-4812-8cf9-e4a3a648af5c',
        gasPriceApi: 'https://api.etherscan.io/api?module=proxy&action=eth_gasPrice',
    },
};
