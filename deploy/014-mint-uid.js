const { getChainId, ethers } = require('hardhat');
const { presignedMintMessage } = require('../test/shared/uid-helper');
const dayjs = require('dayjs');

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { get, execute } = deployments;

    const uniqueIdentity = await get('UniqueIdentity');

    const { deployer } = await getNamedAccounts();

    const [adminSigner] = await ethers.getSigners();

    const UID_TYPE = 0;

    const nonce = 1;

    const chainID = await getChainId();

    const managerAddress = network.config.manager;

    const expiredAt = dayjs().unix() + 86400 * 1000;

    const ethRequired = ethers.utils.parseEther('0.00083');

    const uidMintMsg = ethers.utils.keccak256(
        ethers.utils.solidityPack(
            ['address', 'address', 'uint256', 'uint256', 'address', 'uint256', 'uint256'],
            [deployer, managerAddress, UID_TYPE, expiredAt, uniqueIdentity.address, nonce, chainID]
        )
    );

    const signature = await adminSigner.signMessage(ethers.utils.arrayify(uidMintMsg));

    await execute(
        'UniqueIdentity',
        { from: deployer, log: true, value: ethRequired },
        'mintTo',
        managerAddress,
        UID_TYPE,
        expiredAt,
        signature
    );
};

module.exports.tags = ['MintUID'];
