const FDSToken = artifacts.require("FDSToken.sol");

module.exports = function(deployer) {
  deployer.deploy(FDSToken);
};
