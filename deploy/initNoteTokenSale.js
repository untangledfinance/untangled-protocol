module.exports = async ({ getNamedAccounts, deployments }) => {
    const { execute } = deployments;
    const { deployer } = await getNamedAccounts();

    // await execute(
    //     'SecuritizationManager',
    //     { from: deployer, log: true },
    //     'setUpTGEForSOT',
    //     network.config.pool,
    //     0,
    //     0,
    //     2,
    //     'SOT_'
    // );

    const issuer = '0x39b7AdC6aAf5b70948680833a0E0c2722f007790';
    const pool = '0xd0f44d42ff1aeededcc0aa85293de0e7bc7912c8';
    const minBidAmount = 0;
    const cap = 600000 * 10e6;
    const saleType = 0;
    const openingTime = 1728086047;
    const ticker = 'Ticker_';
    const intialAmount = 0;

    await execute(
        'SecuritizationManager',
        { from: deployer, log: true },
        'setUpTGEForJOT',
        {
            issuerTokenController: issuer,
            pool: pool,
            minBidAmount: minBidAmount,
            totalCap: cap,
            openingTime: openingTime,
            saleType: saleType,
            longSale: true,
            ticker: ticker,
        },
        intialAmount
    );
};

module.exports.tags = ['InitNoteTokenSale'];
