exports.setupSender = require('./01_setupSender.js');
exports.setupReceiver = require('./02_setupReceiver.js');
exports.transferMessage = require('./03_transferMessage.js');
exports.getInfoFromReceiver = require('./04_getInfoFromReceiver.js');
exports.validateContracts = require('./contracts-validation.js');

require('./deploy-securitization-pool-template.js');
require('./upgrade-securitization-pool.js');