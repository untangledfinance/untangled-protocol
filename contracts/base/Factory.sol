// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {TransparentUpgradeableProxy} from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import {ContextUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol';

abstract contract Factory is Initializable, ContextUpgradeable {
    address public factoryAdmin;

    modifier onlyFactoryAdmin() {
        require(msg.sender == factoryAdmin, 'Only factory admin');
        _;
    }

    function __Factory__init(address _factoryAdmin) internal onlyInitializing {
        __Context_init_unchained();
        __Factory_init_unchained(_factoryAdmin);
    }

    function __Factory_init_unchained(address _factoryAdmin) internal onlyInitializing {
        factoryAdmin = _factoryAdmin;
    }

    function _setFactoryAdmin(address _factoryAdmin) internal {
        factoryAdmin = _factoryAdmin;
    }

    function _deployInstance(address _poolImplAddress, bytes memory _data) internal returns (address) {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(_poolImplAddress, factoryAdmin, _data);

        return address(proxy);
    }

    uint256[50] private __gap;
}
