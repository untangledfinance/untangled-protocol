// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {ContextUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol';
import {ERC165Upgradeable} from '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol';
import {ReentrancyGuardUpgradeable} from '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import {PausableUpgradeable} from '../../base/PauseableUpgradeable.sol';
import {ERC20BurnableUpgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
import {IERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol';
import {Registry} from '../../storage/Registry.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {ISecuritizationTGE} from './ISecuritizationTGE.sol';
import {Configuration} from '../../libraries/Configuration.sol';
import {ISecuritizationPoolValueService} from './ISecuritizationPoolValueService.sol';
import {RegistryInjection} from './RegistryInjection.sol';
import {SecuritizationAccessControl} from './SecuritizationAccessControl.sol';
import {IMintedTGE} from '../note-sale/IMintedTGE.sol';
import {IFinalizableCrowdsale} from '../note-sale/crowdsale/IFinalizableCrowdsale.sol';
import {SecuritizationPoolStorage} from './SecuritizationPoolStorage.sol';
import {ISecuritizationPoolExtension, SecuritizationPoolExtension} from './SecuritizationPoolExtension.sol';
import {ISecuritizationPoolStorage} from './ISecuritizationPoolStorage.sol';
import {ICrowdSale} from '../note-sale/crowdsale/ICrowdSale.sol';

import {ORIGINATOR_ROLE} from './types.sol';

import {IPoolNAV} from './IPoolNAV.sol';
import {IPoolNAVFactory} from './IPoolNAVFactory.sol';

interface ICrowdSaleLike {
    function token() external view returns (address);
}

contract SecuritizationTGE is
    ERC165Upgradeable,
    RegistryInjection,
    ContextUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    SecuritizationAccessControl,
    SecuritizationPoolStorage,
    ISecuritizationTGE
{
    using ConfigHelper for Registry;

    function installExtension(
        bytes memory params
    ) public virtual override(SecuritizationAccessControl, SecuritizationPoolStorage) onlyCallInTargetPool {
        __SecuritizationTGE_init_unchained(abi.decode(params, (NewPoolParams)));
    }

    function __SecuritizationTGE_init_unchained(NewPoolParams memory params) internal {
        Storage storage $ = _getStorage();
        $.pot = address(this);
        $.state = CycleState.INITIATED;

        $.underlyingCurrency = params.currency;
        $.minFirstLossCushion = params.minFirstLossCushion;
        $.debtCeiling = params.debtCeiling;
    }

    // alias
    function sotToken() public view override returns (address) {
        // return _getStorage().sotToken;
        address tge = tgeAddress();
        if (tge == address(0)) return address(0);
        return ICrowdSaleLike(tge).token();
    }

    // alias
    function jotToken() public view override returns (address) {
        // return _getStorage().jotToken;
        address tge = secondTGEAddress();
        if (tge == address(0)) return address(0);
        return ICrowdSaleLike(tge).token();
    }

    function underlyingCurrency() public view override returns (address) {
        return _getStorage().underlyingCurrency;
    }

    function reserve() public view override returns (uint256) {
        return _getStorage().reserve;
    }

    function minFirstLossCushion() public view override returns (uint32) {
        return _getStorage().minFirstLossCushion;
    }

    function termLengthInSeconds() public view override returns (uint64) {
        return _getStorage().termLengthInSeconds;
    }

    function paidPrincipalAmountSOT() public view override returns (uint256) {
        return _getStorage().paidPrincipalAmountSOT;
    }

    function principalAmountSOT() public view override returns (uint256) {
        return _getStorage().principalAmountSOT;
    }

    function debtCeiling() public view override returns (uint256) {
        return _getStorage().debtCeiling;
    }

    function interestRateSOT() public view override returns (uint32) {
        return _getStorage().interestRateSOT;
    }

    function paidPrincipalAmountSOTByInvestor(address user) public view override returns (uint256) {
        return _getStorage().paidPrincipalAmountSOTByInvestor[user];
    }

    function totalAssetRepaidCurrency() public view override returns (uint256) {
        return _getStorage().totalAssetRepaidCurrency;
    }

    modifier finishRedemptionValidator() {
        require(hasFinishedRedemption(), 'SecuritizationPool: Redemption has not finished');
        _;
    }

    /// @inheritdoc ISecuritizationTGE
    function injectTGEAddress(
        address _tgeAddress,
        Configuration.NOTE_TOKEN_TYPE _noteType
    ) external override whenNotPaused onlyIssuingTokenStage {
        registry().requireSecuritizationManager(_msgSender());

        require(_tgeAddress != address(0), 'SecuritizationPool: Address zero');
        address _tokenAddress = ICrowdSaleLike(_tgeAddress).token();
        require(_tokenAddress != address(0), 'SecuritizationPool: Address zero');

        Storage storage $ = _getStorage();

        if (_noteType == Configuration.NOTE_TOKEN_TYPE.SENIOR) {
            $.tgeAddress = _tgeAddress;
            $.sotToken = _tokenAddress;
        } else {
            $.secondTGEAddress = _tgeAddress;
            $.jotToken = _tokenAddress;
        }

        $.state = CycleState.CROWDSALE;

        emit UpdateTGEAddress(_tgeAddress, _noteType);
    }

    /// @notice allows the redemption of tokens
    function redeem(
        address usr,
        address notesToken,
        uint256 currencyAmount,
        uint256 tokenAmount
    ) external virtual override {
        require(
            _msgSender() == address(registry().getDistributionTranche()),
            'SecuritizationPool: Caller must be DistributionTranche'
        );

        Storage storage $ = _getStorage();

        if (sotToken() == notesToken) {
            $.paidPrincipalAmountSOTByInvestor[usr] += currencyAmount;
            emit UpdatePaidPrincipalAmountSOTByInvestor(usr, currencyAmount);
        }

        $.reserve = $.reserve - currencyAmount;

        if (tokenAmount > 0) {
            ERC20BurnableUpgradeable(notesToken).burn(tokenAmount);
        }

        require(checkMinFirstLost(), 'MinFirstLoss is not satisfied');
        require(
            IERC20Upgradeable($.underlyingCurrency).transferFrom($.pot, usr, currencyAmount),
            'SecuritizationPool: currency-transfer-failed'
        );

        emit UpdateReserve($.reserve);
    }

    /// @inheritdoc ISecuritizationTGE
    function disburse(address usr, uint256 currencyAmount) external virtual override {
        Storage storage $ = _getStorage();
        require(
            _msgSender() == address(registry().getNoteTokenVault()),
            'SecuritizationPool: Caller must be NoteTokenVault'
        );
        require(
            IERC20Upgradeable($.underlyingCurrency).transferFrom($.pot, usr, currencyAmount),
            'SecuritizationPool: currency-transfer-failed'
        );
    }

    function checkMinFirstLost() public view virtual returns (bool) {
        ISecuritizationPoolValueService poolService = registry().getSecuritizationPoolValueService();
        return _getStorage().minFirstLossCushion <= poolService.getJuniorRatio(address(this));
    }

    function isDebtCeilingValid() public view virtual override returns (bool) {
        Storage storage $ = _getStorage();
        uint256 totalDebt = 0;
        if ($.tgeAddress != address(0)) {
            totalDebt += ICrowdSale($.tgeAddress).currencyRaised();
        }
        if ($.secondTGEAddress != address(0)) {
            totalDebt += ICrowdSale($.secondTGEAddress).currencyRaised();
        }
        return $.debtCeiling >= totalDebt;
    }

    // Increase by value
    function increaseTotalAssetRepaidCurrency(uint256 amount) external virtual override whenNotPaused {
        registry().requireLoanRepaymentRouter(_msgSender());

        Storage storage $ = _getStorage();

        $.reserve = $.reserve + amount;
        $.totalAssetRepaidCurrency = $.totalAssetRepaidCurrency + amount;

        emit UpdateReserve($.reserve);
    }

    function hasFinishedRedemption() public view override returns (bool) {
        address stoken = sotToken();
        if (stoken != address(0)) {
            require(IERC20Upgradeable(stoken).totalSupply() == 0, 'SecuritizationPool: SOT still remain');
        }

        address jtoken = jotToken();
        if (jtoken != address(0)) {
            require(IERC20Upgradeable(jtoken).totalSupply() == 0, 'SecuritizationPool: JOT still remain');
        }

        return true;
    }

    function setPot(address _pot) external override whenNotPaused nonReentrant notClosingStage {
        registry().requirePoolAdminOrOwner(address(this), _msgSender());

        Storage storage $ = _getStorage();

        require($.pot != _pot, 'SecuritizationPool: Same address with current pot');
        $.pot = _pot;

        if (_pot == address(this)) {
            require(
                IERC20Upgradeable($.underlyingCurrency).approve(_pot, type(uint256).max),
                'SecuritizationPool: Pot not approved'
            );
        }
        registry().getSecuritizationManager().registerPot(_pot);
    }

    function setMinFirstLossCushion(uint32 _minFirstLossCushion) external override whenNotPaused notClosingStage {
        registry().requirePoolAdminOrOwner(address(this), _msgSender());

        Storage storage $ = _getStorage();
        $.minFirstLossCushion = _minFirstLossCushion;
        emit UpdateDebtCeiling(_minFirstLossCushion);
    }

    function setDebtCeiling(uint256 _debtCeiling) external override whenNotPaused notClosingStage {
        registry().requirePoolAdminOrOwner(address(this), _msgSender());

        Storage storage $ = _getStorage();
        $.debtCeiling = _debtCeiling;
        require(isDebtCeilingValid(), 'SecuritizationPool: Debt ceiling is not valid');
        emit UpdateDebtCeiling(_debtCeiling);
    }

    function setUpPoolNAV() public override {
        require(poolNAV() == address(0), 'SecuritizationPool: PoolNAV already set');
        IPoolNAVFactory poolNAVFactory = registry().getPoolNAVFactory();
        require(address(poolNAVFactory) != address(0), 'Pool NAV Factory was not registered');
        address poolNAVAddress = poolNAVFactory.createPoolNAV();
        Storage storage $ = _getStorage();
        $.poolNAV = poolNAVAddress;

        emit UpdatePoolNAV(poolNAVAddress);
    }

    function increaseReserve(uint256 currencyAmount) external override whenNotPaused {
        require(
            _msgSender() == address(registry().getSecuritizationManager()) ||
                _msgSender() == address(registry().getDistributionOperator()),
            'SecuritizationPool: Caller must be SecuritizationManager or DistributionOperator'
        );

        Storage storage $ = _getStorage();

        $.reserve = $.reserve + currencyAmount;
        require(checkMinFirstLost(), 'MinFirstLoss is not satisfied');

        emit UpdateReserve($.reserve);
    }

    function decreaseReserve(uint256 currencyAmount) external override whenNotPaused {
        require(
            _msgSender() == address(registry().getSecuritizationManager()) ||
                _msgSender() == address(registry().getDistributionOperator()) ||
                _msgSender() == address(registry().getNoteTokenVault()),
            'SecuritizationPool: Caller must be SecuritizationManager or DistributionOperator'
        );

        Storage storage $ = _getStorage();
        $.reserve = $.reserve - currencyAmount;
        require(checkMinFirstLost(), 'MinFirstLoss is not satisfied');

        emit UpdateReserve($.reserve);
    }

    function setInterestRateForSOT(uint32 _interestRateSOT) external override whenNotPaused {
        Storage storage $ = _getStorage();
        require(_msgSender() == $.tgeAddress, 'SecuritizationPool: Only tge can update interest');

        $.interestRateSOT = _interestRateSOT;
        emit UpdateInterestRateSOT(_interestRateSOT);
    }

    // After closed pool and redeem all not -> get remain cash to recipient wallet
    function claimCashRemain(
        address recipientWallet
    ) external override whenNotPaused onlyOwner finishRedemptionValidator {
        Storage storage $ = _getStorage();

        IERC20Upgradeable currency = IERC20Upgradeable($.underlyingCurrency);
        require(
            currency.transferFrom($.pot, recipientWallet, currency.balanceOf($.pot)),
            'SecuritizationPool: Transfer failed'
        );
    }

    function startCycle(
        uint64 _termLengthInSeconds,
        uint256 _principalAmountForSOT,
        uint32 _interestRateForSOT,
        uint64 _timeStartEarningInterest
    ) external override whenNotPaused nonReentrant onlyOwner onlyIssuingTokenStage {
        require(_termLengthInSeconds > 0, 'SecuritizationPool: Term length is 0');

        Storage storage $ = _getStorage();

        $.termLengthInSeconds = _termLengthInSeconds;

        $.principalAmountSOT = _principalAmountForSOT;

        $.state = CycleState.OPEN;

        if ($.tgeAddress != address(0)) {
            IMintedTGE mintedTokenGenerationEvent = IMintedTGE($.tgeAddress);
            mintedTokenGenerationEvent.setupLongSale(
                _interestRateForSOT,
                _termLengthInSeconds,
                _timeStartEarningInterest
            );
            if (!IFinalizableCrowdsale($.tgeAddress).finalized()) {
                IFinalizableCrowdsale($.tgeAddress).finalize(false, $.pot);
            }
            $.interestRateSOT = mintedTokenGenerationEvent.pickedInterest();
        }
        if ($.secondTGEAddress != address(0)) {
            IFinalizableCrowdsale($.secondTGEAddress).finalize(false, $.pot);
            require(
                IFinalizableCrowdsale($.secondTGEAddress).finalized(),
                'SecuritizationPool: second sale is still on going'
            );
        }
    }

    function withdraw(address to, uint256 amount) public override whenNotPaused {
        registry().requireLoanKernel(_msgSender());
        require(hasRole(ORIGINATOR_ROLE, to), 'SecuritizationPool: Only Originator can drawdown');
        require(!registry().getNoteTokenVault().redeemDisabled(address(this)), 'SecuritizationPool: withdraw paused');
        Storage storage $ = _getStorage();
        require($.reserve >= amount, 'SecuritizationPool: not enough reserve');

        $.reserve = $.reserve - amount;

        require(checkMinFirstLost(), 'MinFirstLoss is not satisfied');
        require(
            IERC20Upgradeable(underlyingCurrency()).transferFrom(pot(), to, amount),
            'SecuritizationPool: Transfer failed'
        );
        emit Withdraw(to, amount);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC165Upgradeable, SecuritizationAccessControl, SecuritizationPoolStorage)
        returns (bool)
    {
        return interfaceId == type(ISecuritizationTGE).interfaceId || super.supportsInterface(interfaceId);
    }

    function pause() public virtual {
        registry().requirePoolAdminOrOwner(address(this), _msgSender());
        _pause();
    }

    function unpause() public virtual {
        registry().requirePoolAdminOrOwner(address(this), _msgSender());
        _unpause();
    }

    function getFunctionSignatures()
        public
        view
        virtual
        override(SecuritizationAccessControl, SecuritizationPoolStorage)
        returns (bytes4[] memory)
    {
        bytes4[] memory _functionSignatures = new bytes4[](32);

        _functionSignatures[0] = this.termLengthInSeconds.selector;
        _functionSignatures[1] = this.setPot.selector;
        _functionSignatures[2] = this.increaseReserve.selector;
        _functionSignatures[3] = this.decreaseReserve.selector;
        _functionSignatures[4] = this.sotToken.selector;
        _functionSignatures[5] = this.jotToken.selector;
        _functionSignatures[6] = this.underlyingCurrency.selector;
        _functionSignatures[7] = this.paidPrincipalAmountSOT.selector;
        _functionSignatures[8] = this.paidPrincipalAmountSOTByInvestor.selector;
        _functionSignatures[9] = this.reserve.selector;
        _functionSignatures[10] = this.principalAmountSOT.selector;
        _functionSignatures[11] = this.interestRateSOT.selector;
        _functionSignatures[12] = this.minFirstLossCushion.selector;
        _functionSignatures[13] = this.totalAssetRepaidCurrency.selector;
        _functionSignatures[14] = this.injectTGEAddress.selector;
        _functionSignatures[15] = this.increaseTotalAssetRepaidCurrency.selector;
        _functionSignatures[16] = this.redeem.selector;
        _functionSignatures[17] = this.hasFinishedRedemption.selector;
        _functionSignatures[18] = this.setInterestRateForSOT.selector;
        _functionSignatures[19] = this.claimCashRemain.selector;
        _functionSignatures[20] = this.startCycle.selector;
        _functionSignatures[21] = this.withdraw.selector;
        _functionSignatures[22] = this.supportsInterface.selector;
        _functionSignatures[23] = this.paused.selector;
        _functionSignatures[24] = this.pause.selector;
        _functionSignatures[25] = this.unpause.selector;
        _functionSignatures[26] = this.setUpPoolNAV.selector;
        _functionSignatures[27] = this.isDebtCeilingValid.selector;
        _functionSignatures[28] = this.setDebtCeiling.selector;
        _functionSignatures[29] = this.debtCeiling.selector;
        _functionSignatures[30] = this.disburse.selector;
        _functionSignatures[31] = this.setMinFirstLossCushion.selector;

        return _functionSignatures;
    }
}
