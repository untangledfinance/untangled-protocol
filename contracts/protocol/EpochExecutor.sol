// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;
import "../interfaces/INoteTokenVault.sol";
import "../interfaces/IPool.sol";
import "../libraries/Math.sol";

contract EpochExecutor {
    
    struct OrderSummary {
        uint256 sotRedeem;
        uint256 jotRedeem;
        uint256 sotSupply;
        uint256 jotSupply;
    }

    struct EpochInformation {
        uint256 lastEpochClosed;
        uint256 minimumEpochTime;
        uint256 lastEpochExecuted;
        uint256 currentEpoch;
        uint256 bestSubScore;
        uint256 sotPrice;
        uint256 jotPrice;
        uint256 epochNAV;
        uint256 epochSeniorAsset;
        uint256 epochReserve;
        uint256 weightSeniorRedeem;
        uint256 weightJuniorRedeem;
        uint256 weightSeniorSupply;
        uint256 weightJuniorSupply;
        uint256 minChallengePeriodEnd;
        uint256 challengeTime;
        uint256 bestRatioImprovement;
        uint256 bestReserveImprovement;
        bool poolClosing;
        bool submitPeriod;
        bool gotFullValidation;
        OrderSummary order;
        OrderSummary bestSubmission;
    }
    
    uint256 constant ONE = 10 ** 27;
    int256 public constant SUCCESS = 0;
    int256 public constant NEW_BEST = 0;
    int256 public constant ERR_CURRENCY_AVAILABLE = -1;
    int256 public constant ERR_MAX_ORDER = -2;
    int256 public constant ERR_MAX_RESERVE = -3;
    int256 public constant ERR_MIN_SENIOR_RATIO = -4;
    int256 public constant ERR_MAX_SENIOR_RATIO = -5;
    int256 public constant ERR_NOT_NEW_BEST = -6;
    int256 public constant ERR_POOL_CLOSING = -7;
    uint256 public constant BIG_NUMBER = ONE * ONE;

    modifier isNewEpoch(address pool){
        require(Math.safeSub(block.timestamp, epochInfor[pool].lastEpochClosed) >= epochInfor[pool].minimumEpochTime);
        _;
    }



    INoteTokenVault public vault; 
    mapping(address => EpochInformation) public epochInfor;

    constructor(address vault_) {
        vault = INoteTokenVault(vault_);
    }

    function setUpPool() public {
        epochInfor[msg.sender].lastEpochClosed = block.timestamp;
    }
    
    function setParam(address pool, bytes32 name, uint256 value) public {
       if (name == "challengeTime") {
            epochInfor[pool].challengeTime = value;
        } else if (name == "minimumEpochTime") {
            epochInfor[pool].minimumEpochTime = value;
        } else if (name == "weightSeniorRedeem") {
            epochInfor[pool].weightSeniorRedeem = value;
        } else if (name == "weightJuniorRedeem") {
           epochInfor[pool].weightJuniorRedeem = value;
        } else if (name == "weightJuniorSupply") {
            epochInfor[pool].weightJuniorSupply = value;
        } else if (name == "weightSeniorSupply") {
           epochInfor[pool].weightSeniorSupply = value;
        } else {
            revert("unknown-name");
        }
    }

    function setParam(address pool,bytes32 name, bool value ) public {
        if (name == "poolClosing") {
            epochInfor[pool].poolClosing = value;
        } else {
            revert("unknown-name");
        }
    }

    

    function closeEpoch(address pool) external isNewEpoch(pool) returns (bool epochExecuted) {
        require(epochInfor[pool].submitPeriod == false);
        IPool _pool = IPool(pool);
        epochInfor[pool].lastEpochClosed = block.timestamp;
        epochInfor[pool].currentEpoch += 1;

        (uint256 orderJuniorSupply, uint256 orderJuniorRedeem, uint256 orderSeniorSupply, uint256 orderSeniorRedeem) = vault.closeEpoch(pool);
        epochInfor[pool].epochSeniorAsset = Math.safeAdd(_pool.seniorDebtAndBalance());

        epochInfor[pool].epochNAV = _pool.currentNAV();
        epochInfor[pool].epochReserve = _pool.reserve();

        if(orderSeniorRedeem == 0 && orderJuniorRedeem == 0 && orderJuniorSupply == 0 && orderSeniorSupply == 0) {
            vault.epochUpdate(pool, epochInfor[pool].currentEpoch, 0, 0, 0, 0, 0);

            _pool.changeSeniorAsset(0, 0);
            _pool.changeBorrowAmountEpoch(epochInfor[pool].epochReserve);
        }

        (uint256 sotPrice,uint256 jotPrice) = _pool.calcTokenPrices();
        epochInfor[pool].sotPrice = sotPrice;
        epochInfor[pool].jotPrice = jotPrice;

        if(jotPrice == 0) {
            epochInfor[pool].poolClosing = true;
        }

        epochInfor[pool].order.sotRedeem = Math.rmul(orderSeniorRedeem, sotPrice);
        epochInfor[pool].order.jotRedeem = Math.rmul(orderJuniorRedeem, jotPrice);
        epochInfor[pool].order.sotSupply = orderSeniorSupply;
        epochInfor[pool].order.jotSupply = orderJuniorSupply;

        if(validate(epochInfor[pool].order) == SUCCESS){
            _executeEpoch(epochInfor[pool]);
            return true;
        }

        epochInfor[pool].submitPeriod = true;
        return false;
    }

    function validate(OrderSummary calldata _order) public view returns (int256 err){

    }

    function _executeEpoch(EpochInformation memory _epochInfor) internal {
        uint256 epochID = Math.safeAdd(_epochInfor.lastEpochExecuted, 1);
        _epochInfor.submitPeriod = false;
        vault.epochUpdate();
    }

}