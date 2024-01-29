const { ethers, upgrades } = require('hardhat');
const { deployments } = require('hardhat');
const _ = require('lodash');
const dayjs = require('dayjs');
const { expect } = require('chai');
const { time } = require('@nomicfoundation/hardhat-network-helpers');
const { arrayify } = require('@ethersproject/bytes');
const { BigNumber } = ethers;
const { parseEther, parseUnits, formatEther, formatBytes32String, keccak256, solidityPack } = ethers.utils;
const { SUPER_ADMIN } = require('./constants.js');
const { presignedMintMessage } = require('./shared/uid-helper.js');

const { unlimitedAllowance, ZERO_ADDRESS } = require('./utils.js');
const { setup } = require('./setup.js');

describe('UniqueIdentity', () => {
    let uniqueIdentity;

    // Wallets
    let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer;
    before('create fixture', async () => {
        [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer] =
            await ethers.getSigners();

        ({ uniqueIdentity } = await setup());
    });

    describe('#mint', async () => {
        it('should mint successfully', async () => {
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

            const balanceOfLender = await uniqueIdentity.balanceOf(lenderSigner.address, '0');
            expect(balanceOfLender).equal(1);
        });

        it('should mintTo successfully', async () => {
            // Gain UID
            const UID_TYPE = 0;
            const chainId = await getChainId();
            const expiredAt = dayjs().unix() + 86400 * 1000;
            const nonce = 0;
            const ethRequired = parseEther('0.00083');

            const uidMintToMessage = keccak256(
                solidityPack(
                    ['address', 'address', 'uint256', 'uint256', 'address', 'uint256', 'uint256'],
                    [
                        borrowerSigner.address,
                        borrowerSigner.address,
                        UID_TYPE,
                        expiredAt,
                        uniqueIdentity.address,
                        nonce,
                        chainId,
                    ]
                )
            );

            const signature = await untangledAdminSigner.signMessage(arrayify(uidMintToMessage));

            await uniqueIdentity
                .connect(borrowerSigner)
                .mintTo(borrowerSigner.address, UID_TYPE, expiredAt, signature, { value: ethRequired });

            const balanceOfBorrower = await uniqueIdentity.balanceOf(borrowerSigner.address, '0');
            expect(balanceOfBorrower).equal(1);
        });
    });

    describe('Get info', async () => {
        it('#name', async () => {
            const result = await uniqueIdentity.name();

            expect(result).equal('Unique Identity');
        });

        it('#symbol', async () => {
            const result = await uniqueIdentity.symbol();

            expect(result).equal('UID');
        });
    });

    describe('#burn', async () => {
        it('Cannot transfer rather than mint or burn', async () => {
            const UID_TYPE = 0;

            await expect(
                uniqueIdentity
                    .connect(lenderSigner)
                    ['safeTransferFrom(address,address,uint256,uint256,bytes)'](
                        lenderSigner.address,
                        borrowerSigner.address,
                        UID_TYPE,
                        1,
                        '0x1234'
                    )
            ).to.be.revertedWith(`Only mint or burn transfers are allowed`);
        });

        it('should burn successfully', async () => {
            const UID_TYPE = 0;
            const chainId = await getChainId();
            const expiredAt = dayjs().unix() + 86400 * 1000;
            const nonce = 1;
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

            const result = await uniqueIdentity.burn(lenderSigner.address, UID_TYPE, expiredAt, signature);

            const balanceOfLender = await uniqueIdentity.balanceOf(lenderSigner.address, '0');
            expect(balanceOfLender).equal(0);
        });
    });

    describe('#burnFrom', async () => {
        it('Only SUPPER ADMIN can burnFrom', async () => {
            const UID_TYPE = 0;
            await expect(
                uniqueIdentity.connect(lenderSigner).burnFrom(borrowerSigner.address, UID_TYPE)
            ).to.be.revertedWith(
                `AccessControl: account ${lenderSigner.address.toLowerCase()} is missing role 0xd980155b32cf66e6af51e0972d64b9d5efe0e6f237dfaa4bdc83f990dd79e9c8`
            );
        });

        it('should burn successfully', async () => {
            const UID_TYPE = 0;
            await uniqueIdentity.burnFrom(borrowerSigner.address, UID_TYPE);

            expect(await uniqueIdentity.hasRole(SUPER_ADMIN, untangledAdminSigner.address)).to.equal(true);
            const balanceOfLender = await uniqueIdentity.balanceOf(borrowerSigner.address, '0');
            expect(balanceOfLender).equal(0);
        });

        it('should add new superadmin successfully', async () => {
            await uniqueIdentity.addSuperAdmin(borrowerSigner.address);

            expect(await uniqueIdentity.hasRole(SUPER_ADMIN, borrowerSigner.address)).to.equal(true);
        });
    });
});
