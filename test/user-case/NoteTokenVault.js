const { ethers, getChainId } = require('hardhat');
const { expect } = require('chai');
const UntangledProtocol = require('../shared/untangled-protocol');
const { parseEther } = ethers.utils;

const dayjs = require('dayjs');
const { time } = require('@nomicfoundation/hardhat-network-helpers');
const { setup } = require('../setup');
const {
    presignedCancelRedeemOrderMessage,
    presignedRedeemOrderMessage,
} = require('../shared/uid-helper');
const { POOL_ADMIN_ROLE, ORIGINATOR_ROLE, BACKEND_ADMIN, SIGNER_ROLE } = require('../constants.js');
const { impersonateAccount, setBalance } = require('@nomicfoundation/hardhat-network-helpers');
const { getPoolByAddress, unlimitedAllowance } = require('../utils');
const { SaleType } = require('../shared/constants.js');
const { RISK_SCORES } = require('../shared/constants');

const ONE_DAY_IN_SECONDS = 86400;

describe('NoteTokenVault', () => {
    let stableCoin;
    let securitizationManager;
    let uniqueIdentity;
    let jotContract;
    let sotContract;
    let securitizationPoolContract;
    let mintedNormalTGEContract;
    let mintedIncreasingInterestTGEContract;
    let loanKernel;
    let noteTokenVault;
    let chainId;
    let securitizationPoolValueService;
    let untangledProtocol;

    // Wallets
    let untangledAdminSigner,
        poolCreatorSigner,
        poolACreator,
        originatorSigner,
        lenderSignerA,
        lenderSignerB,
        lenderSignerC,
        backendAdminSigner,
        cancelOrderAdminSigner,
        redeemOrderAdminSigner,
        relayer;

    const stableCoinAmountToBuyJOT = parseEther('1');
    const stableCoinAmountToBuySOT = parseEther('1');

    before('create fixture', async () => {
        // Init wallets
        [
            untangledAdminSigner,
            poolCreatorSigner,
            poolACreator,
            originatorSigner,
            lenderSignerA,
            lenderSignerB,
            lenderSignerC,
            backendAdminSigner,
            cancelOrderAdminSigner,
            redeemOrderAdminSigner,
            relayer,
        ] = await ethers.getSigners();

        // Init contracts
        const contracts = await setup();
        untangledProtocol = UntangledProtocol.bind(contracts);
        ({
            stableCoin,
            uniqueIdentity,
            securitizationManager,
            loanKernel,
            noteTokenVault,
            securitizationPoolValueService,
        } = contracts);

        await securitizationManager.grantRole(POOL_ADMIN_ROLE, poolCreatorSigner.address);
        // Create new pool
        const poolParams = {
            currency: 'cUSD',
            minFirstLossCushion: 10,
            validatorRequired: true,
            debtCeiling: 1000,
        };
        const { riskScoreA, riskScoreB, riskScoreC, riskScoreD, riskScoreE, riskScoreF } = RISK_SCORES;
        const riskScores = [riskScoreA, riskScoreB, riskScoreC, riskScoreD, riskScoreE, riskScoreF];

        // Init JOT sale
        const jotCap = parseEther('1000'); // $1000
        const isLongSaleTGEJOT = true;
        const now = dayjs().unix();
        const initialJotAmount = stableCoinAmountToBuyJOT;
        const jotInfo = {
            issuerTokenController: untangledAdminSigner.address,
            minBidAmount: parseEther('1'),
            saleType: SaleType.NORMAL_SALE,
            longSale: true,
            ticker: 'Ticker',
            openingTime: now,
            closingTime: now + ONE_DAY_IN_SECONDS,
            rate: 10000,
            cap: jotCap,
            initialJOTAmount: initialJotAmount,
        };

        // Init SOT sale
        const sotCap = parseEther('1000'); // $1000
        const sotInfo = {
            issuerTokenController: untangledAdminSigner.address,
            saleType: SaleType.MINTED_INCREASING_INTEREST,
            minBidAmount: parseEther('1'),
            openingTime: now,
            closingTime: now + 2* ONE_DAY_IN_SECONDS,
            rate: 10000,
            cap: sotCap,
            initialInterest: 10000,
            finalInterest: 90000,
            timeInterval: 86400,
            amountChangeEachInterval: 10000,
            ticker: 'Ticker',
        };
        const [poolAddress, sotCreated, jotCreated] = await untangledProtocol.createFullPool(poolCreatorSigner, poolParams, riskScores, sotInfo, jotInfo);
        securitizationPoolContract = await getPoolByAddress(poolAddress);
        mintedIncreasingInterestTGEContract = await ethers.getContractAt('MintedIncreasingInterestTGE', sotCreated.sotTGEAddress);
        mintedNormalTGEContract = await ethers.getContractAt('MintedNormalTGE', jotCreated.jotTGEAddress);
        sotContract = await ethers.getContractAt('NoteToken', sotCreated.sotTokenAddress);
        jotContract = await ethers.getContractAt('NoteToken', jotCreated.jotTokenAddress);

        // Grant role originator
        await securitizationPoolContract
            .connect(poolCreatorSigner)
            .grantRole(ORIGINATOR_ROLE, originatorSigner.address);


        // Lender gain UID
        chainId = await getChainId();
        await untangledProtocol.mintUID(lenderSignerA);
        await untangledProtocol.mintUID(lenderSignerB);
        await untangledProtocol.mintUID(lenderSignerC);
        // Faucet stable coin to lender/investor
        await stableCoin.transfer(lenderSignerA.address, parseEther('10000')); // $10k
        await stableCoin.transfer(lenderSignerB.address, parseEther('10000')); // $10k
        await stableCoin.transfer(lenderSignerC.address, parseEther('10000')); // $10k
    });

    describe('Redeem Orders', () => {
        before('Lender A buy JOT and SOT', async () => {
            // Lender buys JOT Token
            await untangledProtocol.buyToken(lenderSignerA, mintedNormalTGEContract.address, stableCoinAmountToBuyJOT);
            // Lender try to buy SOT with amount violates min first loss
            await untangledProtocol.buyToken(lenderSignerA, mintedIncreasingInterestTGEContract.address, stableCoinAmountToBuySOT);
        });
        before('Lender B buy JOT and SOT', async () => {
            // Lender buys JOT Token
            await untangledProtocol.buyToken(lenderSignerB, mintedNormalTGEContract.address, stableCoinAmountToBuyJOT);
            // Lender try to buy SOT with amount violates min first loss
            await untangledProtocol.buyToken(lenderSignerB, mintedIncreasingInterestTGEContract.address, stableCoinAmountToBuySOT);
        });
        describe('Redeem Order', () => {
            it('Investor A should make redeem order for 1 JOT', async () => {
                await noteTokenVault
                    .connect(untangledAdminSigner)
                    .grantRole(SIGNER_ROLE, redeemOrderAdminSigner.address);
                await jotContract.connect(lenderSignerA).approve(noteTokenVault.address, unlimitedAllowance);

                const redeemParam = {
                    pool: securitizationPoolContract.address,
                    noteTokenAddress: jotContract.address,
                    noteTokenRedeemAmount: parseEther('1'),
                };
                const redeemOrderMessage = presignedRedeemOrderMessage(
                    lenderSignerA.address,
                    redeemParam.pool,
                    redeemParam.noteTokenAddress,
                    redeemParam.noteTokenRedeemAmount,
                    chainId
                );
                const redeemSignature = await redeemOrderAdminSigner.signMessage(redeemOrderMessage);

                await expect(noteTokenVault.connect(lenderSignerA).redeemOrder(redeemParam, redeemSignature))
                    .to.emit(noteTokenVault, 'RedeemOrder')
                    .withArgs(
                        securitizationPoolContract.address,
                        jotContract.address,
                        lenderSignerA.address,
                        parseEther('1'),
                        parseEther('1')
                    );
                const totalJOTRedeem = await noteTokenVault.totalJOTRedeem(securitizationPoolContract.address);
                expect(totalJOTRedeem).to.equal(parseEther('1'));
                const jotRedeemOrderLenderA = await noteTokenVault.userRedeemJOTOrder(
                    securitizationPoolContract.address,
                    lenderSignerA.address
                );
                expect(jotRedeemOrderLenderA).to.equal(parseEther('1'));
            });
            it('should revert if created redeem order for JOT again', async () => {
                const redeemParam = {
                    pool: securitizationPoolContract.address,
                    noteTokenAddress: jotContract.address,
                    noteTokenRedeemAmount: parseEther('1'),
                };
                const redeemOrderMessage = presignedRedeemOrderMessage(
                    lenderSignerA.address,
                    redeemParam.pool,
                    redeemParam.noteTokenAddress,
                    redeemParam.noteTokenRedeemAmount,
                    chainId
                );
                const redeemSignature = await redeemOrderAdminSigner.signMessage(redeemOrderMessage);
                await expect(
                    noteTokenVault.connect(lenderSignerA).redeemOrder(redeemParam, redeemSignature)
                ).to.be.revertedWith('NoteTokenVault: User already created redeem order');
            });
            it('Investor B should make redeem order for 1 JOT', async () => {
                const jotLenderBBalance = await jotContract.balanceOf(lenderSignerB.address); // 1 jot
                await jotContract.connect(lenderSignerB).approve(noteTokenVault.address, jotLenderBBalance);

                const redeemParam = {
                    pool: securitizationPoolContract.address,
                    noteTokenAddress: jotContract.address,
                    noteTokenRedeemAmount: parseEther('1'),
                };
                const redeemOrderMessage = presignedRedeemOrderMessage(
                    lenderSignerB.address,
                    redeemParam.pool,
                    redeemParam.noteTokenAddress,
                    redeemParam.noteTokenRedeemAmount,
                    chainId
                );
                const redeemSignature = await redeemOrderAdminSigner.signMessage(redeemOrderMessage);
                await noteTokenVault.connect(lenderSignerB).redeemOrder(redeemParam, redeemSignature);

                const totalJOTRedeem = await noteTokenVault.totalJOTRedeem(securitizationPoolContract.address);
                expect(totalJOTRedeem).to.equal(parseEther('2'));
                const jotRedeemOrderLenderB = await noteTokenVault.userRedeemJOTOrder(
                    securitizationPoolContract.address,
                    lenderSignerB.address
                );
                expect(jotRedeemOrderLenderB).to.equal(parseEther('1'));
            });
            it('Investor A should make redeem order for 1 SOT', async () => {
                await sotContract.connect(lenderSignerA).approve(noteTokenVault.address, unlimitedAllowance);

                const redeemParam = {
                    pool: securitizationPoolContract.address,
                    noteTokenAddress: sotContract.address,
                    noteTokenRedeemAmount: parseEther('1'),
                };
                const redeemOrderMessage = presignedRedeemOrderMessage(
                    lenderSignerA.address,
                    redeemParam.pool,
                    redeemParam.noteTokenAddress,
                    redeemParam.noteTokenRedeemAmount,
                    chainId
                );
                const redeemSignature = await redeemOrderAdminSigner.signMessage(redeemOrderMessage);
                await expect(noteTokenVault.connect(lenderSignerA).redeemOrder(redeemParam, redeemSignature))
                    .to.emit(noteTokenVault, 'RedeemOrder')
                    .withArgs(
                        securitizationPoolContract.address,
                        sotContract.address,
                        lenderSignerA.address,
                        parseEther('1'),
                        parseEther('1')
                    );
                const totalSOTRedeem = await noteTokenVault.totalSOTRedeem(securitizationPoolContract.address);
                expect(totalSOTRedeem).to.equal(parseEther('1'));
                const sotRedeemOrderLenderA = await noteTokenVault.userRedeemSOTOrder(
                    securitizationPoolContract.address,
                    lenderSignerA.address
                );
                expect(sotRedeemOrderLenderA).to.equal(parseEther('1'));
            });
            it('should revert if created redeem order for SOT again', async () => {
                const redeemParam = {
                    pool: securitizationPoolContract.address,
                    noteTokenAddress: sotContract.address,
                    noteTokenRedeemAmount: parseEther('1'),
                };
                const redeemOrderMessage = presignedRedeemOrderMessage(
                    lenderSignerA.address,
                    redeemParam.pool,
                    redeemParam.noteTokenAddress,
                    redeemParam.noteTokenRedeemAmount,
                    chainId
                );
                const redeemSignature = await redeemOrderAdminSigner.signMessage(redeemOrderMessage);
                await expect(
                    noteTokenVault.connect(lenderSignerA).redeemOrder(redeemParam, redeemSignature)
                ).to.be.revertedWith('NoteTokenVault: User already created redeem order');
            });
            it('Investor B should make redeem order for 1 SOT', async () => {
                const sotLenderBBalance = await sotContract.balanceOf(lenderSignerB.address); // 1 sot
                await sotContract.connect(lenderSignerB).approve(noteTokenVault.address, sotLenderBBalance);

                const redeemParam = {
                    pool: securitizationPoolContract.address,
                    noteTokenAddress: sotContract.address,
                    noteTokenRedeemAmount: parseEther('1'),
                };
                const redeemOrderMessage = presignedRedeemOrderMessage(
                    lenderSignerB.address,
                    redeemParam.pool,
                    redeemParam.noteTokenAddress,
                    redeemParam.noteTokenRedeemAmount,
                    chainId
                );
                const redeemSignature = await redeemOrderAdminSigner.signMessage(redeemOrderMessage);
                await noteTokenVault.connect(lenderSignerB).redeemOrder(redeemParam, redeemSignature);

                const totalSOTRedeem = await noteTokenVault.totalSOTRedeem(securitizationPoolContract.address);
                expect(totalSOTRedeem).to.equal(parseEther('2'));
                const sotRedeemOrderLenderB = await noteTokenVault.userRedeemSOTOrder(
                    securitizationPoolContract.address,
                    lenderSignerB.address
                );
                expect(sotRedeemOrderLenderB).to.equal(parseEther('1'));
            });
            it('only pool creator can disable redeem request', async () => {
                await expect(
                    noteTokenVault.connect(lenderSignerA).setRedeemDisabled(securitizationPoolContract.address, true)
                ).to.be.revertedWith(
                    `AccessControl: account ${lenderSignerA.address.toLowerCase()} is missing role 0x48c56c0d6590b6240b1a1005717522dced5c82a200c197c7d7ad7bf3660f4194`
                );
                await noteTokenVault.connect(untangledAdminSigner).grantRole(BACKEND_ADMIN, backendAdminSigner.address);
                await noteTokenVault
                    .connect(backendAdminSigner)
                    .setRedeemDisabled(securitizationPoolContract.address, true);
            });
            it('should revert if request redemption when redeem disabled', async () => {
                let redeemParam = {
                    pool: securitizationPoolContract.address,
                    noteTokenAddress: jotContract.address,
                    noteTokenRedeemAmount: parseEther('1'),
                };
                let redeemOrderMessage = presignedRedeemOrderMessage(
                    lenderSignerB.address,
                    redeemParam.pool,
                    redeemParam.noteTokenAddress,
                    redeemParam.noteTokenRedeemAmount,
                    chainId
                );
                let redeemSignature = await redeemOrderAdminSigner.signMessage(redeemOrderMessage);
                await expect(
                    noteTokenVault.connect(lenderSignerB).redeemOrder(redeemParam, redeemSignature)
                ).to.be.revertedWith('redeem-not-allowed');

                redeemParam = {
                    pool: securitizationPoolContract.address,
                    noteTokenAddress: sotContract.address,
                    noteTokenRedeemAmount: parseEther('1'),
                };
                redeemOrderMessage = presignedRedeemOrderMessage(
                    lenderSignerB.address,
                    redeemParam.pool,
                    redeemParam.noteTokenAddress,
                    redeemParam.noteTokenRedeemAmount,
                    chainId
                );
                redeemSignature = await redeemOrderAdminSigner.signMessage(redeemOrderMessage);
                await expect(
                    noteTokenVault.connect(lenderSignerB).redeemOrder(redeemParam, redeemSignature)
                ).to.be.revertedWith('redeem-not-allowed');
            });

            it('should revert if buy note token when redeem disabled', async () => {
                await expect(
                    untangledProtocol.buyToken(lenderSignerA, mintedNormalTGEContract.address, stableCoinAmountToBuyJOT)
                ).to.be.revertedWith('SM: Buy token paused');
                // Lender try to buy SOT with amount violates min first loss
                expect(
                    untangledProtocol.buyToken(lenderSignerA, mintedIncreasingInterestTGEContract.address, stableCoinAmountToBuySOT)
                ).to.be.revertedWith('SM: Buy token paused');
            });
            it('should revert if drawdown when redeem disabled', async () => {
                await impersonateAccount(loanKernel.address);
                await setBalance(loanKernel.address, ethers.utils.parseEther('1'));
                const signer = await ethers.getSigner(loanKernel.address);
                await expect(
                    securitizationPoolContract.connect(signer).withdraw(originatorSigner.address, parseEther('0.5'))
                ).to.be.revertedWith('SecuritizationPool: withdraw paused');
            });
            it('enable redeem order', async () => {
                await noteTokenVault
                    .connect(backendAdminSigner)
                    .setRedeemDisabled(securitizationPoolContract.address, false);
            });
            it('Investor A should change redeem order for 1 JOT', async () => {
                const redeemParam = {
                    pool: securitizationPoolContract.address,
                    noteTokenAddress: jotContract.address,
                    noteTokenRedeemAmount: parseEther('1'),
                };
                const redeemOrderMessage = presignedRedeemOrderMessage(
                    lenderSignerA.address,
                    redeemParam.pool,
                    redeemParam.noteTokenAddress,
                    redeemParam.noteTokenRedeemAmount,
                    chainId
                );
                const redeemSignature = await redeemOrderAdminSigner.signMessage(redeemOrderMessage);
                await expect(
                    noteTokenVault.connect(lenderSignerA).redeemOrder(redeemParam, redeemSignature)
                ).to.be.revertedWith('NoteTokenVault: User already created redeem order');
            });
            it('Investor A change redeem order for 1 SOT', async () => {
                const redeemParam = {
                    pool: securitizationPoolContract.address,
                    noteTokenAddress: sotContract.address,
                    noteTokenRedeemAmount: parseEther('1'),
                };
                const redeemOrderMessage = presignedRedeemOrderMessage(
                    lenderSignerA.address,
                    redeemParam.pool,
                    redeemParam.noteTokenAddress,
                    redeemParam.noteTokenRedeemAmount,
                    chainId
                );
                const redeemSignature = await redeemOrderAdminSigner.signMessage(redeemOrderMessage);
                await expect(
                    noteTokenVault.connect(lenderSignerA).redeemOrder(redeemParam, redeemSignature)
                ).to.be.revertedWith('NoteTokenVault: User already created redeem order');
            });
        });

        describe('Cancel Order', () => {
            before('Lender C buy JOT and SOT', async () => {
                // Lender buys JOT Token
                await  untangledProtocol.buyToken(lenderSignerC, mintedNormalTGEContract.address, stableCoinAmountToBuyJOT)
                // Lender try to buy SOT with amount violates min first loss
                await untangledProtocol.buyToken(
                    lenderSignerC,
                    mintedIncreasingInterestTGEContract.address,
                    stableCoinAmountToBuySOT
                );
            });
            before('Investor C create redeem order for SOT and JOT', async () => {
                await jotContract.connect(lenderSignerC).approve(noteTokenVault.address, unlimitedAllowance);

                let redeemParam = {
                    pool: securitizationPoolContract.address,
                    noteTokenAddress: jotContract.address,
                    noteTokenRedeemAmount: parseEther('1'),
                };
                let redeemOrderMessage = presignedRedeemOrderMessage(
                    lenderSignerC.address,
                    redeemParam.pool,
                    redeemParam.noteTokenAddress,
                    redeemParam.noteTokenRedeemAmount,
                    chainId
                );
                let redeemSignature = await redeemOrderAdminSigner.signMessage(redeemOrderMessage);
                await noteTokenVault.connect(lenderSignerC).redeemOrder(redeemParam, redeemSignature);

                await sotContract.connect(lenderSignerC).approve(noteTokenVault.address, unlimitedAllowance);

                redeemParam = {
                    pool: securitizationPoolContract.address,
                    noteTokenAddress: sotContract.address,
                    noteTokenRedeemAmount: parseEther('1'),
                };
                redeemOrderMessage = presignedRedeemOrderMessage(
                    lenderSignerC.address,
                    redeemParam.pool,
                    redeemParam.noteTokenAddress,
                    redeemParam.noteTokenRedeemAmount,
                    chainId
                );
                redeemSignature = await redeemOrderAdminSigner.signMessage(redeemOrderMessage);
                await noteTokenVault.connect(lenderSignerC).redeemOrder(redeemParam, redeemSignature);
            });
            it('Should revert if invalid signer', async () => {
                const maxTimestamp = (await time.latest()) + ONE_DAY_IN_SECONDS;
                const nonce = 0;
                const cancelParam = {
                    pool: securitizationPoolContract.address,
                    noteTokenAddress: jotContract.address,
                    maxTimestamp: maxTimestamp,
                };
                const cancelOrderMessage = presignedCancelRedeemOrderMessage(
                    lenderSignerC.address,
                    securitizationPoolContract.address,
                    jotContract.address,
                    maxTimestamp,
                    nonce,
                    chainId
                );
                const cancelSignature = await untangledAdminSigner.signMessage(cancelOrderMessage);
                await expect(
                    noteTokenVault.connect(lenderSignerC).cancelOrder(cancelParam, cancelSignature)
                ).to.be.revertedWith('Invalid signer');
            });
            it('Should revert if maxTimestamp < block timestamp', async () => {
                const maxTimestamp = (await time.latest()) - 1; // maxTimestamp in the past
                const nonce = 0;
                const cancelParam = {
                    pool: securitizationPoolContract.address,
                    noteTokenAddress: jotContract.address,
                    maxTimestamp: maxTimestamp,
                };
                const cancelOrderMessage = presignedCancelRedeemOrderMessage(
                    lenderSignerC.address,
                    securitizationPoolContract.address,
                    jotContract.address,
                    maxTimestamp,
                    nonce,
                    chainId
                );
                const cancelSignature = await untangledAdminSigner.signMessage(cancelOrderMessage);
                // await noteTokenVault.connect(lenderSignerC).cancelOrder(cancelParam, cancelSignature)
                await expect(
                    noteTokenVault.connect(lenderSignerC).cancelOrder(cancelParam, cancelSignature)
                ).to.be.revertedWith('Cancel request has expired');
            });
            it('Investor C should cancel order for JOT successfully', async () => {
                await noteTokenVault
                    .connect(untangledAdminSigner)
                    .grantRole(SIGNER_ROLE, cancelOrderAdminSigner.address);
                const maxTimestamp = (await time.latest()) + ONE_DAY_IN_SECONDS;
                const nonce = 0;
                const cancelParam = {
                    pool: securitizationPoolContract.address,
                    noteTokenAddress: jotContract.address,
                    maxTimestamp: maxTimestamp,
                };
                const cancelOrderMessage = presignedCancelRedeemOrderMessage(
                    lenderSignerC.address,
                    securitizationPoolContract.address,
                    jotContract.address,
                    maxTimestamp,
                    nonce,
                    chainId
                );
                const cancelSignature = await cancelOrderAdminSigner.signMessage(cancelOrderMessage);
                await noteTokenVault.connect(lenderSignerC).cancelOrder(cancelParam, cancelSignature);
                const totalJOTRedeem = await noteTokenVault.totalJOTRedeem(securitizationPoolContract.address);
                expect(totalJOTRedeem).to.equal(parseEther('2'));
                const jotRedeemOrderLenderC = await noteTokenVault.userRedeemJOTOrder(
                    securitizationPoolContract.address,
                    lenderSignerC.address
                );
                expect(jotRedeemOrderLenderC).to.equal(parseEther('0'));
                const jotBalanceLenderC = await jotContract.balanceOf(lenderSignerC.address);
                expect(jotBalanceLenderC).to.equal(parseEther('1'));
            });
            it('Should revert if invalid nonce', async () => {
                const maxTimestamp = (await time.latest()) + ONE_DAY_IN_SECONDS;
                const nonce = 0;
                const cancelParam = {
                    pool: securitizationPoolContract.address,
                    noteTokenAddress: sotContract.address,
                    maxTimestamp: maxTimestamp,
                };
                const cancelOrderMessage = presignedCancelRedeemOrderMessage(
                    lenderSignerC.address,
                    securitizationPoolContract.address,
                    sotContract.address,
                    maxTimestamp,
                    nonce,
                    chainId
                );
                const cancelSignature = await cancelOrderAdminSigner.signMessage(cancelOrderMessage);
                await expect(
                    noteTokenVault.connect(lenderSignerC).cancelOrder(cancelParam, cancelSignature)
                ).to.be.revertedWith('Invalid signer');
            });
            it('Investor C should cancel order for SOT successfully', async () => {
                const maxTimestamp = (await time.latest()) + ONE_DAY_IN_SECONDS;
                const nonce = 1;
                const cancelParam = {
                    pool: securitizationPoolContract.address,
                    noteTokenAddress: sotContract.address,
                    maxTimestamp: maxTimestamp,
                };
                const cancelOrderMessage = presignedCancelRedeemOrderMessage(
                    lenderSignerC.address,
                    securitizationPoolContract.address,
                    sotContract.address,
                    maxTimestamp,
                    nonce,
                    chainId
                );
                const cancelSignature = await cancelOrderAdminSigner.signMessage(cancelOrderMessage);
                await noteTokenVault.connect(lenderSignerC).cancelOrder(cancelParam, cancelSignature);
                const totalSOTRedeem = await noteTokenVault.totalSOTRedeem(securitizationPoolContract.address);
                expect(totalSOTRedeem).to.equal(parseEther('2'));
                const sotRedeemOrderLenderC = await noteTokenVault.userRedeemSOTOrder(
                    securitizationPoolContract.address,
                    lenderSignerC.address
                );
                expect(sotRedeemOrderLenderC).to.equal(parseEther('0'));
                const sotBalanceLenderC = await sotContract.balanceOf(lenderSignerC.address);
                expect(sotBalanceLenderC).to.equal(parseEther('1'));
            });
        });

        describe('Disburse', () => {
            const maxReserveForJOTRedeem = parseEther('2.833333333333333333');
            it('SOT: should revert if not backend admin', async () => {
                await expect(
                    noteTokenVault
                        .connect(poolCreatorSigner)
                        .disburseAll(
                            securitizationPoolContract.address,
                            sotContract.address,
                            [lenderSignerA.address, lenderSignerB.address],
                            [parseEther('0.5'), parseEther('1')],
                            [parseEther('0.5'), parseEther('1')]
                        )
                ).to.be.revertedWith(
                    `AccessControl: account ${poolCreatorSigner.address.toLowerCase()} is missing role 0x48c56c0d6590b6240b1a1005717522dced5c82a200c197c7d7ad7bf3660f4194`
                );
            });
            it('should return max available reserve', async () => {
                const result = await securitizationPoolValueService.getMaxAvailableReserve(
                    securitizationPoolContract.address,
                    parseEther('1.5')
                );
                expect(result).to.deep.equal([
                    parseEther('4.333333333333333333'),
                    parseEther('1.5'),
                    maxReserveForJOTRedeem,
                ]);
            });

            it('SOT: should run successfully', async () => {
                await noteTokenVault
                    .connect(backendAdminSigner)
                    .preDistribute(
                        securitizationPoolContract.address,
                        parseEther('1.5'),
                        [sotContract.address],
                        [parseEther('1.5')]
                    );
                await expect(
                    noteTokenVault
                        .connect(backendAdminSigner)
                        .disburseAll(
                            securitizationPoolContract.address,
                            sotContract.address,
                            [lenderSignerA.address, lenderSignerB.address],
                            [parseEther('0.5'), parseEther('1')],
                            [parseEther('0.5'), parseEther('1')]
                        )
                )
                    .to.emit(noteTokenVault, 'DisburseOrder')
                    .withArgs(
                        securitizationPoolContract.address,
                        sotContract.address,
                        [lenderSignerA.address, lenderSignerB.address],
                        [parseEther('0.5'), parseEther('1')],
                        [parseEther('0.5'), parseEther('1')]
                    );
                const totalSOTRedeem = await noteTokenVault.totalSOTRedeem(securitizationPoolContract.address);
                expect(totalSOTRedeem).to.equal(parseEther('0.5'));
                const sotRedeemOrderLenderA = await noteTokenVault.userRedeemSOTOrder(
                    securitizationPoolContract.address,
                    lenderSignerA.address
                );
                expect(sotRedeemOrderLenderA).to.equal(parseEther('0.5'));
                const sotRedeemOrderLenderB = await noteTokenVault.userRedeemSOTOrder(
                    securitizationPoolContract.address,
                    lenderSignerB.address
                );
                expect(sotRedeemOrderLenderB).to.equal(parseEther('0'));
                const reserve = await securitizationPoolContract.reserve();
                expect(reserve).to.equal(parseEther('4.5')); // $3 SOT raised + $3 JOT raised - $1.5 redeemed
                const sotTGECurrencyRaised = await mintedIncreasingInterestTGEContract.currencyRaised();
                expect(sotTGECurrencyRaised).to.equal(parseEther('1.5'));
            });

            it('JOT: should revert if not backend admin', async () => {
                await expect(
                    noteTokenVault
                        .connect(poolCreatorSigner)
                        .disburseAll(
                            securitizationPoolContract.address,
                            jotContract.address,
                            [lenderSignerA.address, lenderSignerB.address],
                            [parseEther('0.5'), parseEther('1')],
                            [parseEther('0.5'), parseEther('1')]
                        )
                ).to.be.revertedWith(
                    `AccessControl: account ${poolCreatorSigner.address.toLowerCase()} is missing role 0x48c56c0d6590b6240b1a1005717522dced5c82a200c197c7d7ad7bf3660f4194`
                );
            });

            it('JOT: Investor C create JOT redeem order for 1 JOT again', async () => {
                let redeemParam = {
                    pool: securitizationPoolContract.address,
                    noteTokenAddress: jotContract.address,
                    noteTokenRedeemAmount: parseEther('1'),
                };
                let redeemOrderMessage = presignedRedeemOrderMessage(
                    lenderSignerC.address,
                    redeemParam.pool,
                    redeemParam.noteTokenAddress,
                    redeemParam.noteTokenRedeemAmount,
                    chainId
                );
                let redeemSignature = await redeemOrderAdminSigner.signMessage(redeemOrderMessage);
                await noteTokenVault.connect(lenderSignerC).redeemOrder(redeemParam, redeemSignature);

                await sotContract.connect(lenderSignerC).approve(noteTokenVault.address, unlimitedAllowance);

                redeemParam = {
                    pool: securitizationPoolContract.address,
                    noteTokenAddress: sotContract.address,
                    noteTokenRedeemAmount: parseEther('1'),
                };
                redeemOrderMessage = presignedRedeemOrderMessage(
                    lenderSignerC.address,
                    redeemParam.pool,
                    redeemParam.noteTokenAddress,
                    redeemParam.noteTokenRedeemAmount,
                    chainId
                );
                redeemSignature = await redeemOrderAdminSigner.signMessage(redeemOrderMessage);
                await noteTokenVault.connect(lenderSignerC).redeemOrder(redeemParam, redeemSignature);
            });
            it('JOT: should revert if exceed max JOT redeem amount', async () => {
                await expect(
                    noteTokenVault
                        .connect(backendAdminSigner)
                        .preDistribute(
                            securitizationPoolContract.address,
                            maxReserveForJOTRedeem.add(parseEther('0.00001')),
                            [jotContract.address],
                            [parseEther('2.83')]
                        )
                ).to.revertedWith('MinFirstLoss is not satisfied');
            });
            it('JOT: should run successfully', async () => {
                // Disburse $2.83 for JOT
                await noteTokenVault
                    .connect(backendAdminSigner)
                    .preDistribute(
                        securitizationPoolContract.address,
                        parseEther('2.83'),
                        [jotContract.address],
                        [parseEther('1.5')]
                    );
                await noteTokenVault.connect(backendAdminSigner).disburseAll(
                    securitizationPoolContract.address,
                    jotContract.address,
                    [lenderSignerA.address, lenderSignerB.address, lenderSignerC.address],
                    [parseEther('0.83'), parseEther('1'), parseEther('1')], // Total: $0.84 + $1.00 + $1.00 = $2.83
                    [parseEther('0.83'), parseEther('1'), parseEther('1')]
                );
                const totalJOTRedeem = await noteTokenVault.totalJOTRedeem(securitizationPoolContract.address);
                expect(totalJOTRedeem).to.equal(parseEther('0.17')); // 3 - 2.83 = 0.17
                const jotRedeemOrderLenderA = await noteTokenVault.userRedeemJOTOrder(
                    securitizationPoolContract.address,
                    lenderSignerA.address
                );
                expect(jotRedeemOrderLenderA).to.equal(parseEther('0.17'));
                const sotRedeemOrderLenderB = await noteTokenVault.userRedeemJOTOrder(
                    securitizationPoolContract.address,
                    lenderSignerB.address
                );
                expect(sotRedeemOrderLenderB).to.equal(parseEther('0'));

                const jotTGECurrencyRaised = await mintedNormalTGEContract.currencyRaised();
                expect(jotTGECurrencyRaised).to.equal(parseEther('0.17')); // $3 - $2.83 = $0.17

                const reserve = await securitizationPoolContract.reserve();
                expect(reserve).to.equal(parseEther('1.67')); // $4.5 - $2.83 = $1.67
            });
        });
    });
});
