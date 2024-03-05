// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IAccessControlUpgradeable} from '@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol';
import {Registry} from '../storage/Registry.sol';
import {Configuration} from './Configuration.sol';
import {ISecuritizationManager} from '../interfaces/ISecuritizationManager.sol';
import {IPool} from '../interfaces/IPool.sol';
import {INoteTokenFactory} from '../interfaces/INoteTokenFactory.sol';
import {INoteToken} from '../interfaces/INoteToken.sol';
import {ITokenGenerationEventFactory} from '../interfaces/ITokenGenerationEventFactory.sol';
import {ILoanKernel} from '../interfaces/ILoanKernel.sol';
import {LoanAssetToken} from '../tokens/ERC721/LoanAssetToken.sol';
import {ISecuritizationPoolValueService} from '../interfaces/ISecuritizationPoolValueService.sol';
import {ISecuritizationPoolValueService} from '../interfaces/ISecuritizationPoolValueService.sol';
import {IGo} from '../interfaces/IGo.sol';
import {OWNER_ROLE} from './DataTypes.sol';
import {INoteTokenVault} from '../interfaces/INoteTokenVault.sol';

/**
 * @title ConfigHelper
 * @notice A convenience library for getting easy access to other contracts and constants within the
 *  protocol, through the use of the Registry contract
 * @author Untangled Team
 */
library ConfigHelper {
    function getAddress(Registry registry, Configuration.CONTRACT_TYPE contractType) internal view returns (address) {
        return registry.getAddress(uint8(contractType));
    }

    function getSecuritizationManager(Registry registry) internal view returns (ISecuritizationManager) {
        return ISecuritizationManager(getAddress(registry, Configuration.CONTRACT_TYPE.SECURITIZATION_MANAGER));
    }

    function getSecuritizationPool(Registry registry) internal view returns (IPool) {
        return IPool(getAddress(registry, Configuration.CONTRACT_TYPE.SECURITIZATION_POOL));
    }

    function getNoteTokenFactory(Registry registry) internal view returns (INoteTokenFactory) {
        return INoteTokenFactory(getAddress(registry, Configuration.CONTRACT_TYPE.NOTE_TOKEN_FACTORY));
    }

    function getTokenGenerationEventFactory(Registry registry) internal view returns (ITokenGenerationEventFactory) {
        return
            ITokenGenerationEventFactory(
                getAddress(registry, Configuration.CONTRACT_TYPE.TOKEN_GENERATION_EVENT_FACTORY)
            );
    }

    function getLoanAssetToken(Registry registry) internal view returns (LoanAssetToken) {
        return LoanAssetToken(getAddress(registry, Configuration.CONTRACT_TYPE.LOAN_ASSET_TOKEN));
    }

    function getLoanKernel(Registry registry) internal view returns (ILoanKernel) {
        return ILoanKernel(getAddress(registry, Configuration.CONTRACT_TYPE.LOAN_KERNEL));
    }

    function getSecuritizationPoolValueService(
        Registry registry
    ) internal view returns (ISecuritizationPoolValueService) {
        return
            ISecuritizationPoolValueService(
                getAddress(registry, Configuration.CONTRACT_TYPE.SECURITIZATION_POOL_VALUE_SERVICE)
            );
    }

    function getGo(Registry registry) internal view returns (IGo) {
        return IGo(getAddress(registry, Configuration.CONTRACT_TYPE.GO));
    }

    function getNoteTokenVault(Registry registry) internal view returns (INoteTokenVault) {
        return INoteTokenVault(getAddress(registry, Configuration.CONTRACT_TYPE.NOTE_TOKEN_VAULT));
    }

    function requireSecuritizationManager(Registry registry, address account) internal view {
        require(account == address(getSecuritizationManager(registry)), 'Registry: Only SecuritizationManager');
    }

    function requireLoanKernel(Registry registry, address account) internal view {
        require(account == address(getLoanKernel(registry)), 'Registry: Only LoanKernel');
    }
}
