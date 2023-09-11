const { ethers, upgrades } = require('hardhat');
const { deployments } = require('hardhat');
const { expect } = require('../shared/expect.js');

const { parseEther, defaultAbiCoder } = ethers.utils;

const abiCoder = new ethers.utils.AbiCoder();

describe('CCIPReceiver', () => {
  let untangedReceiver;
  let untangledBridgeRouter;

  // Wallets
  let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner;
  before('create fixture', async () => {
    [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner] =
      await ethers.getSigners();

    const UntangledBridgeRouter = await ethers.getContractFactory('UntangledBridgeRouter');
    untangledBridgeRouter = await upgrades.deployProxy(UntangledBridgeRouter, [untangledAdminSigner.address]);

    const UntangedReceiver = await ethers.getContractFactory('UntangedReceiver');
    untangedReceiver = await upgrades.deployProxy(UntangedReceiver, [
      untangledAdminSigner.address,
      untangledBridgeRouter.address,
    ]);

    const CCIP_RECEIVER_ROLE = await untangledBridgeRouter.CCIP_RECEIVER_ROLE();
    await untangledBridgeRouter.grantRole(CCIP_RECEIVER_ROLE, untangedReceiver.address);
  });

  describe('#Receiver', async () => {
    it('should receive message successfully', async () => {
      const userData = abiCoder.encode(['address', 'uint256'], [lenderSigner.address, parseEther('100')]);
      const sender = abiCoder.encode(['address'], [lenderSigner.address]);

      const data = defaultAbiCoder.encode(['uint8', 'bytes'], [0, userData]);

      await untangedReceiver.connect(untangledAdminSigner).ccipReceive({
        messageId: ethers.constants.HashZero,
        sourceChainSelector: 1234,
        sender: sender,
        data: data,
        destTokenAmounts: [],
      });

      const result = await untangedReceiver.getLastReceivedMessageDetails();

      expect(result.messageId).to.equal(ethers.constants.HashZero);
      expect(result.command.messageType).to.equal(0);
      expect(result.command.data).to.equal(userData);

      const messageDataGroup = await untangedReceiver.messageDataGroup(ethers.constants.HashZero);

      expect(messageDataGroup.messageType).to.equal(0);
      expect(messageDataGroup.data).to.equal(userData);
    });
  });

  describe('#Upgrade Proxy', async () => {
    it('Upgrade successfully', async () => {
      const UntangledReceiverV2 = await ethers.getContractFactory('UntangledReceiverV2');
      const untangledReceiverV2 = await upgrades.upgradeProxy(untangedReceiver.address, UntangledReceiverV2);

      expect(untangledReceiverV2.address).to.equal(untangedReceiver.address);

      const hello = await untangledReceiverV2.hello();
      expect(hello).to.equal('Hello world');
    });
  });
});
