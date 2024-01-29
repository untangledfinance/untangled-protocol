const { getChainId } = require('hardhat');
const { networks } = require('../../networks');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { execute, get, read } = deployments;
  const { deployer } = await getNamedAccounts();

  const kycAdmin = network.config.kycAdmin;

  const sm = await get('SecuritizationManager');
  const ui = await get('UniqueIdentity');

  const OWNER_ROLE = await read('SecuritizationManager', 'OWNER_ROLE');
  await execute(
    'SecuritizationManager',
    {
      from: deployer,
      log: true,
    },
    'grantRole',
    OWNER_ROLE,
    kycAdmin
  );

  const SIGNER_ROLE = await read('UniqueIdentity', 'SIGNER_ROLE');
  await execute(
    'UniqueIdentity',
    {
      from: deployer,
      log: true,
    },
    'grantRole',
    SIGNER_ROLE,
    kycAdmin
  );
};

module.exports.dependencies = ['registry', 'securitization_manager', 'unique_identity'];
module.exports.tags = ['mainnet', 'grant_kyc_admin'];
