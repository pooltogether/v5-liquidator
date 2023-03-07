// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import { BaseSetup } from "./utils/BaseSetup.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";

contract MockERC20Test is BaseSetup {
  // Contracts
  MockERC20 public testToken;

  function setUp() public virtual override {
    super.setUp();
    testToken = new MockERC20("testToken", "TEST", 18);
  }

  function testMint(uint256 amount) public {
    assertEq(testToken.balanceOf(address(this)), 0);
    testToken.mint(address(this), amount);
    assertEq(testToken.balanceOf(address(this)), amount);
  }
}
