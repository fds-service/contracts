const FDSResonance = artifacts.require("FDSResonance.sol");
const FDSToken = artifacts.require("FDSToken.sol");

module.exports = function(deployer) {
  deployer.deploy(FDSResonance, FDSToken.address, "0xc88DC709Dec2fb564f7365915f11A819310c6391", "0xc88DC709Dec2fb564f7365915f11A819310c6391", 1, 1);
};
