const { ethers, getChainId } = require('hardhat');
const { expect } = require('chai');
const { setup } = require('../setup.js');
const { parseEther, parseUnits, formatEther, formatBytes32String } = ethers.utils;
const UntangledProtocol = require('../shared/untangled-protocol');
const dayjs = require('dayjs');
const { time } = require('@nomicfoundation/hardhat-network-helpers');
const { presignedMintMessage, presignedRedeemOrderMessage } = require('../shared/uid-helper');
const { POOL_ADMIN_ROLE, ORIGINATOR_ROLE, BACKEND_ADMIN, SIGNER_ROLE } = require('../constants.js');
const { utils } = require('ethers');
const { getPoolByAddress, unlimitedAllowance } = require('../utils.js');
const { SaleType } = require('../shared/constants.js');
const { getContractAt } = require('@nomiclabs/hardhat-ethers/internal/helpers.js');

/**
 * This file tests the case that a pool invest into another pool
 * */

const ONE_DAY = 86400; // seconds
describe('Pool to Pool', () => {
    // investor pool - the pool which invest into another pool (buy JOT/SOT of another pool)
    describe('Pool A invests in pool B', async () => {
        let stableCoin;
        let securitizationManager;
        let loanKernel;
        let loanRepaymentRouter;
        let loanAssetTokenContract;
        let loanRegistry;
        let uniqueIdentity;
        let registry;
        let noteTokenVault;
        let poolBContract;
        let securitizationPoolValueService;

        // Wallets
        let untangledAdminSigner,
            poolCreatorSigner,
            poolACreator,
            borrowerSigner,
            lenderSigner,
            relayer,
            poolAPot,
            anonymousInvestorSigner,
            backendAdminSigner,
            redeemOrderAdminSigner;

        const stableCoinAmountToBuyJOT = parseEther('1'); // $1
        const stableCoinAmountToBuySOT = parseEther('2'); // $1
        const poolAPotInitialBalance = parseEther('100');
        let poolAContract;
        let mintedNormalTGEPoolBContract;
        let mintedNormalTGEPoolAContract;
        let mintedIncreasingInterestTGEPoolBContract;
        let mintedIncreasingInterestTGEPoolAContract;
        let jotPoolBContract;
        let sotPoolBContract;
        let chainId;
        let untangledProtocol;
        let jotAmount;
        let sotAmount;

        before('init sale', async () => {
            // Init wallets
            [
                untangledAdminSigner,
                poolCreatorSigner,
                poolACreator,
                borrowerSigner,
                lenderSigner,
                relayer,
                poolAPot,
                anonymousInvestorSigner,
                backendAdminSigner,
                redeemOrderAdminSigner,
            ] = await ethers.getSigners();

            // Init contracts
            const contracts = await setup();
            untangledProtocol = UntangledProtocol.bind(contracts);
            ({
                stableCoin,
                uniqueIdentity,
                loanAssetTokenContract,
                loanRegistry,
                loanKernel,
                loanRepaymentRouter,
                securitizationManager,
                registry,
                securitizationPoolValueService,
                noteTokenVault,
            } = contracts);

            await noteTokenVault.connect(untangledAdminSigner).grantRole(BACKEND_ADMIN, backendAdminSigner.address);
            await noteTokenVault.connect(untangledAdminSigner).grantRole(SIGNER_ROLE, redeemOrderAdminSigner.address);
            chainId = await getChainId();

            // Create new main pool
            await securitizationManager.grantRole(POOL_ADMIN_ROLE, poolCreatorSigner.address);
            const securitizationPoolAddress = await untangledProtocol.createSecuritizationPool(poolCreatorSigner);

            poolBContract = await getPoolByAddress(securitizationPoolAddress);
            // Init JOT sale
            const now = dayjs().unix();
            const initialJOTAmount = parseEther('1');
            const { jotTGEAddress, jotTokenAddress } = await untangledProtocol.initJOTSale(poolCreatorSigner, {
                issuerTokenController: untangledAdminSigner.address,
                pool: securitizationPoolAddress,
                minBidAmount: parseEther('1'),
                saleType: SaleType.NORMAL_SALE,
                longSale: true,
                ticker: "Ticker",
                openingTime: now,
                closingTime: now + ONE_DAY,
                rate: 10000,
                cap: parseEther('10'),
                initialJOTAmount,
            });

            mintedNormalTGEPoolBContract = await ethers.getContractAt('MintedNormalTGE', jotTGEAddress);

            // Init SOT sale
            const { sotTGEAddress, sotTokenAddress } = await untangledProtocol.initSOTSale(poolCreatorSigner, {
                issuerTokenController: untangledAdminSigner.address,
                pool: securitizationPoolAddress,
                saleType: SaleType.MINTED_INCREASING_INTEREST,
                minBidAmount: parseEther('1'),
                openingTime: now,
                closingTime: now + 2 * ONE_DAY,
                rate: 10000,
                cap: parseEther('10'),
                initialInterest: 10000,
                finalInterest: 90000,
                timeInterval: 86400,
                amountChangeEachInterval: 10000,
                ticker: "Ticker",
            });
            mintedIncreasingInterestTGEPoolBContract = await ethers.getContractAt(
                'MintedIncreasingInterestTGE',
                sotTGEAddress
            );

            // Create investor pool
            await securitizationManager.grantRole(POOL_ADMIN_ROLE, poolACreator.address);
            const poolAContractAddress = await untangledProtocol.createSecuritizationPool(poolACreator);
            poolAContract = await getPoolByAddress(poolAContractAddress);
            await poolAContract.connect(poolACreator).setPot(poolAPot.address);

            // Init JOT sale PoolA
            const nowPoolA = dayjs().unix();
            const { jotTGEAddress: jotTGEAddressPoolA  } = await untangledProtocol.initJOTSale(poolACreator, {
                issuerTokenController: untangledAdminSigner.address,
                pool: poolAContract.address,
                minBidAmount: parseEther('1'),
                saleType: SaleType.NORMAL_SALE,
                longSale: true,
                ticker: "Ticker",
                openingTime: nowPoolA,
                closingTime: nowPoolA + ONE_DAY,
                rate: 10000,
                cap: parseEther('10'),
                initialJOTAmount: parseEther('1'),
            });
            mintedNormalTGEPoolAContract = await ethers.getContractAt('MintedNormalTGE', jotTGEAddressPoolA);

            // Init SOT Pool A sale
            const { sotTGEAddress: sotTGEAddressPoolA } = await untangledProtocol.initSOTSale(poolACreator, {
                issuerTokenController: untangledAdminSigner.address,
                pool: poolAContract.address,
                saleType: SaleType.MINTED_INCREASING_INTEREST,
                minBidAmount: parseEther('1'),
                openingTime: now,
                closingTime: now + 2 * ONE_DAY,
                rate: 10000,
                cap: parseEther('10'),
                initialInterest: 10000,
                finalInterest: 90000,
                timeInterval: 86400,
                amountChangeEachInterval: 10000,
                ticker: "Ticker",
            });
            mintedIncreasingInterestTGEPoolAContract = await ethers.getContractAt(
                'MintedIncreasingInterestTGE',
                sotTGEAddressPoolA
            );

            // Anonymous investor gain UID
            await untangledProtocol.mintUID(anonymousInvestorSigner);
            await stableCoin.connect(untangledAdminSigner).transfer(anonymousInvestorSigner.address, parseEther('1'));
            await untangledProtocol.buyToken(anonymousInvestorSigner, mintedNormalTGEPoolAContract.address, parseEther('1'));

            // Pool A pot gain UID
            await untangledProtocol.mintUID(poolAPot);

            // Faucet stable coin to investorPoolPot
            // await stableCoin.transfer(poolAPot.address, poolAPotInitialBalance); // $100
        });

        it('Pool A pot invests into pool B for JOT', async () => {
            // Invest into main pool (buy JOT token)
            await untangledProtocol.buyToken(poolAPot, mintedNormalTGEPoolBContract.address, stableCoinAmountToBuyJOT)
            expect(await stableCoin.balanceOf(poolAPot.address)).equal('0');
        });
        it('Pool A originator can transfer JOT from pool A pot to pool A', async () => {
            // Transfer to pool
            const jotPoolBAddress = await poolBContract.jotToken();
            jotPoolBContract = await ethers.getContractAt('NoteToken', jotPoolBAddress);
            const jotPoolAAmount = await jotPoolBContract.balanceOf(poolAContract.address);

            expect(jotPoolAAmount).equal(parseEther('1'));
        });
        it('Should include B JOT token value in pool A expected assets', async () => {
            // Check values
            const chainTime = await time.latest();
            const expectAssetValue = await securitizationPoolValueService.getExpectedAssetsValue(poolAContract.address);
            expect(expectAssetValue).equal(stableCoinAmountToBuyJOT);
            const tokenERC20AssetAddress = await poolAContract.tokenAssetAddresses(0);
            expect(tokenERC20AssetAddress).equal(jotPoolBContract.address);
        });
        it('Pool A owner can claim B JOT Token from pool A to pool A pot', async () => {
            // Claim back to investor pot wallet
            await poolAContract
                .connect(poolACreator)
                .withdrawERC20Assets([jotPoolBContract.address], [poolAPot.address], [parseEther('1')]);
            const investorPoolPotJotBalance = await jotPoolBContract.balanceOf(poolAPot.address);
            expect(investorPoolPotJotBalance).equal(parseEther('1'));
        });
        it('Pool A pot can make JOT redeem request to pool B', async () => {
            // Redeem
            const investorPoolPotJotBalance = await jotPoolBContract.balanceOf(poolAPot.address);
            await jotPoolBContract.connect(poolAPot).approve(noteTokenVault.address, unlimitedAllowance);

            const redeemParam = {
                pool: poolBContract.address,
                noteTokenAddress: jotPoolBContract.address,
                noteTokenRedeemAmount: parseEther('1'),
            };
            const redeemOrderMessage = presignedRedeemOrderMessage(
                poolAPot.address,
                redeemParam.pool,
                redeemParam.noteTokenAddress,
                redeemParam.noteTokenRedeemAmount,
                chainId
            );
            const redeemSignature = await redeemOrderAdminSigner.signMessage(redeemOrderMessage);

            await noteTokenVault.connect(poolAPot).redeemOrder(redeemParam, redeemSignature);

            await noteTokenVault
                .connect(backendAdminSigner)
                .preDistribute(poolBContract.address, parseEther('1'), [jotPoolBContract.address], [parseEther('1')]);
            await noteTokenVault
                .connect(backendAdminSigner)
                .disburseAll(
                    poolBContract.address,
                    jotPoolBContract.address,
                    [poolAPot.address],
                    [parseEther('1')],
                    [parseEther('1')]
                );

            const investorPoolPotJotBalanceAfterRedeem = await jotPoolBContract.balanceOf(poolAPot.address);
            const investorPoolPotStableCoinBalanceAfterRedeem = await stableCoin.balanceOf(poolAPot.address);
            expect(investorPoolPotStableCoinBalanceAfterRedeem).equal(parseEther('1'));
            expect(investorPoolPotJotBalanceAfterRedeem).equal('0');
        });

        it('Pool A pot invests into pool B for SOT', async () => {
            await stableCoin.connect(untangledAdminSigner).transfer(anonymousInvestorSigner.address, parseEther('2'));
            await untangledProtocol.buyToken(anonymousInvestorSigner, mintedNormalTGEPoolAContract.address, parseEther('2'))
            // Invest into main pool (buy JOT token)
            await untangledProtocol.buyToken(poolAPot, mintedNormalTGEPoolBContract.address, stableCoinAmountToBuyJOT);
            const value = await mintedIncreasingInterestTGEPoolBContract.hasStarted();
            // Invest into main pool (buy SOT token)
            await untangledProtocol.buyToken(poolAPot, mintedIncreasingInterestTGEPoolBContract.address, stableCoinAmountToBuySOT)
            expect(await stableCoin.balanceOf(poolAPot.address)).equal('0');
        });
        it('Pool A originator can transfer SOT from pool A pot to pool A', async () => {
            // Transfer to pool
            const sotPoolBAddress = await poolBContract.sotToken();
            sotPoolBContract = await ethers.getContractAt('NoteToken', sotPoolBAddress);
            const sotPoolAContractAmount = await sotPoolBContract.balanceOf(poolAContract.address);

            expect(sotPoolAContractAmount).equal(parseEther('2'));
        });
        it('Should include B SOT token value in pool A expected assets', async () => {
            // Check values
            const chainTime = await time.latest();
            const expectAssetValue = await securitizationPoolValueService.getExpectedAssetsValue(poolAContract.address);
            expect(expectAssetValue).equal(parseEther('3'));
            const tokenERC20AssetAddress = await poolAContract.tokenAssetAddresses(1);
            expect(tokenERC20AssetAddress).equal(sotPoolBContract.address);
        });
        it('Pool A owner can claim B SOT Token from pool A to pool A pot', async () => {
            // Claim back to investor pot wallet
            await poolAContract
                .connect(poolACreator)
                .withdrawERC20Assets([sotPoolBContract.address], [poolAPot.address], [parseEther('2')]);
            const investorPoolPotJotBalance = await sotPoolBContract.balanceOf(poolAPot.address);
            expect(investorPoolPotJotBalance).equal(parseEther('2'));
        });
        it('Pool A pot can make SOT redeem request to pool B', async () => {
            // Redeem
            const investorPoolPotSotBalance = await sotPoolBContract.balanceOf(poolAPot.address);

            await sotPoolBContract.connect(poolAPot).approve(noteTokenVault.address, unlimitedAllowance);

            const redeemParam = {
                pool: poolBContract.address,
                noteTokenAddress: sotPoolBContract.address,
                noteTokenRedeemAmount: investorPoolPotSotBalance,
            };
            const redeemOrderMessage = presignedRedeemOrderMessage(
                poolAPot.address,
                redeemParam.pool,
                redeemParam.noteTokenAddress,
                redeemParam.noteTokenRedeemAmount,
                chainId
            );
            const redeemSignature = await redeemOrderAdminSigner.signMessage(redeemOrderMessage);

            await noteTokenVault.connect(poolAPot).redeemOrder(redeemParam, redeemSignature);

            await noteTokenVault
                .connect(backendAdminSigner)
                .preDistribute(
                    poolBContract.address,
                    investorPoolPotSotBalance,
                    [sotPoolBContract.address],
                    [parseEther('2')]
                );
            await noteTokenVault
                .connect(backendAdminSigner)
                .disburseAll(
                    poolBContract.address,
                    sotPoolBContract.address,
                    [poolAPot.address],
                    [investorPoolPotSotBalance],
                    [parseEther('2')]
                );

            const investorPoolPotJotBalanceAfterRedeem = await sotPoolBContract.balanceOf(poolAPot.address);
            const investorPoolPotStableCoinBalanceAfterRedeem = await stableCoin.balanceOf(poolAPot.address);
            expect(investorPoolPotStableCoinBalanceAfterRedeem).equal(stableCoinAmountToBuySOT);
            expect(investorPoolPotJotBalanceAfterRedeem).equal('0');
        });
    });

    describe('Pool A invests in pool B, pool B invests in pool C', async () => {
        let stableCoin;
        let securitizationManager;
        let loanKernel;
        let loanRepaymentRouter;
        let loanAssetTokenContract;
        let loanRegistry;
        let uniqueIdentity;
        let registry;
        let noteTokenVault;
        let distributionAssessor;
        let securitizationPoolValueService;
        let chainId;

        let poolAContract;
        let poolBContract;
        let poolCContract;
        let mintedNormalTGEPoolAContract;
        let mintedIncreasingInterestTGEPoolAContract;
        let mintedNormalTGEPoolBContract;
        let mintedIncreasingInterestTGEPoolBContract;
        let mintedNormalTGEPoolCContract;
        let mintedIncreasingInterestTGEPoolCContract;
        let sotBContract;
        let sotCContract;
        let jotBContract;
        let jotCContract;
        let untangledProtocol;
        let sotAmountABuyFromB; // Currency amount
        let sotAmountBBuyFromC; // Currency amount

        // Wallets
        let untangledAdminSigner,
            poolBCreatorSigner,
            poolACreatorSigner,
            poolCCreatorSigner,
            poolAOriginatorSigner,
            poolBOriginatorSigner,
            lenderSigner,
            relayer,
            poolAPotSigner,
            poolBPotSigner,
            poolCPotSigner,
            anonymousInvestorSigner,
            backendAdminSigner,
            redeemOrderAdminSigner;

        const stableCoinAmountToBuyBJOT = parseEther('2'); // $2
        const stableCoinAmountToBuyCJOT = parseEther('1'); // $1
        const poolAPotInitialBalance = parseEther('100');
        const expectSOTAmountABuyFromB = parseEther('2');
        const expectSOTAmountBBuyFromC = parseEther('1');
        const NOW = dayjs().unix();
        before('init sale', async () => {
            // Init wallets
            [
                untangledAdminSigner,
                poolBCreatorSigner,
                poolACreatorSigner,
                poolCCreatorSigner,
                poolAOriginatorSigner,
                poolBOriginatorSigner,
                lenderSigner,
                relayer,
                poolAPotSigner,
                poolBPotSigner,
                poolCPotSigner,
                anonymousInvestorSigner,
                backendAdminSigner,
                redeemOrderAdminSigner,
            ] = await ethers.getSigners();

            // Init contracts
            const contracts = await setup();
            untangledProtocol = UntangledProtocol.bind(contracts);
            ({
                stableCoin,
                uniqueIdentity,
                loanAssetTokenContract,
                loanRegistry,
                loanKernel,
                loanRepaymentRouter,
                securitizationManager,
                distributionAssessor,
                registry,
                securitizationPoolValueService,
                noteTokenVault,
            } = contracts);

            await noteTokenVault.connect(untangledAdminSigner).grantRole(BACKEND_ADMIN, backendAdminSigner.address);
            await noteTokenVault.connect(untangledAdminSigner).grantRole(SIGNER_ROLE, redeemOrderAdminSigner.address);
            chainId = await getChainId();

            // Create pool C
            await securitizationManager.grantRole(POOL_ADMIN_ROLE, poolCCreatorSigner.address);
            const poolCContractAddress = await untangledProtocol.createSecuritizationPool(poolCCreatorSigner);
            poolCContract = await getPoolByAddress(poolCContractAddress);

            // Set pot for pool C
            await poolCContract.connect(poolCCreatorSigner).setPot(poolCPotSigner.address);
            await stableCoin.connect(poolCPotSigner).approve(poolCContract.address, ethers.constants.MaxUint256);

            // Init JOT sale pool C
            const { jotTGEAddress: jotTGEPoolCAddress  } = await untangledProtocol.initJOTSale(poolCCreatorSigner, {
                issuerTokenController: untangledAdminSigner.address,
                pool: poolCContract.address,
                minBidAmount: parseEther('1'),
                saleType: SaleType.NORMAL_SALE,
                longSale: true,
                ticker: "Ticker",
                openingTime: NOW,
                closingTime: NOW + ONE_DAY,
                rate: 10000,
                cap: parseEther('10'),
                initialJOTAmount: parseEther('1'),
            });
            mintedNormalTGEPoolCContract = await ethers.getContractAt('MintedNormalTGE', jotTGEPoolCAddress);
            const jotPoolCAddress = await poolCContract.jotToken();
            jotCContract = await ethers.getContractAt('NoteToken', jotPoolCAddress);

            // Init SOT sale pool C
            const { sotTGEAddress: sotTGEPoolCAddress } = await untangledProtocol.initSOTSale(poolCCreatorSigner, {
                issuerTokenController: untangledAdminSigner.address,
                pool: poolCContract.address,
                saleType: SaleType.MINTED_INCREASING_INTEREST,
                minBidAmount: parseEther('1'),
                openingTime: NOW,
                closingTime: NOW + 2 * ONE_DAY,
                rate: 10000,
                cap: parseEther('10'),
                initialInterest: 10000,
                finalInterest: 90000,
                timeInterval: 86400,
                amountChangeEachInterval: 10000,
                ticker: "Ticker",
            });
            mintedIncreasingInterestTGEPoolCContract = await ethers.getContractAt(
                'MintedIncreasingInterestTGE',
                sotTGEPoolCAddress
            );
            const sotPoolCAddress = await poolCContract.sotToken();
            sotCContract = await ethers.getContractAt('NoteToken', sotPoolCAddress);

            // Create pool B
            await securitizationManager.grantRole(POOL_ADMIN_ROLE, poolBCreatorSigner.address);
            const securitizationPoolAddress = await untangledProtocol.createSecuritizationPool(poolBCreatorSigner);

            // Set pot for pool B
            poolBContract = await getPoolByAddress(securitizationPoolAddress);
            await poolBContract.connect(poolBCreatorSigner).setPot(poolBPotSigner.address);
            await stableCoin.connect(poolBPotSigner).approve(poolBContract.address, ethers.constants.MaxUint256);

            // Init JOT sale pool B
            const { jotTGEAddress: jotTGEPoolBAddress, jotTokenAddress: jotPoolBAddress  } = await untangledProtocol.initJOTSale(poolBCreatorSigner, {
                issuerTokenController: untangledAdminSigner.address,
                pool: poolBContract.address,
                minBidAmount: parseEther('1'),
                saleType: SaleType.NORMAL_SALE,
                longSale: true,
                ticker: "Ticker",
                openingTime: NOW,
                closingTime: NOW + ONE_DAY,
                rate: 10000,
                cap: parseEther('10'),
                initialJOTAmount: parseEther('1'),
            });
            mintedNormalTGEPoolBContract = await ethers.getContractAt('MintedNormalTGE', jotTGEPoolBAddress);
            jotBContract = await ethers.getContractAt('NoteToken', jotPoolBAddress);

            // Init SOT sale pool B
            const sotCapPoolB = '10000000000000000000';
            const isLongSaleTGESOTPoolB = true;
            const { sotTGEAddress: sotTGEPoolBAddress } = await untangledProtocol.initSOTSale(poolBCreatorSigner, {
                issuerTokenController: untangledAdminSigner.address,
                pool: poolBContract.address,
                saleType: SaleType.MINTED_INCREASING_INTEREST,
                minBidAmount: parseEther('1'),
                openingTime: NOW,
                closingTime: NOW + 2 * ONE_DAY,
                rate: 10000,
                cap: parseEther('10'),
                initialInterest: 10000,
                finalInterest: 90000,
                timeInterval: 86400,
                amountChangeEachInterval: 10000,
                ticker: "Ticker",
            });
            mintedIncreasingInterestTGEPoolBContract = await ethers.getContractAt(
                'MintedIncreasingInterestTGE',
                sotTGEPoolBAddress
            );
            const sotPoolBAddress = await poolBContract.sotToken();
            sotBContract = await ethers.getContractAt('NoteToken', sotPoolBAddress);

            // Create pool A
            await securitizationManager.grantRole(POOL_ADMIN_ROLE, poolACreatorSigner.address);
            const poolAContractAddress = await untangledProtocol.createSecuritizationPool(poolACreatorSigner);
            poolAContract = await getPoolByAddress(poolAContractAddress);
            await poolAContract.connect(poolACreatorSigner).setPot(poolAPotSigner.address);

            // Init JOT sale PoolA
            const { jotTGEAddress: jotTGEAddressPoolA  } = await untangledProtocol.initJOTSale(poolACreatorSigner, {
                issuerTokenController: untangledAdminSigner.address,
                pool: poolAContract.address,
                minBidAmount: parseEther('1'),
                saleType: SaleType.NORMAL_SALE,
                longSale: true,
                ticker: "Ticker",
                openingTime: NOW,
                closingTime: NOW + ONE_DAY,
                rate: 10000,
                cap: parseEther('10'),
                initialJOTAmount: parseEther('1'),
            });
            mintedNormalTGEPoolAContract = await ethers.getContractAt('MintedNormalTGE', jotTGEAddressPoolA);

            // Init SOT Pool A sale
            const { sotTGEAddress } = await untangledProtocol.initSOTSale(poolACreatorSigner, {
                issuerTokenController: untangledAdminSigner.address,
                pool: poolAContract.address,
                saleType: SaleType.MINTED_INCREASING_INTEREST,
                minBidAmount: parseEther('1'),
                openingTime: NOW,
                closingTime: NOW + 2 * ONE_DAY,
                rate: 10000,
                cap: parseEther('10'),
                initialInterest: 10000,
                finalInterest: 90000,
                timeInterval: 86400,
                amountChangeEachInterval: 10000,
                ticker: "Ticker",
            });

            // Anonymous investor gain UID
            await untangledProtocol.mintUID(anonymousInvestorSigner);
            await stableCoin.connect(untangledAdminSigner).transfer(anonymousInvestorSigner.address, parseEther('2'));
            await untangledProtocol.buyToken(
                anonymousInvestorSigner,
                mintedNormalTGEPoolAContract.address,
                parseEther('2')
            );


            // Pool A pot gain UID
            await untangledProtocol.mintUID(poolAPotSigner);

            // Pool B pot gain UID
            await untangledProtocol.mintUID(poolBPotSigner);

            // Faucet stable coin to investorPoolPot
            // await stableCoin.transfer(poolAPotSigner.address, poolAPotInitialBalance); // $100
        });

        it('Pool A pot invests into pool B for JOT', async () => {
            // Invest into main pool (buy JOT token)
            await untangledProtocol.buyToken(poolAPotSigner, mintedNormalTGEPoolBContract.address, stableCoinAmountToBuyBJOT)
            expect(await stableCoin.balanceOf(poolAPotSigner.address)).equal('0');
            expect(await jotBContract.balanceOf(poolAContract.address)).equal(parseEther('2'));
        });
        it('Pool B pot invests into pool C for JOT', async () => {
            await  untangledProtocol.buyToken(poolBPotSigner, mintedNormalTGEPoolCContract.address, stableCoinAmountToBuyCJOT)
            expect(await stableCoin.balanceOf(poolBPotSigner.address)).equal(
                stableCoinAmountToBuyBJOT.sub(stableCoinAmountToBuyCJOT)
            );
            expect(await jotCContract.balanceOf(poolBContract.address)).equal(parseEther('1'));
        });
        it('Pool A originator can transfer B-JOT from pool A pot to pool A', async () => {
            expect(await jotBContract.balanceOf(poolAContract.address)).equal(parseEther('2'));
        });
        it('Pool B originator can transfer C-JOT from pool B pot to pool B', async () => {
            expect(await jotCContract.balanceOf(poolBContract.address)).equal(parseEther('1'));
        });
        it('Should include B-JOT token value in pool A expected assets', async () => {
            // Check values
            const tokenERC20AssetLength = await poolAContract.getTokenAssetAddressesLength();
            const balanceOfPoolAWithjotBContract = await jotBContract.balanceOf(poolAContract.address);

            const expectAssetValue = await securitizationPoolValueService.getExpectedAssetsValue(poolAContract.address);
            expect(expectAssetValue).closeTo(parseEther('2'), parseEther('0.01'));
            // SOT address was added to tokenAssetAddresses variables
            const tokenERC20AssetAddress = await poolAContract.tokenAssetAddresses(0);
            expect(tokenERC20AssetAddress).equal(jotBContract.address);
        });
        it('Should include C-JOT token value in pool B expected assets', async () => {
            // Check values
            const chainTime = await time.latest();
            // SOT address was added to tokenAssetAddresses variables
            const tokenERC20AssetAddress = await poolBContract.tokenAssetAddresses(0);
            expect(tokenERC20AssetAddress).equal(jotCContract.address);
            const expectAssetValue = await securitizationPoolValueService.getExpectedAssetsValue(poolBContract.address);
            expect(expectAssetValue).equal(stableCoinAmountToBuyCJOT);
        });
        it('Pool A owner can claim B-JOT Token from pool A to pool A pot', async () => {
            // Claim back to investor pot wallet
            await poolAContract
                .connect(poolACreatorSigner)
                .withdrawERC20Assets([jotBContract.address], [poolAPotSigner.address], [parseEther('2')]);
            const sotBalance = await jotBContract.balanceOf(poolAPotSigner.address);
            expect(sotBalance).equal(expectSOTAmountABuyFromB);
        });
        it('Pool B owner can claim C-JOT Token from pool B to pool B pot', async () => {
            // Claim back to investor pot wallet
            await poolBContract
                .connect(poolBCreatorSigner)
                .withdrawERC20Assets([jotCContract.address], [poolBPotSigner.address], [parseEther('1')]);
            const sotBalance = await jotCContract.balanceOf(poolBPotSigner.address);
            expect(sotBalance).equal(expectSOTAmountBBuyFromC);
        });
        it('Pool B pot can make JOT redeem request to pool C', async () => {
            // Redeem
            const jotBalance = await jotCContract.balanceOf(poolBPotSigner.address);

            await jotCContract.connect(poolBPotSigner).approve(noteTokenVault.address, unlimitedAllowance);

            const redeemParam = {
                pool: poolCContract.address,
                noteTokenAddress: jotCContract.address,
                noteTokenRedeemAmount: jotBalance,
            };
            const redeemOrderMessage = presignedRedeemOrderMessage(
                poolBPotSigner.address,
                redeemParam.pool,
                redeemParam.noteTokenAddress,
                redeemParam.noteTokenRedeemAmount,
                chainId
            );
            const redeemSignature = await redeemOrderAdminSigner.signMessage(redeemOrderMessage);

            await noteTokenVault.connect(poolBPotSigner).redeemOrder(redeemParam, redeemSignature);

            await noteTokenVault
                .connect(backendAdminSigner)
                .preDistribute(
                    poolCContract.address,
                    stableCoinAmountToBuyCJOT,
                    [jotCContract.address],
                    [parseEther('1')]
                );
            await noteTokenVault
                .connect(backendAdminSigner)
                .disburseAll(
                    poolCContract.address,
                    jotCContract.address,
                    [poolBPotSigner.address],
                    [stableCoinAmountToBuyCJOT],
                    [parseEther('1')]
                );
            const investorPoolPotJotBalanceAfterRedeem = await jotCContract.balanceOf(poolBPotSigner.address);
            const investorPoolPotStableCoinBalanceAfterRedeem = await stableCoin.balanceOf(poolBPotSigner.address);
            expect(investorPoolPotStableCoinBalanceAfterRedeem).equal(stableCoinAmountToBuyBJOT);
            expect(investorPoolPotJotBalanceAfterRedeem).equal('0');
        });

        it('Pool A pot can make JOT redeem request to pool B', async () => {
            // Redeem
            const investorPoolPotJotBalance = await jotBContract.balanceOf(poolAPotSigner.address);

            await jotBContract.connect(poolAPotSigner).approve(noteTokenVault.address, unlimitedAllowance);

            const redeemParam = {
                pool: poolBContract.address,
                noteTokenAddress: jotBContract.address,
                noteTokenRedeemAmount: investorPoolPotJotBalance,
            };
            const redeemOrderMessage = presignedRedeemOrderMessage(
                poolAPotSigner.address,
                redeemParam.pool,
                redeemParam.noteTokenAddress,
                redeemParam.noteTokenRedeemAmount,
                chainId
            );
            const redeemSignature = await redeemOrderAdminSigner.signMessage(redeemOrderMessage);

            await noteTokenVault.connect(poolAPotSigner).redeemOrder(redeemParam, redeemSignature);

            await noteTokenVault
                .connect(backendAdminSigner)
                .preDistribute(
                    poolBContract.address,
                    stableCoinAmountToBuyBJOT,
                    [jotBContract.address],
                    [parseEther('2')]
                );
            await noteTokenVault
                .connect(backendAdminSigner)
                .disburseAll(
                    poolBContract.address,
                    jotBContract.address,
                    [poolAPotSigner.address],
                    [stableCoinAmountToBuyBJOT],
                    [parseEther('2')]
                );

            const investorPoolPotJotBalanceAfterRedeem = await jotBContract.balanceOf(poolAPotSigner.address);
            const investorPoolPotStableCoinBalanceAfterRedeem = await stableCoin.balanceOf(poolAPotSigner.address);
            expect(investorPoolPotStableCoinBalanceAfterRedeem).closeTo(stableCoinAmountToBuyBJOT, parseEther('0.01'));
            expect(investorPoolPotJotBalanceAfterRedeem).equal('0');
        });
    });
});
