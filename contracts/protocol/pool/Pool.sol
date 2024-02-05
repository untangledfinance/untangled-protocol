// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {Registry} from '../../storage/Registry.sol';
import {OWNER_ROLE,ORIGINATOR_ROLE} from './types.sol';
import {PoolStorage} from './PoolStorage.sol';
import {DataTypes} from '../../libraries/DataTypes.sol';
import {UntangledBase} from "../../base/UntangledBase.sol";
import {PoolNAVLogic} from '../../libraries/logic/PoolNAVLogic.sol';
import {PoolAssetLogic} from '../../libraries/logic/PoolAssetLogic.sol';
import {TGELogic} from '../../libraries/logic/TGELogic.sol';
import {GenericLogic} from '../../libraries/logic/GenericLogic.sol';
import {Configuration} from '../../libraries/Configuration.sol';
/**
 * @title Untangled's SecuritizationPool contract
 * @notice Main entry point for senior LPs (a.k.a. capital providers)
 *  Automatically invests across borrower pools using an adjustable strategy.
 * @author Untangled Team
 */
contract Pool is PoolStorage, UntangledBase{
    using ConfigHelper for Registry;
    // using AddressUpgradeable for address;
    // using ERC165CheckerUpgradeable for address;
    // event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    Registry public registry;
    // }
    modifier onlyIssuingTokenStage() {
        DataTypes.CycleState _state = state();
        require(_state != DataTypes.CycleState.OPEN && _state != DataTypes.CycleState.CLOSED, 'Not in issuing token stage');
        _;
    }

    modifier notClosingStage() {
        require(!isClosedState(), 'SecuritizationPool: Pool in closed state');
        _;
    }

    /** CONSTRUCTOR */
    function initialize(address _registryAddress) public initializer {
        __UntangledBase__init(_msgSender());
        require(_registryAddress != address(0), 'Registry address cannot be empty');
        registry = Registry(_registryAddress);
    }
    function state() internal view returns(DataTypes.CycleState){
        return _poolStorage.state;
    }
    function isClosedState() internal view returns (bool) {
        return state() == DataTypes.CycleState.CLOSED;
    }
    function tgeAddress() public view returns (address) {
        return _poolStorage.tgeAddress;
    }
    function getNFTAssetsLength() external view returns (uint256){
        return _poolStorage.nftAssets.length;
    }

    /// @notice A view function that returns an array of token asset addresses
    function getTokenAssetAddresses() external view returns (address[] memory){
        return _poolStorage.tokenAssetAddresses;
    }

    /// @notice A view function that returns the length of the token asset addresses array
    function getTokenAssetAddressesLength() external view returns (uint256){
        return _poolStorage.tokenAssetAddresses.length;
    }

    /// @notice Riks scores length
    /// @return the length of the risk scores array
    function getRiskScoresLength() external view returns (uint256){
        return _poolStorage.riskScores.length;
    }

    function riskScores(uint256 index) external view returns (DataTypes.RiskScore memory){
        return _poolStorage.riskScores[index];
    }
    function nftAssets(uint256 idx) external view returns (DataTypes.NFTAsset memory){
        return _poolStorage.nftAssets[idx];
    }

    function tokenAssetAddresses(uint256 idx) external view returns (address){
        return _poolStorage.tokenAssetAddresses[idx];
    }
    /// @notice sets up the risk scores for the contract for pool
    function setupRiskScores(
        uint32[] calldata _daysPastDues,
        uint32[] calldata _ratesAndDefaults,
        uint32[] calldata _periodsAndWriteOffs
    ) external whenNotPaused notClosingStage{
        registry.requirePoolAdmin(_msgSender());
        PoolAssetLogic.setupRiskScores(_poolStorage,_daysPastDues,_ratesAndDefaults,_periodsAndWriteOffs);
    }

    /// @notice exports NFT assets to another pool address
    function exportAssets(address tokenAddress, address toPoolAddress, uint256[] calldata tokenIds) external whenNotPaused nonReentrant notClosingStage {
        registry.requirePoolAdminOrOwner(address(this), _msgSender());
        PoolAssetLogic.exportAssets(_poolStorage.nftAssets,tokenAddress,toPoolAddress,tokenIds);
    }

    /// @notice withdraws NFT assets from the contract and transfers them to recipients
    function withdrawAssets(
        address[] calldata tokenAddresses,
        uint256[] calldata tokenIds,
        address[] calldata recipients
    ) external whenNotPaused onlyRole(OWNER_ROLE){
        PoolAssetLogic.withdrawAssets(_poolStorage.nftAssets,tokenAddresses,tokenIds,recipients);
    }

    /// @notice collects NFT assets from a specified address
    function collectAssets(uint256[] calldata tokenIds, DataTypes.LoanEntry[] calldata loanEntries) external whenNotPaused returns (uint256){
        registry.requireLoanKernel(_msgSender());
        return PoolAssetLogic.collectAssets(_poolStorage,tokenIds,loanEntries);
    }

    /// @notice collects ERC20 assets from specified senders
    function collectERC20Asset(address tokenAddresss) external whenNotPaused notClosingStage{
        registry.requireSecuritizationManager(_msgSender());
        PoolAssetLogic.collectERC20Asset(_poolStorage,tokenAddresss);
    }

    /// @notice withdraws ERC20 assets from the contract and transfers them to recipients\
    function withdrawERC20Assets(
        address[] calldata tokenAddresses,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external whenNotPaused nonReentrant{
        registry.requirePoolAdminOrOwner(address(this), _msgSender());
        PoolAssetLogic.withdrawERC20Assets(_poolStorage.existsTokenAssetAddress,tokenAddresses,recipients,amounts);
    }

    /// @dev Trigger set up opening block timestamp
    function setUpOpeningBlockTimestamp() external{
        require(_msgSender() == tgeAddress(), 'SecuritizationPool: Only tge address');
        PoolAssetLogic.setUpOpeningBlockTimestamp(_poolStorage);
    }  

    /*==================== NAV ====================*/
    function addLoan(uint256 loan, DataTypes.LoanEntry calldata loanEntry) private returns (uint256){
        return PoolNAVLogic.addLoan(_poolStorage,loan,loanEntry);
    }

    function repayLoan(uint256 loan, uint256 amount) external returns (uint256){
        require(address(registry.getLoanRepaymentRouter()) == msg.sender, 'not authorized');
        return PoolNAVLogic.repayLoan(_poolStorage,loan,amount);
    }

    function file(bytes32 name, uint256 value) private{
        PoolNAVLogic.file(_poolStorage,name,value);
    }

    function file(
        bytes32 name,
        uint256 rate_,
        uint256 writeOffPercentage_,
        uint256 overdueDays_,
        uint256 penaltyRate_,
        uint256 riskIndex
    ) private{
        PoolNAVLogic.file(_poolStorage,name,rate_,writeOffPercentage_,overdueDays_,penaltyRate_,riskIndex);
    }

    function debt(uint256 loan) external view returns (uint256 loanDebt){
        return GenericLogic.debt(_poolStorage,loan);
    }

    function risk(bytes32 nft_) external view returns (uint256 risk_){
        return uint256(_poolStorage.details[nft_].risk);
    }

    /// @notice calculates and returns the current NAV
    /// @return nav_ current NAV
    function currentNAV() external view returns (uint256 nav_){
        return GenericLogic.currentNAV(_poolStorage);
    }

    function currentNAVAsset(bytes32 tokenId) external view returns (uint256){
        return GenericLogic.currentNAVAsset(_poolStorage,tokenId);
    }

    function futureValue(bytes32 nft_) external view returns (uint256){
        return uint256(_poolStorage.details[nft_].futureValue);
    }

    function maturityDate(bytes32 nft_) external view returns (uint256){
        return uint256(_poolStorage.details[nft_].maturityDate);
    }

    function discountRate() external view returns (uint256){
        return uint256(_poolStorage.discountRate);
    }

    function updateAssetRiskScore(bytes32 nftID_, uint256 risk_) external{
        registry.requirePoolAdmin(_msgSender());
        PoolNAVLogic.updateAssetRiskScore(_poolStorage,nftID_,risk_);
    }

    /// @notice retrieves loan information
    function getAsset(bytes32 agreementId) external view returns (DataTypes.NFTDetails memory){
        return _poolStorage.details[agreementId];
    }
    /*==================== TGE ====================*/
    function setPot(address _pot) external whenNotPaused nonReentrant notClosingStage {
        registry.requirePoolAdminOrOwner(address(this), _msgSender());
        TGELogic.setPot(_poolStorage,_pot);
    }

    /// @notice sets debt ceiling value
    function setDebtCeiling(uint256 _debtCeiling) external whenNotPaused notClosingStage{
        registry.requirePoolAdminOrOwner(address(this), _msgSender());
        TGELogic.setDebtCeiling(_poolStorage,_debtCeiling);
    }

    /// @notice sets mint first loss value
    function setMinFirstLossCushion(uint32 _minFirstLossCushion) external whenNotPaused notClosingStage{
        registry.requirePoolAdminOrOwner(address(this), _msgSender());
        TGELogic.setMinFirstLossCushion(_poolStorage,_minFirstLossCushion);
    }

    // function pot() external view returns (address);

    /// @dev trigger update reserve when buy note token action happens
    function increaseReserve(uint256 currencyAmount) external whenNotPaused{
        require(
            _msgSender() == address(registry.getSecuritizationManager()) ||
                _msgSender() == address(registry.getNoteTokenVault()),
            'SecuritizationPool: Caller must be SecuritizationManager or NoteTokenVault'
        );
        address poolServiceAddress = address(registry.getSecuritizationPoolValueService());
        TGELogic.increaseReserve(_poolStorage,poolServiceAddress,currencyAmount);
    }

    /// @dev trigger update reserve
    function decreaseReserve(uint256 currencyAmount) external whenNotPaused{
        require(
            _msgSender() == address(registry.getSecuritizationManager()) ||
                _msgSender() == address(registry.getNoteTokenVault()),
            'SecuritizationPool: Caller must be SecuritizationManager or DistributionOperator'
        );
        address poolServiceAddress = address(registry.getSecuritizationPoolValueService());
        TGELogic.decreaseReserve(_poolStorage,poolServiceAddress,currencyAmount);
    }

    // function tgeAddress() external view returns (address);

    // function secondTGEAddress() external view returns (address);

    function sotToken() external view returns (address){
        TGELogic.sotToken(_poolStorage);
    }

    function jotToken() external view returns (address){
        TGELogic.jotToken(_poolStorage);
    }

    function underlyingCurrency() external view returns (address){
        return _poolStorage.underlyingCurrency;
    }

    function paidPrincipalAmountSOT() external view returns (uint256){
        return _poolStorage.paidPrincipalAmountSOT;
    }

    function paidPrincipalAmountSOTByInvestor(address user) external view returns (uint256){
        return _poolStorage.paidPrincipalAmountSOTByInvestor[user];
    }

    function reserve() external view returns (uint256){
        return _poolStorage.reserve;
    }

    function debtCeiling() external view returns (uint256){
        return _poolStorage.debtCeiling;
    }

    // Annually, support 4 decimals num
    function interestRateSOT() external view returns (uint32){
        return _poolStorage.interestRateSOT;
    } 

    function minFirstLossCushion() external view returns (uint32){
        return _poolStorage.minFirstLossCushion;
    }

     // Total $ (cUSD) paid for Asset repayment - repayInBatch
    function totalAssetRepaidCurrency() external view returns (uint256){
        return _poolStorage.totalAssetRepaidCurrency;
    }

    /// @notice injects the address of the Token Generation Event (TGE) and the associated token address
    function injectTGEAddress(
        address _tgeAddress,
        // address _tokenAddress,
        Configuration.NOTE_TOKEN_TYPE _noteToken
    ) external whenNotPaused onlyIssuingTokenStage {
        registry.requireSecuritizationManager(_msgSender());
        TGELogic.injectTGEAddress(_poolStorage,_tgeAddress,_noteToken);
    }

    /// @dev trigger update asset value repaid
    function increaseTotalAssetRepaidCurrency(uint256 amount) external whenNotPaused{
        registry.requireLoanRepaymentRouter(_msgSender());
        TGELogic.increaseTotalAssetRepaidCurrency(_poolStorage,amount);
    }

    /// @dev Disburses a specified amount of currency to the given user.
    /// @param usr The address of the user to receive the currency.
    /// @param currencyAmount The amount of currency to disburse.
    function disburse(address usr, uint256 currencyAmount) external whenNotPaused{
        require(
            _msgSender() == address(registry.getNoteTokenVault()),
            'SecuritizationPool: Caller must be NoteTokenVault'
        );
        TGELogic.disburse(_poolStorage,usr,currencyAmount);
    }

    /// @notice checks if the redemption process has finished
    function hasFinishedRedemption() external view returns (bool){
        TGELogic.hasFinishedRedemption(_poolStorage);
    }

    ///@notice check current debt ceiling is valid
    function isDebtCeilingValid() external view returns (bool){
        TGELogic.isDebtCeilingValid(_poolStorage);
    }

    function claimCashRemain(address recipientWallet) external whenNotPaused onlyRole(OWNER_ROLE) {
        require(TGELogic.hasFinishedRedemption(_poolStorage), 'SecuritizationPool: Redemption has not finished');
        TGELogic.claimCashRemain(_poolStorage,recipientWallet);
    }

    // function openingBlockTimestamp() external view returns (uint64);

    function startCycle() external whenNotPaused nonReentrant onlyIssuingTokenStage{
        TGELogic.startCycle(_poolStorage);
    }

    /// @notice allows the originator to withdraw from reserve
    function withdraw(address to, uint256 amount) external whenNotPaused onlyRole(ORIGINATOR_ROLE){
        registry.requireLoanKernel(_msgSender());
        require(!registry.getNoteTokenVault().redeemDisabled(address(this)), 'SecuritizationPool: withdraw paused');
        address poolServiceAddress = address(registry.getSecuritizationPoolValueService());
        TGELogic.withdraw(_poolStorage,poolServiceAddress,to,amount);
    }
}
