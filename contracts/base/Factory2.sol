// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/utils/Create2.sol';
import {AddressUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol';

abstract contract Factory2 is Initializable {
    using AddressUpgradeable for address;

    address public factoryAdmin;

    function __Factory__init(address _factoryAdmin) internal onlyInitializing {
        __Factory__init_unchained(_factoryAdmin);
    }

    function __Factory__init_unchained(address _factoryAdmin) internal onlyInitializing {
        factoryAdmin = _factoryAdmin;
    }

    function _setFactoryAdmin(address _factoryAdmin) internal {
        factoryAdmin = _factoryAdmin;
    }

    // function getSelector(string memory _func) internal pure returns (bytes4) {
    //     return bytes4(keccak256(bytes(_func)));
    // }

    function _deployInstance(address _poolImplAddress, bytes memory _data, bytes32 salt) internal returns (address) {
        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(
            Create2.deploy(
                0,
                salt,
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode,
                    abi.encode(_poolImplAddress, address(this), '')
                )
            )
        );

        proxy.changeAdmin(factoryAdmin);
        address(proxy).functionCall(_data);

        return address(proxy);
    }

    uint256[50] private __gap;
}
