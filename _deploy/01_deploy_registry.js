const { deployProxy } = require('../utils/deployHelper');

module.exports = async ({ getNamedAccounts, deployments }) => {
  await deployProxy({ getNamedAccounts, deployments }, 'Registry', []);
};

module.exports.tags = ['registry_v1', 'core'];
