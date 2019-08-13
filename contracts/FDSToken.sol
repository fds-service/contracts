pragma solidity ^0.5.0;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Detailed.sol";

contract FDSToken is ERC20, ERC20Detailed {
    uint256 public burned; // Burned FDS.

    string private constant NAME = "FairDollars";
    string private constant SYMBOL = "FDS";
    uint8 private constant DECIMALS = 18;
    uint256 private constant INITIAL_SUPPLY = 2 * 10**28; // 20 billion

    constructor () public ERC20Detailed(NAME, SYMBOL, DECIMALS) {
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    function burn(uint256 value) public returns(bool) {
        burned = burned.add(value);
        _burn(msg.sender, value);
        return true;
    }

    function burnFrom(address from, uint256 value) public returns(bool) {
        burned = burned.add(value);
        _burnFrom(from, value);
        return true;
    }
}

