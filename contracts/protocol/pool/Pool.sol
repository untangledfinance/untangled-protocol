// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;
import {INoteToken} from '../../interfaces/INoteToken.sol';
import {IPool} from '../../interfaces/IPool.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {Registry} from '../../storage/Registry.sol';
import {OWNER_ROLE, ORIGINATOR_ROLE, POOL_ADMIN_ROLE} from '../../libraries/DataTypes.sol';
import {PoolStorage} from './PoolStorage.sol';
import {DataTypes, ONE, ONE_HUNDRED_PERCENT} from '../../libraries/DataTypes.sol';
import {UntangledBase} from '../../base/UntangledBase.sol';
import {PoolNAVLogic} from '../../libraries/logic/PoolNAVLogic.sol';
import {PoolAssetLogic} from '../../libraries/logic/PoolAssetLogic.sol';
import {TGELogic} from '../../libraries/logic/TGELogic.sol';
import {GenericLogic} from '../../libraries/logic/GenericLogic.sol';
import {RebaseLogic} from '../../libraries/logic/RebaseLogic.sol';
import {Configuration} from '../../libraries/Configuration.sol';

/**
 * @title Untangled's SecuritizationPool contract
 * @notice Main entry point for senior LPs (a.k.a. capital providers)
 *  Automatically invests across borrower pools using an adjustable strategy.
 * @author Untangled Team
 */
contract Pool is IPool, PoolStorage, UntangledBase {
    using ConfigHelper for Registry;

    Registry public registry;

    event InsertNFTAsset(address token, uint256 tokenId);

    modifier requirePoolAdminOrOwner() {
        require(
            hasRole(POOL_ADMIN_ROLE, _msgSender()) || hasRole(OWNER_ROLE, _msgSender()),
            'Pool: Not an pool admin or pool owner'
        );
        _;
    }

    /** CONSTRUCTOR */
    function initialize(address _registryAddress, bytes memory params) public initializer {
        __UntangledBase__init(_msgSender());

        require(_registryAddress != address(0), 'Registry address cannot be empty');
        registry = Registry(_registryAddress);

        DataTypes.NewPoolParams memory newPoolParams = abi.decode(params, (DataTypes.NewPoolParams));

        require(newPoolParams.currency != address(0), 'Pool: Invalid currency');

        _poolStorage.underlyingCurrency = newPoolParams.currency;
        _poolStorage.validatorRequired = newPoolParams.validatorRequired;
        _poolStorage.pot = address(this);

        TGELogic._setMinFirstLossCushion(_poolStorage, newPoolParams.minFirstLossCushion);
        TGELogic._setDebtCeiling(_poolStorage, newPoolParams.debtCeiling);

        require(
            INoteToken(newPoolParams.currency).approve(address(this), type(uint256).max),
            'Pool: Currency approval failed'
        );

        registry.getLoanAssetToken().setApprovalForAll(address(registry.getLoanKernel()), true);
    }

    function tgeAddress() public view returns (address) {
        return _poolStorage.tgeAddress;
    }

    function getNFTAssetsLength() external view returns (uint256) {
        return _poolStorage.nftAssets.length;
    }

    /// @notice A view function that returns an array of token asset addresses
    function getTokenAssetAddresses() external view returns (address[] memory) {
        return _poolStorage.tokenAssetAddresses;
    }

    /// @notice A view function that returns the length of the token asset addresses array
    function getTokenAssetAddressesLength() external view returns (uint256) {
        return _poolStorage.tokenAssetAddresses.length;
    }

    /// @notice Riks scores length
    /// @return the length of the risk scores array
    function getRiskScoresLength() external view returns (uint256) {
        return _poolStorage.riskScores.length;
    }

    function riskScores(uint256 index) external view returns (DataTypes.RiskScore memory) {
        return _poolStorage.riskScores[index];
    }

    function nftAssets(uint256 idx) external view returns (DataTypes.NFTAsset memory) {
        return _poolStorage.nftAssets[idx];
    }

    function tokenAssetAddresses(uint256 idx) external view returns (address) {
        return _poolStorage.tokenAssetAddresses[idx];
    }

    /// @notice sets up the risk scores for the contract for pool
    function setupRiskScores(
        uint32[] calldata _daysPastDues,
        uint32[] calldata _ratesAndDefaults,
        uint32[] calldata _periodsAndWriteOffs
    ) external whenNotPaused onlyRole(POOL_ADMIN_ROLE) {
        PoolAssetLogic.setupRiskScores(_poolStorage, _daysPastDues, _ratesAndDefaults, _periodsAndWriteOffs);
        // rebase
        rebase();
    }

    /// @notice exports NFT assets to another pool address
    function exportAssets(
        address tokenAddress,
        address toPoolAddress,
        uint256[] calldata tokenIds
    ) external whenNotPaused nonReentrant requirePoolAdminOrOwner {
        PoolAssetLogic.exportAssets(_poolStorage.nftAssets, tokenAddress, toPoolAddress, tokenIds);
    }

    /// @notice withdraws NFT assets from the contract and transfers them to recipients
    function withdrawAssets(
        address[] calldata tokenAddresses,
        uint256[] calldata tokenIds,
        address[] calldata recipients
    ) external whenNotPaused onlyRole(OWNER_ROLE) {
        PoolAssetLogic.withdrawAssets(_poolStorage.nftAssets, tokenAddresses, tokenIds, recipients);
    }

    function getLoansValue(
        uint256[] memory tokenIds,
        DataTypes.LoanEntry[] memory loanEntries
    ) external view returns (uint256, uint256[] memory) {
        return PoolAssetLogic.getLoansValue(_poolStorage, tokenIds, loanEntries);
    }

    /// @notice collects NFT assets from a specified address
    function collectAssets(
        uint256[] calldata tokenIds,
        DataTypes.LoanEntry[] calldata loanEntries
    ) external whenNotPaused returns (uint256) {
        registry.requireLoanKernel(_msgSender());
        return PoolAssetLogic.collectAssets(_poolStorage, tokenIds, loanEntries);
    }

    /// @notice collects ERC20 assets from specified senders
    function collectERC20Asset(address tokenAddresss) external whenNotPaused {
        registry.requireSecuritizationManager(_msgSender());
        PoolAssetLogic.collectERC20Asset(_poolStorage, tokenAddresss);
    }

    /// @notice withdraws ERC20 assets from the contract and transfers them to recipients\ound
    function withdrawERC20Assets(
        address[] calldata tokenAddresses,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external whenNotPaused nonReentrant requirePoolAdminOrOwner {
        PoolAssetLogic.withdrawERC20Assets(_poolStorage.existsTokenAssetAddress, tokenAddresses, recipients, amounts);
    }

    /// @dev Trigger set up opening block timestamp
    function setUpOpeningBlockTimestamp() external {
        require(_msgSender() == tgeAddress(), 'SecuritizationPool: Only tge address');
        PoolAssetLogic.setUpOpeningBlockTimestamp(_poolStorage);
    }

    function onERC721Received(address, address, uint256 tokenId, bytes memory) external returns (bytes4) {
        address token = _msgSender();
        require(
            token == address(registry.getLoanAssetToken()),
            'SecuritizationPool: Must be token issued by Untangled'
        );
        DataTypes.NFTAsset[] storage _nftAssets = _poolStorage.nftAssets;
        _nftAssets.push(DataTypes.NFTAsset({tokenAddress: token, tokenId: tokenId}));
        emit InsertNFTAsset(token, tokenId);
        return this.onERC721Received.selector;
    }

    /*==================== NAV ====================*/
    function writeOff(uint256 loan) public {
        PoolNAVLogic.writeOff(_poolStorage, loan);
        // rebase
        rebase();
    }

    function repayLoan(
        uint256[] calldata loans,
        uint256[] calldata amounts
    ) external returns (uint256[] memory, uint256[] memory) {
        require(address(registry.getLoanKernel()) == msg.sender, 'not authorized');
        uint256 numberOfLoans = loans.length;
        require(numberOfLoans == amounts.length, 'Invalid length');

        uint256[] memory lastOutstandingDebt = new uint256[](numberOfLoans);

        for (uint256 i; i < numberOfLoans; i++) {
            (uint256 chi, uint256 penaltyChi) = GenericLogic.chiAndPenaltyChi(_poolStorage, loans[i]);
            lastOutstandingDebt[i] = GenericLogic.debtWithChi(_poolStorage, loans[i], chi, penaltyChi);
        }

        (uint256[] memory repayAmounts, uint256[] memory previousDebts) = PoolNAVLogic.repayLoan(
            _poolStorage,
            loans,
            amounts
        );

        uint256 totalIncomeRepay;
        uint256 totalCapitalRepay;

        for (uint256 i; i < numberOfLoans; i++) {
            uint256 interestAmount = previousDebts[i] - lastOutstandingDebt[i];

            if (repayAmounts[i] <= interestAmount) {
                totalIncomeRepay += repayAmounts[i];
            } else {
                totalIncomeRepay += interestAmount;
                totalCapitalRepay += repayAmounts[i] - interestAmount;
            }
        }

        _poolStorage.incomeReserve += totalIncomeRepay;
        _poolStorage.capitalReserve += totalCapitalRepay;

        return (repayAmounts, previousDebts);
    }

    function debt(uint256 loan) external view returns (uint256 loanDebt) {
        return GenericLogic.debt(_poolStorage, loan);
    }

    function risk(bytes32 nft_) external view returns (uint256 risk_) {
        return uint256(_poolStorage.details[nft_].risk);
    }

    /// @notice calculates and returns the current NAV
    /// @return nav_ current NAV
    function currentNAV() external view returns (uint256 nav_) {
        return GenericLogic.currentNAV(_poolStorage);
    }

    function currentNAVAsset(bytes32 tokenId) external view returns (uint256) {
        return GenericLogic.currentNAVAsset(_poolStorage, tokenId);
    }

    function futureValue(bytes32 nft_) external view returns (uint256) {
        return uint256(_poolStorage.details[nft_].futureValue);
    }

    function maturityDate(bytes32 nft_) external view returns (uint256) {
        return uint256(_poolStorage.details[nft_].maturityDate);
    }

    function discountRate() external view returns (uint256) {
        return uint256(_poolStorage.discountRate);
    }

    function updateAssetRiskScore(bytes32 nftID_, uint256 risk_) external onlyRole(POOL_ADMIN_ROLE) {
        PoolNAVLogic.updateAssetRiskScore(_poolStorage, nftID_, risk_);
    }

    /// @notice retrieves loan information
    function getAsset(bytes32 agreementId) external view returns (DataTypes.NFTDetails memory) {
        return _poolStorage.details[agreementId];
    }

    /*==================== TGE ====================*/
    function setPot(address _pot) external whenNotPaused nonReentrant requirePoolAdminOrOwner {
        TGELogic.setPot(_poolStorage, _pot);
        registry.getSecuritizationManager().registerPot(_pot);
    }

    /// @notice sets debt ceiling value
    function setDebtCeiling(uint256 _debtCeiling) external whenNotPaused requirePoolAdminOrOwner {
        TGELogic.setDebtCeiling(_poolStorage, _debtCeiling);
    }

    /// @notice sets mint first loss value
    function setMinFirstLossCushion(uint32 _minFirstLossCushion) external whenNotPaused requirePoolAdminOrOwner {
        TGELogic.setMinFirstLossCushion(_poolStorage, _minFirstLossCushion);
    }

    function pot() external view returns (address) {
        return _poolStorage.pot;
    }

    /// @dev trigger update reserve when buy note token action happens
    function increaseCapitalReserve(uint256 currencyAmount) external whenNotPaused {
        require(
            _msgSender() == address(registry.getSecuritizationManager()) ||
                _msgSender() == address(registry.getNoteTokenVault()),
            'SecuritizationPool: Caller must be SecuritizationManager or NoteTokenVault'
        );
        GenericLogic.increaseCapitalReserve(_poolStorage, currencyAmount);
    }

    function secondTGEAddress() external view returns (address) {
        return _poolStorage.secondTGEAddress;
    }

    function sotToken() external view returns (address) {
        return TGELogic.sotToken(_poolStorage);
    }

    function jotToken() external view returns (address) {
        return TGELogic.jotToken(_poolStorage);
    }

    function underlyingCurrency() external view returns (address) {
        return _poolStorage.underlyingCurrency;
    }

    function paidPrincipalAmountSOT() external view returns (uint256) {
        return _poolStorage.paidPrincipalAmountSOT;
    }

    function reserve() external view returns (uint256) {
        return GenericLogic.reserve(_poolStorage);
    }

    function debtCeiling() external view returns (uint256) {
        return _poolStorage.debtCeiling;
    }

    // Annually, support 4 decimals num
    function interestRateSOT() external view returns (uint256) {
        return _poolStorage.interestRateSOT;
    }

    function setInterestRateSOT(uint32 _newRate) external {
        registry.requireSecuritizationManager(_msgSender());
        TGELogic._setInterestRateSOT(_poolStorage, _newRate);
    }

    function minFirstLossCushion() external view returns (uint32) {
        return _poolStorage.minFirstLossCushion;
    }

    // Total $ (cUSD) paid for Asset repayment - repayInBatch
    function totalAssetRepaidCurrency() external view returns (uint256) {
        return _poolStorage.totalAssetRepaidCurrency;
    }

    /// @notice injects the address of the Token Generation Event (TGE) and the associated token address
    function injectTGEAddress(
        address _tgeAddress,
        // address _tokenAddress,
        Configuration.NOTE_TOKEN_TYPE _noteToken
    ) external whenNotPaused {
        registry.requireSecuritizationManager(_msgSender());
        TGELogic.injectTGEAddress(_poolStorage, _tgeAddress, _noteToken);
    }

    /// @dev Disburses a specified amount of currency to the given user.
    /// @param usr The address of the user to receive the currency.
    /// @param currencyAmount The amount of currency to disburse.
    function disburse(address usr, uint256 currencyAmount) external whenNotPaused {
        require(
            _msgSender() == address(registry.getNoteTokenVault()),
            'SecuritizationPool: Caller must be NoteTokenVault'
        );
        TGELogic.disburse(_poolStorage, usr, currencyAmount);
    }

    /// @notice checks if the redemption process has finished
    function hasFinishedRedemption() external view returns (bool) {
        return TGELogic.hasFinishedRedemption(_poolStorage);
    }

    ///@notice check current debt ceiling is valid
    function isDebtCeilingValid() external view returns (bool) {
        return TGELogic.isDebtCeilingValid(_poolStorage);
    }

    function claimCashRemain(address recipientWallet) external whenNotPaused onlyRole(OWNER_ROLE) {
        require(TGELogic.hasFinishedRedemption(_poolStorage), 'SecuritizationPool: Redemption has not finished');
        TGELogic.claimCashRemain(_poolStorage, recipientWallet);
    }

    function openingBlockTimestamp() external view returns (uint64) {
        return _poolStorage.openingBlockTimestamp;
    }

    /// @notice allows the originator to withdraw from reserve
    function withdraw(address to, uint256 amount) external whenNotPaused {
        registry.requireLoanKernel(_msgSender());
        require(hasRole(ORIGINATOR_ROLE, to), 'SecuritizationPool: Only Originator can drawdown');
        require(!registry.getNoteTokenVault().redeemDisabled(address(this)), 'SecuritizationPool: withdraw paused');
        TGELogic.withdraw(_poolStorage, to, amount);
    }

    function validatorRequired() external view returns (bool) {
        return _poolStorage.validatorRequired;
    }

    /*==================== REBASE ====================*/
    /// @notice rebase the debt and balance of the senior tranche according to
    /// the current ratio between senior and junior
    function rebase() public {
        RebaseLogic.rebase(_poolStorage, GenericLogic.currentNAV(_poolStorage), GenericLogic.reserve(_poolStorage));
    }

    /// @notice changes the senior asset value based on new supply or redeems
    /// @param _seniorSupply senior supply amount
    /// @param _seniorRedeem senior redeem amount
    function changeSeniorAsset(uint256 _seniorSupply, uint256 _seniorRedeem) external {
        require(
            _msgSender() == address(registry.getSecuritizationManager()) ||
                _msgSender() == address(registry.getNoteTokenVault()),
            'SecuritizationPool: Caller must be SecuritizationManager or NoteTokenVault'
        );
        RebaseLogic.changeSeniorAsset(
            _poolStorage,
            GenericLogic.currentNAV(_poolStorage),
            GenericLogic.reserve(_poolStorage),
            _seniorSupply,
            _seniorRedeem
        );
        if (_seniorSupply > 0) require(isMinFirstLossValid(), 'Pool: Exceeds MinFirstLoss');
    }

    function seniorDebtAndBalance() external view returns (uint256, uint256) {
        return (RebaseLogic.seniorDebt(_poolStorage), _poolStorage.seniorBalance);
    }

    function calcTokenPrices() external view returns (uint256 juniorTokenPrice, uint256 seniorTokenPrice) {
        address jotTokenAddress = TGELogic.jotToken(_poolStorage);
        address sotTokenAddress = TGELogic.sotToken(_poolStorage);
        uint256 noteTokenDecimal = (10 ** INoteToken(sotTokenAddress).decimals());
        (uint256 _juniorTokenPrice, uint256 _seniorTokenPrice) = RebaseLogic.calcTokenPrices(
            GenericLogic.currentNAV(_poolStorage),
            GenericLogic.reserve(_poolStorage),
            RebaseLogic.seniorDebt(_poolStorage),
            _poolStorage.seniorBalance,
            INoteToken(jotTokenAddress).totalSupply(),
            INoteToken(sotTokenAddress).totalSupply()
        );
        return ((_juniorTokenPrice * noteTokenDecimal) / ONE, (_seniorTokenPrice * noteTokenDecimal) / ONE);
    }

    function calcJuniorRatio() public view returns (uint256 juniorRatio) {
        return
            RebaseLogic.calcJuniorRatio(
                GenericLogic.currentNAV(_poolStorage),
                GenericLogic.reserve(_poolStorage),
                RebaseLogic.seniorDebt(_poolStorage),
                _poolStorage.seniorBalance
            );
    }

    function isMinFirstLossValid() public view returns (bool) {
        return _poolStorage.minFirstLossCushion <= calcJuniorRatio();
    }
}
