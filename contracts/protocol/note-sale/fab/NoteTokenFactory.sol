// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IPauseable} from '../../../base/IPauseable.sol';
import '../../../base/UntangledBase.sol';
import '../../../base/Factory.sol';
import '../../../interfaces/INoteTokenFactory.sol';
import '../../../libraries/ConfigHelper.sol';
import '../../../libraries/UntangledMath.sol';
import {MINTER_ROLE} from '../../../tokens/ERC20/types.sol';

contract NoteTokenFactory is UntangledBase, Factory, INoteTokenFactory {
    using ConfigHelper for Registry;

    bytes4 constant TOKEN_INIT_FUNC_SELECTOR = bytes4(keccak256('initialize(string,string,uint8,address,uint8)'));

    Registry public registry;

    INoteToken[] public override tokens;

    mapping(address => bool) public override isExistingTokens;

    address public override noteTokenImplementation;

    modifier onlySecuritizationManager() {
        require(
            _msgSender() == address(registry.getSecuritizationManager()),
            'SecuritizationPool: Only SecuritizationManager'
        );
        _;
    }

    function initialize(Registry _registry, address _factoryAdmin) public initializer {
        __UntangledBase__init(_msgSender());
        __Factory__init(_factoryAdmin);

        registry = _registry;
    }

    function setFactoryAdmin(address _factoryAdmin) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setFactoryAdmin(_factoryAdmin);
    }

    function changeMinterRole(address tokenAddress, address newController) external override onlySecuritizationManager {
        IAccessControlUpgradeable token = IAccessControlUpgradeable(tokenAddress);
        token.grantRole(MINTER_ROLE, newController);
    }

    function setNoteTokenImplementation(address newAddress) external onlyAdmin {
        require(newAddress != address(0), 'NoteTokenFactory: new address cannot be zero');
        noteTokenImplementation = newAddress;
        emit UpdateNoteTokenImplementation(newAddress);
    }

    function createToken(
        address _poolAddress,
        Configuration.NOTE_TOKEN_TYPE _noteTokenType,
        uint8 _nDecimals,
        string calldata ticker
    ) external override whenNotPaused nonReentrant onlySecuritizationManager returns (address) {
        string memory name;
        string memory symbol;
        if (_noteTokenType == Configuration.NOTE_TOKEN_TYPE.SENIOR) {
            name = 'Senior Obligation Token';
            symbol = string.concat(ticker, '_SOT');
        } else {
            name = 'Junior Obligation Token';
            symbol = string.concat(ticker, '_JOT');
        }

        bytes memory _initialData = abi.encodeWithSelector(
            TOKEN_INIT_FUNC_SELECTOR,
            name,
            symbol,
            _nDecimals,
            _poolAddress,
            uint8(_noteTokenType)
        );

        address ntAddress = _deployInstance(noteTokenImplementation, _initialData);

        INoteToken token = INoteToken(ntAddress);

        tokens.push(token);
        isExistingTokens[address(token)] = true;

        emit TokenCreated(address(token), _poolAddress, _noteTokenType, _nDecimals, ticker);

        return address(token);
    }

    function pauseUnpauseToken(address tokenAddress) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isExistingTokens[tokenAddress], 'NoteTokenFactory: token does not exist');
        IPauseable token = IPauseable(tokenAddress);
        if (token.paused()) {
            token.unpause();
        } else {
            token.pause();
        }
    }

    function pauseAllTokens() external whenNotPaused nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 tokensLength = tokens.length;
        for (uint256 i = 0; i < tokensLength; i = UntangledMath.uncheckedInc(i)) {
            if (!tokens[i].paused()) tokens[i].pause();
        }
    }

    function unPauseAllTokens() external whenNotPaused nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 tokensLength = tokens.length;
        for (uint256 i = 0; i < tokensLength; i = UntangledMath.uncheckedInc(i)) {
            if (tokens[i].paused()) tokens[i].unpause();
        }
    }

    uint256[46] private __gap0;
    uint256[50] private __gap;
}
