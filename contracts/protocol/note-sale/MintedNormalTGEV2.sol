// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import '../../base/UntangledBase.sol';
import '@openzeppelin/contracts/interfaces/IERC20.sol';
import {Registry} from '../../storage/Registry.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {ISecuritizationPool} from '../../interfaces/ISecuritizationPool.sol';
import {ISecuritizationPoolStorage} from '../../interfaces/ISecuritizationPoolStorage.sol';
import {ISecuritizationTGE} from '../../interfaces/ISecuritizationTGE.sol';
import {IMintedNormalTGEV2} from '../../interfaces/IMintedNormalTGEV2.sol';
import {LongSaleInterest} from './base/LongSaleInterest.sol';
import '../../interfaces/INoteToken.sol';
import '../../interfaces/ICrowdSale.sol';

/// @title MintedNormalTGE
/// @author Untangled Team
/// @dev Note sale for JOT
contract MintedNormalTGEV2 is IMintedNormalTGEV2, UntangledBase {
    using ConfigHelper for Registry;

    // To convert an encoded interest rate into its equivalent in percents,
    // divide it by INTEREST_RATE_SCALING_FACTOR_PERCENT -- e.g.
    //     10,000 => 1% interest rate
    /// @dev A constant used to convert an encoded interest rate into its equivalent in percentage.
    /// To convert an encoded interest rate to a percentage, divide it by this scaling factor
    uint256 public constant INTEREST_RATE_SCALING_FACTOR_PERCENT = 10 ** 4;

    /// @dev Pool address which this sale belongs to
    address public pool;

    /// @dev The token being sold
    address public token;

    /// @dev The token being sold
    address public currency;

    bool public hasStarted;

    uint256 public firstNoteTokenMintedTimestamp; // Timestamp at which the first asset is collected to pool

    /// @dev Amount of currency raised
    uint256 internal _currencyRaised;

    /// @dev Amount of token raised
    uint256 public tokenRaised;

    /// @dev Minimum currency bid amount for note token
    uint256 public minBidAmount;

    // How many token units a buyer gets per currency.
    uint256 public rate; // support by RATE_SCALING_FACTOR decimal numbers

    mapping(address => uint256) public _currencyRaisedByInvestor;

    Registry public registry;
    uint256 public interestRate;
    uint256 public initialAmount;

    function initialize(Registry _registry, address _pool, address _token, address _currency) public initializer {
        __UntangledBase__init_unchained(_msgSender());
        registry = _registry;
        pool = _pool;
        token = _token;
        currency = _currency;
    }

    modifier securitizationPoolRestricted() {
        require(_msgSender() == pool, 'MintedNormalTGEV2: Caller must be pool');
        _;
    }

    modifier smpRestricted() {
        require(
            _msgSender() == address(registry.getSecuritizationManager()),
            'MintedNormalTGEV2: Caller must be securitization manager'
        );
        _;
    }

    function currencyRaisedByInvestor(address investor) public view returns (uint256) {
        return _currencyRaisedByInvestor[investor];
    }

    /// @notice Setup minimum bid amount in currency for note token
    /// @param _minBidAmount Expected minimum amount
    function setMinBidAmount(uint256 _minBidAmount) external override whenNotPaused {
        require(
            hasRole(OWNER_ROLE, _msgSender()) || _msgSender() == address(registry.getSecuritizationManager()),
            'MintedNormalTGEV2: caller must be owner or manager'
        );
        minBidAmount = _minBidAmount;
        emit UpdateMinBidAmount(_minBidAmount);
    }

    /// @notice Set hasStarted variable
    function setHasStarted(bool _hasStarted) public {
        require(
            hasRole(OWNER_ROLE, _msgSender()) || _msgSender() == address(registry.getSecuritizationManager()),
            'MintedNormalTGEV2: caller must be owner or manager'
        );
        hasStarted = _hasStarted;

        emit SetHasStarted(hasStarted);
    }

    /// @notice Catch event redeem token
    /// @param currencyAmount amount of currency investor want to redeem
    function onRedeem(uint256 currencyAmount) public virtual override {
        require(
            _msgSender() == address(registry.getNoteTokenVault()),
            'MintedNormalTGEV2: Caller must be Note token vault'
        );
        _currencyRaised -= currencyAmount;
    }

    /// @notice Retrieves the remaining token balance held by the MintedNormalTGEV2 contract
    function getTokenRemainAmount() public view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function getTokenPrice() public view returns (uint256) {
        return registry.getDistributionAssessor().calcTokenPrice(pool, token);
    }

    function getTokenAmount(uint256 currencyAmount) public view returns (uint256) {
        uint256 tokenPrice = getTokenPrice();

        if (tokenPrice == 0) {
            return 0;
        }
        return (currencyAmount * 10 ** INoteToken(token).decimals()) / tokenPrice;
    }

    /// @notice Requires that the currency amount does not exceed the total cap
    function _preValidatePurchase(
        address beneficiary,
        uint256 currencyAmount,
        uint256 tokenAmount
    ) internal view virtual {
        require(hasStarted, 'MintedNormalTGEV2: sale not started');
        require(currencyAmount >= minBidAmount, 'MintedNormalTGEV2: Less than minBidAmount');
        require(beneficiary != address(0), 'MintedNormalTGEV2: beneficiary is zero address');
        require(tokenAmount != 0, 'MintedNormalTGEV2: token amount is 0');
    }

    /// @dev Mints and delivers tokens to the beneficiary
    function _deliverTokens(address beneficiary, uint256 tokenAmount) internal {
        INoteToken noteToken = INoteToken(token);
        if (noteToken.noteTokenType() == uint8(Configuration.NOTE_TOKEN_TYPE.SENIOR) && noteToken.totalSupply() == 0) {
            firstNoteTokenMintedTimestamp = block.timestamp;
            ISecuritizationPool(pool).setUpOpeningBlockTimestamp();
        }
        noteToken.mint(beneficiary, tokenAmount);
    }

    /// @dev Burns and delivers tokens to the beneficiary
    function _ejectTokens(uint256 tokenAmount) internal {
        INoteToken(token).burn(tokenAmount);
    }

    /// @dev Transfers the currency from the payer to the MintedNormalTGEV2 contract
    function _claimPayment(address payee, uint256 currencyAmount) internal {
        require(
            IERC20(currency).transferFrom(payee, address(this), currencyAmount),
            'Fail to transfer currency from payee to contract'
        );
    }

    /// @dev Transfers the currency funds from the MintedNormalTGEV2 contract to the specified beneficiary
    function _forwardFunds(address beneficiary, uint256 currencyAmount) internal {
        require(IERC20(currency).transfer(beneficiary, currencyAmount), 'Fail to transfer currency to Beneficiary');
    }

    function currencyRaised() public view virtual override returns (uint256) {
        return _currencyRaised;
    }

    function getInterest() public view override returns (uint256) {
        return interestRate;
    }

    function setInterestRate(uint256 _interestRate) external override whenNotPaused {
        require(
            hasRole(OWNER_ROLE, _msgSender()) || _msgSender() == address(registry.getSecuritizationManager()),
            'MintedNormalTGE: Caller must be owner or manager'
        );
        interestRate = _interestRate;
    }

    /// @notice Setup initial amount currency raised for JOT condition
    /// @param _initialAmount Expected minimum amount of JOT before SOT start
    function setInitialAmount(uint256 _initialAmount) external override whenNotPaused {
        require(
            hasRole(OWNER_ROLE, _msgSender()) || _msgSender() == address(registry.getSecuritizationManager()),
            'MintedNormalTGE: Caller must be owner or manager'
        );
        initialAmount = _initialAmount;
        emit UpdateInitialAmount(_initialAmount);
    }

    /// @notice  Allows users to buy note token
    /// @param payee pay for purchase
    /// @param beneficiary wallet receives note token
    /// @param currencyAmount amount of currency used for purchase
    function buyTokens(
        address payee,
        address beneficiary,
        uint256 currencyAmount
    ) public override whenNotPaused nonReentrant smpRestricted returns (uint256) {
        uint256 tokenAmount = getTokenAmount(currencyAmount);

        _preValidatePurchase(beneficiary, currencyAmount, tokenAmount);

        // update state
        _currencyRaised += currencyAmount;
        _currencyRaisedByInvestor[beneficiary] += currencyAmount;

        ISecuritizationTGE securitizationPool = ISecuritizationTGE(pool);
        require(securitizationPool.isDebtCeilingValid(), 'MintedNormalTGEV2: Exceeds Debt Ceiling');
        tokenRaised += tokenAmount;

        _claimPayment(payee, currencyAmount);
        _deliverTokens(beneficiary, tokenAmount);

        _forwardFunds(ISecuritizationPoolStorage(pool).pot(), currencyAmount);

        emit TokensPurchased(_msgSender(), beneficiary, currencyAmount, tokenAmount);

        return tokenAmount;
    }
}
