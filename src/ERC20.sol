// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { ERC20 as OZERC20 } from "openzeppelin/token/ERC20/ERC20.sol";

contract ERC20 is OZERC20 {
  uint8 private _decimals;

  constructor(string memory name_, string memory symbol_, uint8 decimals_) OZERC20(name_, symbol_) {
    _decimals = decimals_;
  }

  function decimals() public view override returns (uint8) {
    return _decimals;
  }
}
