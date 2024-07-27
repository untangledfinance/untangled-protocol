const { utils, BigNumber } = require('ethers');

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deployer } = await getNamedAccounts();
    const { deploy, read, get, execute } = deployments;

    const usdc = '0x47C7b654E3432EcDc77e806D01bc389c67e4E99c';

    const POOL_ADMIN_ROLE = utils.keccak256(Buffer.from('POOL_CREATOR'));
    const poolAdminAddress = '0xC52a72eDdcA008580b4Efc89eA9f343AfF11FeA3';
    await execute(
        'SecuritizationManager',
        {
            from: deployer,
            log: true,
        },
        'grantRole',
        POOL_ADMIN_ROLE,
        poolAdminAddress
    );

    await execute(
        'SecuritizationManager',
        {
            from: deployer,
            log: true,
        },
        'newPoolInstance',
        utils.keccak256(Date.now()),
        poolAdminAddress,
        utils.defaultAbiCoder.encode(
            [
                {
                    type: 'tuple',
                    components: [
                        {
                            name: 'currency',
                            type: 'address',
                        },
                        {
                            name: 'minFirstLossCushion',
                            type: 'uint32',
                        },
                        {
                            name: 'validatorRequired',
                            type: 'bool',
                        },
                        {
                            name: 'debtCeiling',
                            type: 'uint256',
                        },
                    ],
                },
            ],
            [
                {
                    currency: usdc,
                    minFirstLossCushion: BigNumber.from(10 * 10000),
                    validatorRequired: true,
                    debtCeiling: utils.parseEther('1000').toString(),
                },
            ]
        )
    );
};

module.exports.dependencies = ['SecuritizationManager'];
module.exports.tags = ['NewPoolInstance'];
