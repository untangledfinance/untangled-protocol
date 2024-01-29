// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IAccessControlUpgradeable} from '@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol';
import {Registry} from '../storage/Registry.sol';
import {Configuration} from './Configuration.sol';

import {ISecuritizationManager} from '../interfaces/ISecuritizationManager.sol';
import {ISecuritizationPool} from '../interfaces/ISecuritizationPool.sol';
import {INoteTokenFactory} from '../interfaces/INoteTokenFactory.sol';
import {INoteToken} from '../interfaces/INoteToken.sol';
import {ITokenGenerationEventFactory} from '../interfaces/ITokenGenerationEventFactory.sol';
import {IUntangledERC721} from '../interfaces/IUntangledERC721.sol';
import {ILoanRepaymentRouter} from '../interfaces/ILoanRepaymentRouter.sol';
import {ILoanKernel} from '../interfaces/ILoanKernel.sol';
import {ILoanAssetToken} from '../interfaces/ILoanAssetToken.sol';
import {IDistributionAssessor} from '../interfaces/IDistributionAssessor.sol';
import {ISecuritizationPoolValueService} from '../interfaces/ISecuritizationPoolValueService.sol';

import {MintedIncreasingInterestTGE} from '../protocol/note-sale/MintedIncreasingInterestTGE.sol';
import {MintedNormalTGE} from '../protocol/note-sale/MintedNormalTGE.sol';
import {IGo} from '../interfaces/IGo.sol';

import {POOL_ADMIN, OWNER_ROLE} from './types.sol';
import {INoteTokenVault} from '../protocol/pool/INoteTokenVault.sol';

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

    function getSecuritizationPool(Registry registry) internal view returns (ISecuritizationPool) {
        return ISecuritizationPool(getAddress(registry, Configuration.CONTRACT_TYPE.SECURITIZATION_POOL));
    }

    function getNoteTokenFactory(Registry registry) internal view returns (INoteTokenFactory) {
        return INoteTokenFactory(getAddress(registry, Configuration.CONTRACT_TYPE.NOTE_TOKEN_FACTORY));
    }

    // function getNoteToken(Registry registry) internal view returns (INoteToken) {
    //     return INoteToken(getAddress(registry, Configuration.CONTRACT_TYPE.NOTE_TOKEN));
    // }

    function getTokenGenerationEventFactory(Registry registry) internal view returns (ITokenGenerationEventFactory) {
        return
            ITokenGenerationEventFactory(
                getAddress(registry, Configuration.CONTRACT_TYPE.TOKEN_GENERATION_EVENT_FACTORY)
            );
    }

    function getLoanAssetToken(Registry registry) internal view returns (ILoanAssetToken) {
        return ILoanAssetToken(getAddress(registry, Configuration.CONTRACT_TYPE.LOAN_ASSET_TOKEN));
    }

    function getLoanRepaymentRouter(Registry registry) internal view returns (ILoanRepaymentRouter) {
        return ILoanRepaymentRouter(getAddress(registry, Configuration.CONTRACT_TYPE.LOAN_REPAYMENT_ROUTER));
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

    function getDistributionAssessor(Registry registry) internal view returns (IDistributionAssessor) {
        return IDistributionAssessor(getAddress(registry, Configuration.CONTRACT_TYPE.DISTRIBUTION_ASSESSOR));
    }

    function getGo(Registry registry) internal view returns (IGo) {
        return IGo(getAddress(registry, Configuration.CONTRACT_TYPE.GO));
    }

    function getNoteTokenVault(Registry registry) internal view returns (INoteTokenVault) {
        return INoteTokenVault(getAddress(registry, Configuration.CONTRACT_TYPE.NOTE_TOKEN_VAULT));
    }

    function requirePoolAdmin(Registry registry, address account) internal view {
        require(
            IAccessControlUpgradeable(address(getSecuritizationManager(registry))).hasRole(POOL_ADMIN, account),
            'Registry: Not an pool admin'
        );
    }

    function requirePoolAdminOrOwner(Registry registry, address pool, address account) internal view {
        require(
            IAccessControlUpgradeable(address(getSecuritizationManager(registry))).hasRole(POOL_ADMIN, account) ||
                IAccessControlUpgradeable(pool).hasRole(OWNER_ROLE, account),
            'Registry: Not an pool admin or pool owner'
        );
    }

    function requireSecuritizationManager(Registry registry, address account) internal view {
        require(account == address(getSecuritizationManager(registry)), 'Registry: Only SecuritizationManager');
    }

    function requireLoanRepaymentRouter(Registry registry, address account) internal view {
        require(account == address(getLoanRepaymentRouter(registry)), 'Registry: Only LoanRepaymentRouter');
    }

    function requireLoanKernel(Registry registry, address account) internal view {
        require(account == address(getLoanKernel(registry)), 'Registry: Only LoanKernel');
    }
}
