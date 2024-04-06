// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;
import {INoteToken} from '../../interfaces/INoteToken.sol';
import {IPool} from '../../interfaces/IPool.sol';
import {IEpochExecutor} from '../../interfaces/IEpochExecutor.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {Registry} from '../../storage/Registry.sol';
import {OWNER_ROLE, ORIGINATOR_ROLE, POOL_ADMIN_ROLE} from '../../libraries/DataTypes.sol';
import {PoolStorage} from './PoolStorage.sol';
import {DataTypes, ONE, ONE_HUNDRED_PERCENT, RATE_SCALING_FACTOR} from '../../libraries/DataTypes.sol';
import {UntangledBase} from '../../base/UntangledBase.sol';
import {PoolNAVLogic} from '../../libraries/logic/PoolNAVLogic.sol';
import {PoolAssetLogic} from '../../libraries/logic/PoolAssetLogic.sol';
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
    event Repay(address poolAddress, uint256 increaseInterestRepay, uint256 increasePrincipalRepay, uint256 timestamp);

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

        setMinFirstLossCushion(newPoolParams.minFirstLossCushion);
        setDebtCeiling(newPoolParams.debtCeiling);

        require(
            INoteToken(newPoolParams.currency).approve(address(this), type(uint256).max),
            'Pool: Currency approval failed'
        );

        registry.getLoanAssetToken().setApprovalForAll(address(registry.getLoanKernel()), true);
    }

    function getNFTAssetsLength() external view returns (uint256) {
        return _poolStorage.nftAssets.length;
    }

    /// @notice A view function that returns an array of token asset addresses
    function getTokenAssetAddresses() external view returns (address[] memory) {
        return _poolStorage.tokenAssetAddresses;
    }

    /// @notice Riks scores length
    /// @return the length of the risk scores array
    function getRiskScoresLength() external view returns (uint256) {
        return _poolStorage.riskScores.length;
    }

    function riskScores(uint256 index) external view returns (DataTypes.RiskScore memory) {
        return _poolStorage.riskScores[index];
    }

    function capitalReserve() external view returns (uint256) {
        return _poolStorage.capitalReserve;
    }

    function incomeReserve() external view returns (uint256) {
        return _poolStorage.incomeReserve;
    }

    function nftAssets(uint256 idx) external view returns (DataTypes.NFTAsset memory) {
        return _poolStorage.nftAssets[idx];
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
        uint256 juniorRatio = calcJuniorRatio();

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

        uint256 totalInterestRepay;
        uint256 totalPrincipalRepay;

        for (uint256 i; i < numberOfLoans; i++) {
            uint256 interestAmount = previousDebts[i] - lastOutstandingDebt[i];

            if (repayAmounts[i] <= interestAmount) {
                totalInterestRepay += repayAmounts[i];
            } else {
                totalInterestRepay += interestAmount;
                totalPrincipalRepay += repayAmounts[i] - interestAmount;
            }
        }

        _poolStorage.incomeReserve += totalInterestRepay;
        _poolStorage.capitalReserve += totalPrincipalRepay;

        uint256 jotIncomeAmt = (totalInterestRepay * juniorRatio) / ONE_HUNDRED_PERCENT;
        uint256 sotIncomeAmt = totalInterestRepay - jotIncomeAmt;

        // Increase income for each type of token
        INoteToken(_poolStorage.sotToken).increaseIncome(sotIncomeAmt);
        INoteToken(_poolStorage.jotToken).increaseIncome(jotIncomeAmt);

        emit Repay(address(this), totalInterestRepay, totalPrincipalRepay, block.timestamp);
        return (repayAmounts, previousDebts);
    }

    function getRepaidAmount() external view returns (uint256, uint256) {
        return (_poolStorage.totalPrincipalRepaid, _poolStorage.totalInterestRepaid);
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

    function setPot(address _pot) external whenNotPaused nonReentrant requirePoolAdminOrOwner {
        GenericLogic.setPot(_poolStorage, _pot);
        registry.getSecuritizationManager().registerPot(_pot);
    }

    /// @notice sets debt ceiling value
    function setDebtCeiling(uint256 _debtCeiling) public whenNotPaused requirePoolAdminOrOwner {
        _poolStorage.debtCeiling = _debtCeiling;
        emit UpdateDebtCeiling(_debtCeiling);
    }

    /// @notice sets mint first loss value
    function setMinFirstLossCushion(uint32 _minFirstLossCushion) public whenNotPaused requirePoolAdminOrOwner {
        require(
            _minFirstLossCushion <= 100 * RATE_SCALING_FACTOR,
            'SecuritizationPool: minFirstLossCushion is greater than 100'
        );

        _poolStorage.minFirstLossCushion = _minFirstLossCushion;
        emit UpdateMintFirstLoss(_minFirstLossCushion);
    }

    function pot() external view returns (address) {
        return _poolStorage.pot;
    }

    /// @dev trigger update reserve when buy note token action happens
    function increaseCapitalReserve(uint256 currencyAmount) external whenNotPaused {
        require(
            _msgSender() == address(registry.getEpochExecutor()),
            // _msgSender() == address(registry.getNoteTokenVault()),
            'SecuritizationPool: Caller must be EpochExecutor'
        );
        GenericLogic.increaseCapitalReserve(_poolStorage, currencyAmount);
    }

    /// @dev trigger update reserve
    function decreaseIncomeReserve(uint256 currencyAmount) external whenNotPaused {
        require(
            _msgSender() == address(registry.getEpochExecutor()),
            // _msgSender() == address(registry.getNoteTokenVault()),
            'SecuritizationPool: Caller must be EpochExecutor'
        );
        GenericLogic.decreaseIncomeReserve(_poolStorage, currencyAmount);
    }

    function decreaseCapitalReserve(uint256 currencyAmount) external whenNotPaused {
        require(
            _msgSender() == address(registry.getEpochExecutor()),
            // _msgSender() == address(registry.getNoteTokenVault())
            'SecuritizationPool: Caller must be EpochExecutor '
        );
        GenericLogic.decreaseCapitalReserve(_poolStorage, currencyAmount);
    }

    function sotToken() public view returns (address) {
        return registry.getSeniorTokenManager().getTokenAddress(address(this));
    }

    function jotToken() public view returns (address) {
        return registry.getJuniorTokenManager().getTokenAddress(address(this));
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
        _poolStorage.interestRateSOT = _newRate;
        emit UpdateInterestRateSot(_newRate);
    }

    function minFirstLossCushion() external view returns (uint32) {
        return _poolStorage.minFirstLossCushion;
    }

    // Total $ (cUSD) paid for Asset repayment - repayInBatch
    function totalAssetRepaidCurrency() external view returns (uint256) {
        return _poolStorage.totalAssetRepaidCurrency;
    }

    function injectNoteToken() external whenNotPaused {
        registry.requireSecuritizationManager(_msgSender());
        (address sotAddress, address jotAddress) = registry.getEpochExecutor().getNoteTokenAddress(address(this));
        _poolStorage.sotToken = sotAddress;
        _poolStorage.jotToken = jotAddress;
    }

    /// @dev trigger update asset value repaid
    function increaseTotalAssetRepaidCurrency(uint256 amount) external whenNotPaused {
        registry.requireLoanKernel(_msgSender());
        _poolStorage.totalAssetRepaidCurrency = _poolStorage.totalAssetRepaidCurrency + amount;
    }

    /// @dev Disburses a specified amount of currency to the given user.
    /// @param usr The address of the user to receive the currency.
    /// @param currencyAmount The amount of currency to disburse.
    function disburse(address usr, uint256 currencyAmount) external whenNotPaused {
        require(
            _msgSender() == address(registry.getEpochExecutor()),
            'SecuritizationPool: Caller must be EpochExecutor'
        );
        GenericLogic.disburse(_poolStorage, usr, currencyAmount);
    }

    function openingBlockTimestamp() external view returns (uint64) {
        return _poolStorage.openingBlockTimestamp;
    }

    /// @notice allows the originator to withdraw from reserve
    function withdraw(address to, uint256 amount) external whenNotPaused {
        registry.requireLoanKernel(_msgSender());
        require(hasRole(ORIGINATOR_ROLE, to), 'SecuritizationPool: Only Originator can drawdown');
        // require(!registry.getNoteTokenVault().redeemDisabled(address(this)), 'SecuritizationPool: withdraw paused');
        GenericLogic.withdraw(_poolStorage, to, amount);
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
                _msgSender() == address(registry.getEpochExecutor()),
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
        address jotTokenAddress = jotToken();
        address sotTokenAddress = sotToken();
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
