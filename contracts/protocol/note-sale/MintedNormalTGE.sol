// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import '../../base/UntangledBase.sol';
import '@openzeppelin/contracts/interfaces/IERC20.sol';
import {Registry} from '../../storage/Registry.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {IPool} from '../../interfaces/IPool.sol';
import {IMintedNormalTGE} from '../../interfaces/IMintedNormalTGE.sol';
import '../../interfaces/INoteToken.sol';

/// @title MintedNormalTGE
/// @author Untangled Team
/// @dev Note sale for JOT
contract MintedNormalTGE is IMintedNormalTGE, UntangledBase {
    using ConfigHelper for Registry;

    Registry public registry;

    /// @dev Pool address which this sale belongs to
    address public pool;

    bool public hasStarted;

    /// @dev The token being sold
    address public token;

    /// @dev The token being sold
    address public currency;

    /// @dev Timestamp at which the first asset is collected to pool
    uint256 public firstNoteTokenMintedTimestamp;

    /// @dev Amount of currency raised
    uint256 internal _currencyRaised;

    /// @dev Amount of token raised
    uint256 public tokenRaised;

    /// @dev Target raised currency amount
    uint256 public totalCap;

    /// @dev Minimum currency bid amount for note token
    uint256 public minBidAmount;

    uint256 public initialAmount;

    mapping(address => uint256) public _currencyRaisedByInvestor;

    function initialize(Registry _registry, address _pool, address _token, address _currency) public initializer {
        __UntangledBase__init_unchained(_msgSender());
        require(_pool != address(0), 'Pool address cannot be empty');
        require(_token != address(0), 'Token address cannot be empty');
        require(_currency != address(0), 'Currency address cannot be empty');
        registry = _registry;
        pool = _pool;
        token = _token;
        currency = _currency;
    }

    modifier securitizationPoolRestricted() {
        require(_msgSender() == pool, 'MintedNormalTGE: Caller must be pool');
        _;
    }

    modifier smpRestricted() {
        require(
            _msgSender() == address(registry.getSecuritizationManager()),
            'MintedNormalTGE: Caller must be securitization manager'
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
            'MintedNormalTGE: caller must be owner or manager'
        );
        minBidAmount = _minBidAmount;
        emit UpdateMinBidAmount(_minBidAmount);
    }

    /// @notice Set hasStarted variable
    function setHasStarted(bool _hasStarted) public {
        require(
            hasRole(OWNER_ROLE, _msgSender()) || _msgSender() == address(registry.getSecuritizationManager()),
            'MintedNormalTGE: caller must be owner or manager'
        );
        hasStarted = _hasStarted;

        emit SetHasStarted(hasStarted);
    }

    /// @notice Catch event redeem token
    /// @param currencyAmount amount of currency investor want to redeem
    function onRedeem(uint256 currencyAmount) public virtual override {
        require(
            _msgSender() == address(registry.getNoteTokenVault()),
            'MintedNormalTGE: Caller must be Note token vault'
        );
        _currencyRaised -= currencyAmount;
    }

    /// @notice Retrieves the remaining token balance held by the MintedNormalTGE contract
    function getTokenRemainAmount() public view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function getTokenPrice() public view returns (uint256) {
        return registry.getSecuritizationPoolValueService().calcTokenPrice(pool, token);
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
        require(hasStarted, 'MintedNormalTGE: sale not started');
        require(currencyAmount >= minBidAmount, 'MintedNormalTGE: Less than minBidAmount');
        require(beneficiary != address(0), 'MintedNormalTGE: beneficiary is zero address');
        require(tokenAmount != 0, 'MintedNormalTGE: token amount is 0');
        require(isUnderTotalCap(currencyAmount), 'MintedNormalTGE: cap exceeded');
    }

    /// @dev Mints and delivers tokens to the beneficiary
    function _deliverTokens(address beneficiary, uint256 tokenAmount) internal {
        INoteToken noteToken = INoteToken(token);
        if (noteToken.noteTokenType() == uint8(Configuration.NOTE_TOKEN_TYPE.SENIOR) && noteToken.totalSupply() == 0) {
            firstNoteTokenMintedTimestamp = block.timestamp;
            IPool(pool).setUpOpeningBlockTimestamp();
        }
        noteToken.mint(beneficiary, tokenAmount);
    }

    /// @dev Transfers the currency from the payer to the MintedNormalTGE contract
    function _claimPayment(address payee, uint256 currencyAmount) internal {
        require(
            IERC20(currency).transferFrom(payee, address(this), currencyAmount),
            'Fail to transfer currency from payee to contract'
        );
    }

    /// @dev Transfers the currency funds from the MintedNormalTGE contract to the specified beneficiary
    function _forwardFunds(address beneficiary, uint256 currencyAmount) internal {
        require(IERC20(currency).transfer(beneficiary, currencyAmount), 'Fail to transfer currency to Beneficiary');
    }

    function currencyRaised() public view virtual override returns (uint256) {
        return _currencyRaised;
    }

    /// @notice Check if the total amount of currency raised is equal to the total cap
    function isDistributedFully() public view returns (bool) {
        return _currencyRaised == totalCap;
    }

    /// @notice Calculates the remaining amount of currency available for purchase
    function getCurrencyRemainAmount() public view virtual returns (uint256) {
        return totalCap - _currencyRaised;
    }

    function setTotalCap(uint256 cap_) external whenNotPaused {
        require(
            hasRole(OWNER_ROLE, _msgSender()) || _msgSender() == address(registry.getSecuritizationManager()),
            'MintedNormalTGE: Caller must be owner or manager'
        );
        _setTotalCap(cap_);
    }

    /// @dev Sets the total cap to the specified amount
    function _setTotalCap(uint256 cap) internal {
        require(cap > 0, 'MintedNormalTGE: cap is 0');
        require(cap >= _currencyRaised, 'MintedNormalTGE: cap is bellow currency raised');

        totalCap = cap;

        emit UpdateTotalCap(totalCap);
    }

    /// @notice Checks if the total amount of currency raised is greater than or equal to the total cap
    function totalCapReached() public view returns (bool) {
        return _currencyRaised >= totalCap;
    }

    /// @notice Checks if the sum of the current currency raised and the specified currency amount is less than or equal to the total cap
    function isUnderTotalCap(uint256 currencyAmount) public view returns (bool) {
        return _currencyRaised + currencyAmount <= totalCap;
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

        IPool securitizationPool = IPool(pool);
        require(securitizationPool.isDebtCeilingValid(), 'MintedNormalTGE: Exceeds Debt Ceiling');
        tokenRaised += tokenAmount;

        _claimPayment(payee, currencyAmount);
        _deliverTokens(beneficiary, tokenAmount);

        _forwardFunds(IPool(pool).pot(), currencyAmount);

        emit TokensPurchased(_msgSender(), beneficiary, currencyAmount, tokenAmount);

        return tokenAmount;
    }
}
