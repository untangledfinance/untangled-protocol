pragma solidity 0.8.19;
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

import {Registry} from '../../storage/Registry.sol';
import '../../libraries/Configuration.sol';
import '../../interfaces/IPool.sol';
import '../../interfaces/INoteTokenManager.sol';
import '../../interfaces/INoteToken.sol';

import {ConfigHelper} from '../../libraries/ConfigHelper.sol';

contract NoteToken is Initializable, PausableUpgradeable, INoteToken {
    using ConfigHelper for Registry;

    uint256 totalCapital;
    uint256 systemIndex;
    uint256 private _totalSupply;
    uint256 private _decimals;
    address private _pool;
    address private _noteTokenManager;

    Registry public registry;
    Configuration.NOTE_TOKEN_TYPE internal _noteTokenType;

    uint256[] allowedUIDTypes;
    string public name;
    string public symbol;
    // user => capital balance
    mapping(address => uint256) public capitalBalance;
    // user => user index
    mapping(address => uint256) public userIndex;
    // user => unclaimed income balance
    mapping(address => uint256) public unclaimedIncomeBalance;

    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 decimals_,
        address poolAddress,
        address noteTokenManagerAddress,
        uint8 tokenType
    ) public initializer {
        require(poolAddress != address(0), "NoteToken: Pool address can't be address(0) ");
        name = name_;
        symbol = symbol_;
        _decimals = decimals_;
        _pool = poolAddress;
        _noteTokenManager = noteTokenManagerAddress;
        _noteTokenType = Configuration.NOTE_TOKEN_TYPE(tokenType);
    }

    modifier onlyPool() {
        _onlyPool();
        _;
    }

    modifier onlyNoteTokenManager() {
        _onlyNoteTokenManager();
        _;
    }

    function transfer(address to, uint256 currencyAmount) external returns (bool) {
        require(INoteTokenManager(_noteTokenManager).hasValidUID(to), 'invalid uid');
        _updateUserIndex(to);
        _updateUserIndex(msg.sender);
        _transfer(to, currencyAmount);
        return true;
    }

    function mint(address to, uint256 currencyAmount) external onlyNoteTokenManager {
        require(INoteTokenManager(_noteTokenManager).hasValidUID(to), 'invalid uid');
        _updateUserIndex(to);
        _mint(to, currencyAmount);
    }

    function redeem(address user, uint256 currencyAmount) external onlyNoteTokenManager {
        require(capitalBalance[user] >= currencyAmount, 'invalid redeem amount');
        _updateUserIndex(user);
        capitalBalance[user] -= currencyAmount;
        _reduceTotalSupply(currencyAmount);
    }

    function distributeIncome(uint256 currencyAmount) external onlyPool {
        systemIndex += (currencyAmount * 10 ** _decimals) / totalCapital;
        _reduceTotalSupply(currencyAmount);
    }

    function claimIncome(address user) external onlyNoteTokenManager {
        unclaimedIncomeBalance[user] = 0;
        userIndex[user] = systemIndex;
    }

    function _onlyPool() internal view {
        require(msg.sender == _pool, 'only pool');
    }

    function _onlyNoteTokenManager() internal view {
        require(msg.sender == _noteTokenManager, 'only note token manager');
    }

    function _transfer(address to, uint256 currencyAmount) internal {
        require(to != address(0), 'transfer to address(0)');
        uint256 withdrawOrder = INoteTokenManager(_noteTokenManager).getWithdrawAmount(_pool, msg.sender);
        require(capitalBalance[msg.sender] - withdrawOrder >= currencyAmount, 'insufficient balance');
        capitalBalance[msg.sender] -= currencyAmount;
        capitalBalance[to] += currencyAmount;
    }

    function _mint(address to, uint256 currencyAmount) internal {
        capitalBalance[to] += currencyAmount;
        _totalSupply += (currencyAmount * 10 ** _decimals) / getPrice();
        totalCapital += currencyAmount;
    }

    function _reduceTotalSupply(uint256 currencyAmount) internal {
        uint256 burnTokenAmount = (currencyAmount * 10 ** _decimals) / getPrice();
        require(burnTokenAmount < _totalSupply, 'invalid burn token amount');
        _totalSupply -= burnTokenAmount;
    }

    function _updateUserIndex(address user) internal {
        unclaimedIncomeBalance[user] = calcUserIncome(user);
        userIndex[user] = systemIndex;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return (capitalBalance[account] * 10 ** _decimals) / getPrice();
    }

    function decimals() public view returns (uint256) {
        return _decimals;
    }

    function pool() public view returns (address) {
        return _pool;
    }

    function calcUserIncome(address user) public view returns (uint256) {
        return
            unclaimedIncomeBalance[user] + ((systemIndex - userIndex[user]) * capitalBalance[user]) / 10 ** _decimals;
    }

    function getPrice() public view returns (uint256 price) {
        if (_noteTokenType == Configuration.NOTE_TOKEN_TYPE.JUNIOR) {
            (price, ) = IPool(_pool).calcTokenPrices();
        }
        if (_noteTokenType == Configuration.NOTE_TOKEN_TYPE.SENIOR) {
            (, price) = IPool(_pool).calcTokenPrices();
        }
    }
}
