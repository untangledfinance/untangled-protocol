const { POOL_ADMIN_ROLE, OWNER_ROLE, ORIGINATOR_ROLE } = require('../test/constants');
const { utils, BigNumber } = require('ethers');

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { get, execute } = deployments;

    const { deployer } = await getNamedAccounts();

    const udsc = network.config.usdc;

    const salt = utils.keccak256(Date.now());

    await execute(
        'SecuritizationManager',
        { from: deployer, log: true },
        'newPoolInstance',
        salt,
        deployer,
        utils.defaultAbiCoder.encode(
            [
                {
                    type: 'tuple',
                    components: [
                        { name: 'debtCeiling', type: 'uint256' },
                        { name: 'currency', type: 'address' },
                        { name: 'minFirstLossCushion', type: 'uint32' },
                        { name: 'validatorRequired', type: 'bool' },
                    ],
                },
            ],
            [
                {
                    debtCeiling: utils.parseEther('1000').toString(),
                    currency: udsc,
                    minFirstLossCushion: BigNumber.from(10 * 10000),
                    validatorRequired: true,
                },
            ]
        )
    );
};

module.exports.tags = ['SetupPool'];
