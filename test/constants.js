const { utils } = require("ethers");


const POOL_ADMIN_ROLE = utils.keccak256(Buffer.from("POOL_CREATOR"));
const BACKEND_ADMIN = utils.keccak256(Buffer.from("BACKEND_ADMIN"));
const OWNER_ROLE = utils.keccak256(Buffer.from("OWNER_ROLE"));
const ORIGINATOR_ROLE = utils.keccak256(Buffer.from("ORIGINATOR_ROLE"));

const VALIDATOR_ADMIN_ROLE = utils.keccak256(Buffer.from("VALIDATOR_ADMIN_ROLE"));

module.exports = {
  POOL_ADMIN_ROLE,
  BACKEND_ADMIN,
  OWNER_ROLE,
  ORIGINATOR_ROLE,

  VALIDATOR_ADMIN_ROLE,
};
