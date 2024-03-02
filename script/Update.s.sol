// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
contract UpdateScript is Script {
    address poolProxy = 0xf60119a084667434f2B3a97342475e9Fc5195FcA;
    address impLogic = 0xdc8B43e6626AeA9Ce0d2266FcE51E7ADF50123c8;
    address newImpLogic = 0xb3687dCcb478E272DECAee7944Ee3F03e40CFfCf;
    
    address proxyAdmin = 0xCB8aDbfdFA11529F69b199fE9779ec19c54fFc8f;
    address owner = 0xC52a72eDdcA008580b4Efc89eA9f343AfF11FeA3;
    function setUp() public {
        // the code is designed only for view functions, and there is no need for a prank.
        vm.prank(owner);
        address imp = ProxyAdmin(proxyAdmin).getProxyImplementation(ITransparentUpgradeableProxy(poolProxy));
        console2.log("old logic: ",imp);
        
        // the code prank owner of proxyAdmin, then update new logic for contract proxy poolProxy
        vm.prank(owner);
        ProxyAdmin(proxyAdmin).upgrade(ITransparentUpgradeableProxy(poolProxy),newImpLogic);

        // the code is designed only for view functions, and there is no need for a prank.
        vm.prank(owner);
        imp = ProxyAdmin(proxyAdmin).getProxyImplementation(ITransparentUpgradeableProxy(poolProxy));
        console2.log("new logic: ",imp);
    }

    function run() public {
    }
}