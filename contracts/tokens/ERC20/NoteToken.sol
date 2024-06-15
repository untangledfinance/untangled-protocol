// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import '@openzeppelin/contracts-upgradeable/token/ERC20/presets/ERC20PresetMinterPauserUpgradeable.sol';
import '../../interfaces/IPool.sol';
import '../../libraries/Configuration.sol';
import '../../interfaces/INoteToken.sol';
/// @title NoteToken
/// @author Untangled Team
/// @dev Template for SOT/JOT token
contract NoteToken is INoteToken, ERC20PresetMinterPauserUpgradeable {
    uint8 public constant PRECISION = 18;

    address internal _poolAddress;
    address internal _noteTokenManager;
    Configuration.NOTE_TOKEN_TYPE internal _noteTokenType;
    uint8 internal _decimals;

    uint256 public systemIndex;

    mapping(address => uint256) public userPrincipalAmounts;
    mapping(address => uint256) public userIndexes;
    mapping(address => uint256) public userCachedIncome;

    event SystemIndexUpdated(uint256 index);
    event UserIndexUpdated(address indexed user, uint256 index);
    event IncomesAccrued(address indexed user, uint256 amount);

    function initialize(
        string memory name,
        string memory symbol,
        uint8 decimalsOfToken,
        address poolAddressOfToken,
        address noteTokenManager,
        uint8 typeOfToken
    ) public initializer {
        __ERC20PresetMinterPauser_init(name, symbol);
        require(poolAddressOfToken != address(0), 'NoteToken: Invalid pool address');

        _decimals = decimalsOfToken;
        _poolAddress = poolAddressOfToken;
        _noteTokenType = Configuration.NOTE_TOKEN_TYPE(typeOfToken);
        _noteTokenManager = noteTokenManager;
    }
    modifier onlyNoteTokenManager() {
        _onlyNoteTokenManager();
        _;
    }

    function _onlyNoteTokenManager() internal view {
        require(msg.sender == _noteTokenManager, 'only note token manager');
    }

    function poolAddress() external view returns (address) {
        return _poolAddress;
    }

    function noteTokenType() external view returns (uint8) {
        return uint8(_noteTokenType);
    }

    function decimals() public view override(ERC20Upgradeable, IERC20MetadataUpgradeable) returns (uint8) {
        return _decimals;
    }

    function burn(uint256 amount) public override(ERC20BurnableUpgradeable, INoteToken) {
        return ERC20BurnableUpgradeable.burn(amount);
    }

    function mint(address receiver, uint256 amount) public override(INoteToken, ERC20PresetMinterPauserUpgradeable) {
        return ERC20PresetMinterPauserUpgradeable.mint(receiver, amount);
    }

    function pause() public virtual override(ERC20PresetMinterPauserUpgradeable, IPauseable) {
        super.pause();
    }

    function paused() public view virtual override(IPauseable, PausableUpgradeable) returns (bool) {
        return super.paused();
    }

    function unpause() public virtual override(ERC20PresetMinterPauserUpgradeable, IPauseable) {
        super.unpause();
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20PresetMinterPauserUpgradeable) {
        if (from == address(0)) {
            uint256 userPrincipal = userPrincipalAmounts[to];
            _updateCurrentUnclaimedIncome(to, userPrincipal);
            userPrincipalAmounts[to] += amount;
        } else {
            address tokenManager;
            if (_noteTokenType == Configuration.NOTE_TOKEN_TYPE.JUNIOR) {
                tokenManager = IPool(_poolAddress).registry().getAddress(
                    uint8(Configuration.CONTRACT_TYPE.JUNIOR_TOKEN_MANAGER)
                );
            } else if (_noteTokenType == Configuration.NOTE_TOKEN_TYPE.SENIOR) {
                tokenManager = IPool(_poolAddress).registry().getAddress(
                    uint8(Configuration.CONTRACT_TYPE.SENIOR_TOKEN_MANAGER)
                );
            }
            require(from == tokenManager || to == tokenManager || to == address(0), 'Invalid transfer');
        }
    }

    /**
     * @dev Return the total rewards pending to claim by an user
     * @param users The user addresses
     * @return The incomes
     */
    function getUserIncomes(address[] calldata users) external view returns (uint256[] memory) {
        uint256[] memory incomes = new uint[](users.length);
        for (uint256 i; i < users.length; i++) {
            incomes[i] =
                userCachedIncome[users[i]] +
                _getUncachedIncomes(userPrincipalAmounts[users[i]], systemIndex, userIndexes[users[i]]);
        }
        return incomes;
    }

    function getUserIncome(address user) external view returns (uint256) {
        return userCachedIncome[user] + _getUncachedIncomes(userPrincipalAmounts[user], systemIndex, userIndexes[user]);
    }

    /**
     * @dev Updates the user state related with his accrued rewards
     * @param user Address of the user
     * @param userBalance The current balance of the user
     * @return The unclaimed rewards that were added to the total accrued
     **/
    function _updateCurrentUnclaimedIncome(address user, uint256 userBalance) internal returns (uint256) {
        uint256 accruedIncomes = _updateUserIndexInternal(user, userBalance);
        uint256 unclaimedRewards = userCachedIncome[user] + accruedIncomes;

        if (accruedIncomes != 0) {
            userCachedIncome[user] = unclaimedRewards;
            emit IncomesAccrued(user, accruedIncomes);
        }

        return unclaimedRewards;
    }

    /**
     * @dev Updates the state of an user in a distribution
     * @param _user The user's address
     * @param _userPrinciple User principle
     * @return The accrued income for the user
     **/
    function _updateUserIndexInternal(address _user, uint256 _userPrinciple) internal returns (uint256) {
        uint256 userIndex = userIndexes[_user];
        uint256 accruedIncomes = 0;

        uint256 newIndex = systemIndex;

        if (_userPrinciple != 0) {
            accruedIncomes = _getUncachedIncomes(_userPrinciple, newIndex, userIndex);
        }

        userIndexes[_user] = newIndex;
        emit UserIndexUpdated(_user, newIndex);

        return accruedIncomes;
    }

    /**
     * @dev Internal function for the calculation of user's rewards on a distribution
     * @param _userPrinciple User balance
     * @param _systemIndex Current index of the system
     * @param _userIndex Index stored for the user
     * @return The income
     **/
    function _getUncachedIncomes(
        uint256 _userPrinciple,
        uint256 _systemIndex,
        uint256 _userIndex
    ) internal pure returns (uint256) {
        return (_userPrinciple * (_systemIndex - _userIndex)) / (10 ** uint256(PRECISION));
    }

    function increaseIncome(uint256 usdAmount) external {
        require(msg.sender == _poolAddress, 'Only Pool');
        uint256 supply = totalSupply();
        require(supply != 0, 'totalSupply != 0');

        systemIndex += (usdAmount * 10 ** PRECISION) / supply;
    }

    function decreaseUserPrinciple(address[] calldata users, uint256[] calldata amounts) external onlyNoteTokenManager {
        uint256 length = users.length;
        require(length == amounts.length, 'Invalid length');
        for (uint256 i; i < length; i++) {
            uint256 userPrincipal = userPrincipalAmounts[users[i]];
            _updateCurrentUnclaimedIncome(users[i], userPrincipal);
            userPrincipalAmounts[users[i]] -= amounts[i];
        }
    }
    function decreaseUserPrinciple(address user, uint256 amount) external onlyNoteTokenManager {
        uint256 userPrincipal = userPrincipalAmounts[user];
        _updateCurrentUnclaimedIncome(user, userPrincipal);
        userPrincipalAmounts[user] -= amount;
    }

    function decreaseUserIncome(address[] calldata users, uint256[] calldata amounts) external onlyNoteTokenManager {
        uint256 length = users.length;
        require(length == amounts.length, 'Invalid length');
        for (uint256 i; i < length; i++) {
            uint256 userPrincipal = userPrincipalAmounts[users[i]];
            _updateCurrentUnclaimedIncome(users[i], userPrincipal);
            userCachedIncome[users[i]] -= amounts[i];
        }
    }

    function decreaseUserIncome(address user, uint256 amounts) external onlyNoteTokenManager {
        uint256 userPrincipal = userPrincipalAmounts[user];
        _updateCurrentUnclaimedIncome(user, userPrincipal);
        userCachedIncome[user] -= amounts;
    }

    function _increaseUserPrinciple(address user, uint256 amount) internal {
        uint256 userPrincipal = userPrincipalAmounts[user];
        _updateCurrentUnclaimedIncome(user, userPrincipal);
        userPrincipalAmounts[user] += amount;
    }
}
