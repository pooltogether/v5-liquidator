// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { Ownable } from "openzeppelin/access/Ownable.sol";

import { ERC20 } from "../../src/ERC20.sol";

contract MockERC20 is ERC20, Ownable {
  constructor(
    string memory name_,
    string memory symbol_,
    uint8 decimals_
  ) ERC20(name_, symbol_, decimals_) {}

  function mint(address to, uint256 value) public virtual {
    _mint(to, value);
  }
}
