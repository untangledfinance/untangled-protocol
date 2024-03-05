const { ethers, upgrades } = require('hardhat');
const { deployments } = require('hardhat');
const _ = require('lodash');
const dayjs = require('dayjs');
const { expect } = require('chai');
const { time } = require('@nomicfoundation/hardhat-network-helpers');

const { BigNumber } = ethers;
const { parseEther, parseUnits, formatEther, formatBytes32String, keccak256, solidityPack } = ethers.utils;

const { unlimitedAllowance, ZERO_ADDRESS } = require('./utils.js');
const { setup } = require('./setup.js');
const { presignedMintMessage } = require('./shared/uid-helper.js');
const {ZAPPER_ROLE} = require('./constants')

describe('Go', () => {
  let go;
  let uniqueIdentity;

  // Wallets
  let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer;
  before('create fixture', async () => {
    [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer] =
      await ethers.getSigners();

    ({ go, uniqueIdentity } = await setup());

    // Gain UID
    const UID_TYPE = 0;
    const chainId = await getChainId();
    const expiredAt = dayjs().unix() + 86400 * 1000;
    const nonce = 0;
    const ethRequired = parseEther('0.00083');

    const uidMintMessage = presignedMintMessage(
      lenderSigner.address,
      UID_TYPE,
      expiredAt,
      uniqueIdentity.address,
      nonce,
      chainId
    );
    const signature = await untangledAdminSigner.signMessage(uidMintMessage);
    await uniqueIdentity.connect(lenderSigner).mint(UID_TYPE, expiredAt, signature, { value: ethRequired });
  });

  describe('#performUpgrade', async () => {
    it('should performUpgrade', async () => {
      await go.performUpgrade();

      const result = await go.ID_TYPE_10();
      expect(result).equal(10);
    });
  });

  describe('#initZapperRole', async () => {
    it('should initZapperRole failed if not admin', async () => {
      await expect(go.connect(lenderSigner).initZapperRole()).to.be.revertedWith(
        `Must have admin role to perform this action`
      );
    });

    it('should initZapperRole', async () => {
      await go.initZapperRole();
    });
  });

  describe('#go', async () => {
    it('should go', async () => {
      const result = await go.go(untangledAdminSigner.address);

      expect(result).equal(false);
    });
  });

  describe('#getAllIdTypes', async () => {
    it('should getAllIdTypes', async () => {
      const result = await go.getAllIdTypes();

      expect(result.map((x) => x.toNumber())).to.deep.equal(
        Array(result.length)
          .fill(0)
          .map((x, i) => i)
      );
    });
  });

  describe('#goOnlyIdTypes', async () => {
    it('should admin return true', async () => {
      // const ZAPPER_ROLE = await go.ZAPPER_ROLE();
      await go.grantRole(ZAPPER_ROLE, untangledAdminSigner.address);
      const result = await go.goOnlyIdTypes(untangledAdminSigner.address, []);

      expect(result).equal(true);
    });

    it('should lender return true', async () => {
      const result = await go.goOnlyIdTypes(lenderSigner.address, [0]);

      expect(result).equal(true);
    });

    it('should borrower return false', async () => {
      const result = await go.goOnlyIdTypes(borrowerSigner.address, [0]);

      expect(result).equal(false);
    });

    it('should borrower return false', async () => {
      const result = await go.connect(lenderSigner).goOnlyIdTypes(borrowerSigner.address, [0]);

      expect(result).equal(false);
    });
  });
});
