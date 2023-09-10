const { ethers, getChainId } = require('hardhat');
const { deployments } = require('hardhat');
const { BigNumber } = require('ethers');
const dayjs = require('dayjs');
const { expect } = require('./shared/expect.js');
const { presignedMintMessage } = require('./shared/uid-helper.js');
const { mine, time } = require('@nomicfoundation/hardhat-network-helpers');

const ONE_DAY = 86400;
const DECIMAL = BigNumber.from(10).pow(18);
describe('Full flow', () => {
  let setupTest;
  let stableCoin;
  let securitizationManagerContract;
  let loanKernelContract;
  let loanRepaymentRouterContract;
  let loanAssetTokenContract;
  let uniqueIdentityContract;
  let loanInterestTermContract;
  let distributionOperator;
  let distributionTranche;

  // Wallets
  let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner;
  before('create fixture', async () => {
    [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner] =
      await ethers.getSigners();
    setupTest = deployments.createFixture(async ({ deployments, getNamedAccounts, ethers }, options) => {
      await deployments.fixture(); // ensure you start from a fresh deployments
      const tokenFactory = await ethers.getContractFactory('TestERC20');
      const stableCoin = await tokenFactory.deploy('cUSD', 'cUSD', BigNumber.from(2).pow(255));
      await stableCoin.transfer(lenderSigner.address, BigNumber.from(1000).mul(DECIMAL)); // Lender has 1000$
      await stableCoin.transfer(originatorSigner.address, BigNumber.from(10000).mul(DECIMAL)); // Originator has 10000$
      const { get } = deployments;
      securitizationManagerContract = await ethers.getContractAt(
        'SecuritizationManager',
        (
          await get('SecuritizationManager')
        ).address
      );
      loanKernelContract = await ethers.getContractAt('LoanKernel', (await get('LoanKernel')).address);
      loanRepaymentRouterContract = await ethers.getContractAt(
        'LoanRepaymentRouter',
        (
          await get('LoanRepaymentRouter')
        ).address
      );
      loanAssetTokenContract = await ethers.getContractAt('LoanAssetToken', (await get('LoanAssetToken')).address);

      uniqueIdentityContract = await ethers.getContractAt('UniqueIdentity', (await get('UniqueIdentity')).address);
      loanInterestTermContract = await ethers.getContractAt('LoanInterestTermsContract', (await get('LoanInterestTermsContract')).address);
      distributionOperator = await ethers.getContractAt('DistributionOperator', (await get('DistributionOperator')).address);
      distributionTranche = await ethers.getContractAt('DistributionTranche', (await get('DistributionTranche')).address);
      return {
        stableCoin: stableCoin,
      };
    });
  });
  beforeEach('deploy fixture', async () => {
    ({ stableCoin } = await setupTest());
  });

  it('Full flow', async function () {
    // await deployments.fixture();
    const { get } = deployments;

    //
    const POOL_CREATOR_ROLE = await securitizationManagerContract.POOL_CREATOR();
    await securitizationManagerContract.grantRole(POOL_CREATOR_ROLE, poolCreatorSigner.address);
    // Create new pool
    const transaction = await securitizationManagerContract
      .connect(poolCreatorSigner)
      .newPoolInstance(stableCoin.address, '100000');
    const receipt = await transaction.wait();
    const [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;

    const securitizationPoolContract = await ethers.getContractAt('SecuritizationPool', securitizationPoolAddress);

    await securitizationPoolContract
      .connect(poolCreatorSigner)
      .setupRiskScores(
        [86400, 2592000, 5184000, 7776000, 10368000, 31536000],
        [
          950000, 900000, 910000, 800000, 810000, 0, 1500000, 1500000, 1500000, 1500000, 1500000, 1500000, 80000,
          100000, 120000, 120000, 140000, 1000000, 10000, 20000, 30000, 40000, 50000, 1000000, 250000, 500000, 500000,
          750000, 1000000, 1000000,
        ],
        [
          432000, 432000, 432000, 432000, 432000, 432000, 2592000, 2592000, 2592000, 2592000, 2592000, 2592000, 250000,
          500000, 500000, 750000, 1000000, 1000000, 1000000, 1000000, 1000000, 1000000, 1000000, 1000000,
        ]
      );

    await loanKernelContract.fillDebtOrder(
      [
        originatorSigner.address,
        stableCoin.address,
        loanRepaymentRouterContract.address,
        '0x348AC65F1968435dfBda0da76e1B259CAe16c0e8',
        '0x5d99687F0d1F20C39EbBb4E9890999BEB7F754A5',
        '0x0000000000000000000000000000000000000000',
        '0x0000000000000000000000000000000000000000',
        '0x0000000000000000000000000000000000000000',
        '0x0000000000000000000000000000000000000000',
        '0x0000000000000000000000000000000000000000',
        '0x0000000000000000000000000000000000000000',
        '0x0000000000000000000000000000000000000000',
        '0x0000000000000000000000000000000000000000',
        '0x0000000000000000000000000000000000000000',
        '0x0000000000000000000000000000000000000000',
        '0x0000000000000000000000000000000000000000',
        '0x0000000000000000000000000000000000000000',
        '0x0000000000000000000000000000000000000000',
        '0x0000000000000000000000000000000000000000',
        '0x0000000000000000000000000000000000000000',
        '0x0000000000000000000000000000000000000000',
        '0x0000000000000000000000000000000000000000',
        '0x0000000000000000000000000000000000000000',
        '0x0000000000000000000000000000000000000000',
        '0x0000000000000000000000000000000000000000',
      ],
      [
        '0',
        '0',
        '456820000000000000',
        '365550000000000000',
        '350030000000000000',
        '118530000000000000',
        '385910000000000000',
        '100820000000000000',
        '280300000000000000',
        '193210000000000000',
        '164940000000000000',
        '248450000000000000',
        '262010000000000030',
        '221970000000000000',
        '191120000000000000',
        '282839999999999970',
        '192090000000000000',
        '318280000000000000',
        '300710000000000000',
        '188620000000000000',
        '57370000000000000',
        '126830000000000000',
        '1667149200',
        '1656003600',
        '1668445200',
        '1620061200',
        '1673888400',
        '1618678800',
        '1654707600',
        '1705251600',
        '1648918800',
        '1656954000',
        '1650042000',
        '1671123600',
        '1662656400',
        '1663174800',
        '1644166800',
        '1679331600',
        '1692896400',
        '1674752400',
        '1649523600',
        '1673974800',
        '6164411054',
        '9318449793',
        '7715593433',
        '9207784601',
        '2184297706',
        '5351475035',
        '2515114902',
        '3790349377',
        '8900494839',
        '8352499066',
        '7888948025',
        '9076625907',
        '9396909362',
        '8676575345',
        '2477640875',
        '9361161236',
        '6801571306',
        '7325230340',
        '6903890397',
        '6019707613',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
      ],
      [
        '0x00000000000656f35ea24b40000186a010000000000000000000044700200000',
        '0x00000000000512b1c9c9a4e00002710010000000000000000000044700200000',
        '0x000000000004db8e6e32bae00001fbd010000000000000000000044700200000',
        '0x000000000001a51a68313a200001adb010000000000000000000047400200000',
        '0x0000000000055b0719b145600002710010000000000000000000066c00200000',
        '0x000000000001662f417e4140000222e010000000000000000000044880200000',
        '0x000000000003e3d35d6a8ac00001d4c01000000000000000000005e680200000',
        '0x000000000002ae6b78a90da00002bf2010000000000000000000088f80200000',
        '0x00000000000249fc0e5d40c00001fbd010000000000000000000069900200000',
        '0x00000000000372abf56a7220000186a010000000000000000000049f80200000',
        '0x000000000003a2d8b4f199a02001d4c010000000000000000000044700200000',
        '0x000000000003149889f8cb200000c35010000000000000000000088f80200000',
        '0x000000000002a6fea09d7900000222e010000000000000000000066c00200000',
        '0x000000000003ecd97b40457fe001388010000000000000000000044700200000',
        '0x000000000002aa70d656e7a00000ea6010000000000000000000059280200000',
        '0x0000000000046ac1f9431c800001fbd010000000000000000000066a80200000',
        '0x0000000000042c5626da68600001fbd010000000000000000000066a80200000',
        '0x0000000000029e1ce40188c000015f9010000000000000000000066c00200000',
        '0x000000000000cbd1b606c3a00000ea6010000000000000000000056280200000',
        '0x000000000001c2973688dce000015f9010000000000000000000088f80200000',
      ],
      [
        '0x979b5e9fab60f9433bf1aa924d2d09636ae0f5c10e2c6a8a58fe441cd1414d7f',
        '0x583057423a4229bfb018a7cf05140649f0f4dc560f4dce8f46f386b1a6df2c2b',
        '0x0402e6a3fda04c590f0de9573cb886b909202a646e29b1505347dbdad71993fb',
        '0x9b267ee2976a46d4c8d37d7b452b40fe1d524430d3e8bc19a2106cadf20d03b8',
        '0xd8ecd3440fa68d7d87f9b3d22ad267ba4e42aad35f07f0112b72bef1b3442eaf',
        '0x1d262f75bc61c2035fe711930f7accf63a4906996cc18c57039f881f835a26db',
        '0xb8566a5ca2016c3d317a3b51deba1869e0ef90e439d56f7c0dd2d7c7a296ee00',
        '0x41dfca479a323413fb4721088abf12b8be2e06c751acc6a293c250cd74f5f55c',
        '0xec7ea982a41e482772525ebf630fc794a7316faee17acb543d8b6c96a5502124',
        '0x93e94a5965297a85d7d7cd9d8ca9daac5fd85667e7f44b8ebddde4e06d82a244',
        '0x24cfbe5d11d2344117dff57f1c47243f5bbec2dda3369b19eb58440dc09da8fa',
        '0xc9641c808d7b9e8c8d83a9c494efd9984f3e9eee5fa95b95cf6e7327ff4f8ef9',
        '0x2d768443b139e63ac48dc4a0f2309e44867776956006ae3db2de93c1d17e2ec1',
        '0x944b447816387dc1f14b1a81dc4d95a77f588c214732772d921e146acd456b2b',
        '0x725e613eb000371ef36950a45b9fa2800660747688fda13025b55b82879d2ed0',
        '0x198cd3e1629cee367ced338ba3255a00d72f44586f4cd9bc3023d9729e8a1d89',
        '0x9b38c17833f4c8b2bc863f33efef835d0e600afba2bbe746e3794f4fcdfdaf3a',
        '0x00303c50018007223c0db10159de590061947bb1d4e75f5fceaa489a72f0fb8e',
        '0xe6ab9cbdeb3b24f86bd997c50e28f97769da3b31c3bbef8afe53abee5a272634',
        '0x791c3c012c84b1f53bc3b945c9f464cad42acf893cfd695e7df8f66e561579e4',
        '0x525c99ffa98599b90164b2a04799af8ee0d7367440de5f5e330b49af57987eb1',
        '0x747547df73b3515acfc3d87aa45a428a9394185ba47a668674c5f674f63f62eb',
        '0x816f42a104360f90b1210d2e78cb375baeef9fd3f4229e5c475817d90fa82510',
        '0xb96a1c004484726e97f0dcabb13ab5d33ffc35f6acefda0c265ac8a53cf0e0aa',
        '0xddfadd695790dfcf22211f95f39cb2e47085cc55030e9de65f80a197f05ad948',
        '0x5f072f62410e1d0b82518604d6b54a8b7c1744a670342b7617393c018267db59',
        '0x2e08e0a653a3a582493161ca12fd6f6c3ec5f432e7ee6bacb9465294b418ce60',
        '0x650ae46836353dbe054b64dc094dd1ad3601141b6a68b8593fa31b7622307770',
        '0x342c11d0ab77a057b86f75c2d755e6dc75ea5351a5e696dcb000cc1664255158',
        '0x7242626e08e727a9d90eb9c6a6ceeb18a90e308ed7d9a91d6c519919cf735b85',
        '0x1f415164b159accfeae9638bdc15f05ee2b2ccaf490e609cfa1148f9a45debb7',
        '0x530a35812694500e53444e84f8f6635ee4b0a3c982a7f2cede32d8478107ef51',
        '0x4901f09e141cc8eb96b0fe2a1f7ff87f3879543bd2632c3126797dd8209bd3b4',
        '0x663c565d6b54bfdf9b350cab706a1ee85cc086a8e33a4dfe9fd6814d10e6198e',
        '0xd722b0d30bc29a7dfb4847696bb5b7cac449db4a0cfb28766212846d8db24693',
        '0xe58adf7af81606c7a45f95406954dd0fc396eaf65177ddbd90ad13afbe974354',
        '0x36abcdc1087e7463a94b05668627e687afe872815f01f937479894b65fc2908a',
        '0xeb03ce11837f5e93a467938bc2c2150408f7938d9936f2fede0be9d54fcded04',
        '0x956c75a3f42cc0d4fab9180b5700adb69cf8d1e7c58b291d35237117403bfe11',
        '0xcf2fb5fd35e534c77ca7b14914fc80741241437f9c2e324ac8373fd687b8f7ad',
      ]
    );

    await securitizationPoolContract
      .connect(poolCreatorSigner)
      .grantRole(await securitizationPoolContract.ORIGINATOR_ROLE(), originatorSigner.address);
    await loanAssetTokenContract.connect(originatorSigner).setApprovalForAll(securitizationPoolContract.address, true);
    await securitizationPoolContract
      .connect(originatorSigner)
      .collectAssets(loanAssetTokenContract.address, originatorSigner.address, [
        '68573754499950287139712752973314570379296281614027304774473155089973215579519',
        '39888941571860786265340489425254739441353721495892246225639551495367240395819',
        '1814376911303643558138225754850733580633933175059860852674847724414762062843',
        '70176507447801386923525276155217627110933503150876918878877518382174110024632',
        '13184540353607289166840638357985936899957388517674636340327471056718548051675',
        '98118009304676984946015583983417753948122531080421117734495028460749452488367',
      ]);

    // Init JOT sale
    const jotCap = '10000000000000000000';
    const isLongSaleTGEJOT = true;
    const now = dayjs().unix();
    const setUpTGEJOTTransaction = await securitizationManagerContract.connect(poolCreatorSigner).setUpTGEForJOT(poolCreatorSigner.address, securitizationPoolAddress, [1, 2], isLongSaleTGEJOT, {
      openingTime: now,
      closingTime: now + ONE_DAY,
      rate: 10000,
      cap: jotCap,
    }, 'Ticker');
    const setUpTGEJOTReceipt = await setUpTGEJOTTransaction.wait();
    const [jotTGEAddress] = setUpTGEJOTReceipt.events.find(e => e.event == 'NewTGECreated').args;
    const mintedNormalTGEContract = await ethers.getContractAt('MintedNormalTGE', jotTGEAddress);

    // Init SOT sale
    const sotCap = '10000000000000000000';
    const isLongSaleTGESOT = true;
    const setUpTGESOTTransaction = await securitizationManagerContract.connect(poolCreatorSigner).setUpTGEForSOT(poolCreatorSigner.address, securitizationPoolAddress, [0, 2], isLongSaleTGESOT, 10000, 90000, 86400, 10000, {
      openingTime: now,
      closingTime: now + 2 * ONE_DAY,
      rate: 10000,
      cap: sotCap,
    }, 'Ticker');
    const setUpTGESOTReceipt = await setUpTGESOTTransaction.wait();
    const [sotTGEAddress] = setUpTGESOTReceipt.events.find(e => e.event == 'NewTGECreated').args;
    const mintedIncreasingInterestTGEContract = await ethers.getContractAt('MintedIncreasingInterestTGE', sotTGEAddress);

    // Gain UID
    const UID_TYPE = 0
    const chainId = await getChainId();
    const expiredAt = now + ONE_DAY;
    const nonce = 0;
    const ethRequired = ethers.utils.parseEther("0.00083")

    const uidMintMessage = presignedMintMessage(lenderSigner.address, UID_TYPE, expiredAt, uniqueIdentityContract.address, nonce, chainId)
    const signature = await untangledAdminSigner.signMessage(uidMintMessage)
    await uniqueIdentityContract.connect(lenderSigner).mint(UID_TYPE, expiredAt, signature, { value: ethRequired });

    // Buy JOT Token
    const stableCoinAmountToBuyJOT = BigNumber.from(1).mul(DECIMAL); // $1
    await stableCoin.connect(lenderSigner).approve(mintedNormalTGEContract.address, stableCoinAmountToBuyJOT)
    await securitizationManagerContract.connect(lenderSigner).buyTokens(mintedNormalTGEContract.address, stableCoinAmountToBuyJOT)

    // Buy SOT Token
    const stableCoinAmountToBuySOT = BigNumber.from(1).mul(DECIMAL); // $1
    await stableCoin.connect(lenderSigner).approve(mintedIncreasingInterestTGEContract.address, stableCoinAmountToBuySOT)
    await securitizationManagerContract.connect(lenderSigner).buyTokens(mintedIncreasingInterestTGEContract.address, stableCoinAmountToBuySOT)

    // Start cycle
    await time.increase(ONE_DAY*5)
    // Finalize jot sale
    await mintedNormalTGEContract.connect(poolCreatorSigner).finalize(false, poolCreatorSigner.address);
    // Finalize sot sale
    await mintedIncreasingInterestTGEContract.connect(poolCreatorSigner).finalize(false, poolCreatorSigner.address);

    const interest = await mintedIncreasingInterestTGEContract.getCurrentInterest();
    console.log(interest);
    await securitizationPoolContract.connect(poolCreatorSigner).startCycle(ONE_DAY*60, 100, interest, now);

    // Repay loan
    await stableCoin.connect(originatorSigner).approve(loanRepaymentRouterContract.address, "100000000000000000000")

    await loanRepaymentRouterContract.connect(originatorSigner).repayInBatch(
      [
        '0x979b5e9fab60f9433bf1aa924d2d09636ae0f5c10e2c6a8a58fe441cd1414d7f',
        '0x583057423a4229bfb018a7cf05140649f0f4dc560f4dce8f46f386b1a6df2c2b',
        '0x0402e6a3fda04c590f0de9573cb886b909202a646e29b1505347dbdad71993fb',
        '0x9b267ee2976a46d4c8d37d7b452b40fe1d524430d3e8bc19a2106cadf20d03b8',
        '0x1d262f75bc61c2035fe711930f7accf63a4906996cc18c57039f881f835a26db',
        '0xd8ecd3440fa68d7d87f9b3d22ad267ba4e42aad35f07f0112b72bef1b3442eaf',
      ],
      [
        '470000000000000000',
        '380000000000000000',
        '360000000000000000',
        '10000000000000000',
        '10000000000000000',
        '400000000000000000',
      ],
      stableCoin.address,
    );
    // Conclude loan
    const jotAddress = await securitizationPoolContract.jotToken();
    const sotAddress = await securitizationPoolContract.sotToken();
    const jotTokenContract = await ethers.getContractAt('NoteToken', jotAddress);
    const sotTokenContract = await ethers.getContractAt('NoteToken', sotAddress);
    // const riskScore = await securitizationPoolContract.riskScores(5)
    // console.log(riskScore);

    // const length = await securitizationPoolContract.getRiskScoresLength();
    await jotTokenContract.connect(lenderSigner).approve(distributionTranche.address, '100')
    await distributionOperator.connect(lenderSigner).makeRedeemRequestAndRedeem(securitizationPoolContract.address, jotTokenContract.address, '100')

        // await sotTokenContract.connect(lenderSigner).approve(distributionTranche.address, '100' )
        // await distributionOperator.connect(lenderSigner).makeRedeemRequestAndRedeem(securitizationPoolContract.address, sotTokenContract.address, '100')
  });
});
