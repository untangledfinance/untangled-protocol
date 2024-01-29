// All supported networks and related contract addresses are defined here.
//
// LINK token addresses: https://docs.chain.link/resources/link-token-contracts/
// Price feeds addresses: https://docs.chain.link/data-feeds/price-feeds/addresses
// Chain IDs: https://chainlist.org/?testnets=true

require('dotenv').config();

const DEFAULT_VERIFICATION_BLOCK_CONFIRMATIONS = 2;

const npmCommand = process.env.npm_lifecycle_event;
const isTestEnvironment = npmCommand == 'test' || npmCommand == 'test:unit';

const PRIVATEKEY = process.env.PRIVATEKEY;

if (!isTestEnvironment && !PRIVATEKEY) {
    throw Error('Set the PRIVATEKEY environment variable with your EVM wallet private key');
}

const networks = {
    sepolia: {
        url: 'https://rpc-sepolia.rockx.com',
        gasPrice: undefined,
        accounts: PRIVATEKEY !== undefined ? [PRIVATEKEY] : [],
        // verifyApiKey: "THIS HAS NOT BEEN SET",
        chainId: 11155111,
        confirmations: DEFAULT_VERIFICATION_BLOCK_CONFIRMATIONS,
        nativeCurrencySymbol: 'ETH',

        // https://docs.chain.link/ccip/supported-networks/
        router: '0xd0daae2231e9cb96b94c8512223533293c3693bf',
        chainSelector: '16015286601757825753',
        linkToken: '0x779877A7B0D9E8603169DdbD7836e478b4624789',
        bnmToken: '0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05', // LINK/SEPOLIA-ETH
    },
    mumbai: {
        url: 'https://polygon-mumbai.blockpi.network/v1/rpc/public',
        gasPrice: undefined,
        // blockGasLimit: 100000000429720,
        accounts: PRIVATEKEY !== undefined ? [PRIVATEKEY] : [],
        // verifyApiKey: "THIS HAS NOT BEEN SET",
        chainId: 80001,
        // confirmations: DEFAULT_VERIFICATION_BLOCK_CONFIRMATIONS,
        nativeCurrencySymbol: 'MATIC',

        // https://docs.chain.link/ccip/supported-networks/
        router: '0x70499c328e1E2a3c41108bd3730F6670a44595D1',
        chainSelector: '12532609583862916517',
        linkToken: '0x326C977E6efc84E512bB9C30f76E30c160eD06FB',
        bnmToken: '0xf1E3A5842EeEF51F2967b3F05D45DD4f4205FF40',
        kycAdmin: '0x9C469Ff6d548D0219575AAc9c26Ac041314AE2bA',
    },
    ether: {
        url: 'https://ethereum.publicnode.com',
        gasPrice: undefined,
        // blockGasLimit: 100000000429720,
        accounts: PRIVATEKEY !== undefined ? [PRIVATEKEY] : [],
        // verifyApiKey: "THIS HAS NOT BEEN SET",
        chainId: 1,
        // confirmations: DEFAULT_VERIFICATION_BLOCK_CONFIRMATIONS,
        nativeCurrencySymbol: 'ETH',

        // https://docs.chain.link/ccip/supported-networks/
        router: '0xE561d5E02207fb5eB32cca20a699E0d8919a1476',
        chainSelector: '5009297550715157269',
        linkToken: '0x514910771AF9Ca656af840dff83E8264EcF986CA',
        bnmToken: '',
    },
    polygon: {
        url: 'https://rpc.ankr.com/polygon',
        gasPrice: undefined,
        blockGasLimit: 100000000429720,
        accounts: PRIVATEKEY !== undefined ? [PRIVATEKEY] : [],
        // verifyApiKey: "THIS HAS NOT BEEN SET",
        chainId: 137,
        // confirmations: DEFAULT_VERIFICATION_BLOCK_CONFIRMATIONS,
        nativeCurrencySymbol: 'MATIC',

        // https://docs.chain.link/ccip/supported-networks/
        router: '0x3C3D92629A02a8D95D5CB9650fe49C3544f69B43',
        chainSelector: '4051577828743386545',
        linkToken: '0xb0897686c545045aFc77CF20eC7A532E3120E0F1',
        bnmToken: '',
        kycAdmin: '0x9C469Ff6d548D0219575AAc9c26Ac041314AE2bA',
    },
};

module.exports = {
    networks,
};
