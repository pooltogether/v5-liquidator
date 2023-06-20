// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";

import "../src/libraries/FixedMathLib.sol";
import { LiquidationPairFactory } from "../src/LiquidationPairFactory.sol";
import { LiquidationPair } from "../src/LiquidationPair.sol";
import { ILiquidationSource } from "../src/interfaces/ILiquidationSource.sol";
import { BaseSetup } from "./utils/BaseSetup.sol";
import { MockFixedMathLib } from "./mocks/MockFixedMathLib.sol";

contract FixedMathLibTest is BaseSetup {
  MockFixedMathLib public lib;

  function setUp() public virtual override {
    super.setUp();
    lib = new MockFixedMathLib();
  }

  function testMulHappyPath() public {
    uint256 result = lib.mul(100, UFixed32x4.wrap(1.5e4));
    assertEq(result, 150);
    result = lib.mul(100, UFixed32x4.wrap(0.5e4));
    assertEq(result, 50);
    result = lib.mul(100, UFixed32x4.wrap(0));
    assertEq(result, 0);
  }

  function testCannotOverflowMul() public {
    vm.expectRevert(abi.encodeWithSelector(FixedMathLib_A_GT_MaxUint224.selector, type(uint256).max));
    lib.mul(type(uint256).max, UFixed32x4.wrap(type(uint32).max));
  }

  function testDivHappyPath() public {
    uint256 result = lib.div(100, UFixed32x4.wrap(2e4));
    assertEq(result, 50);
    result = lib.div(100, UFixed32x4.wrap(0.5e4));
    assertEq(result, 200);
  }

  function testCannotOverflowDiv() public {
    uint256 a = uint256(type(uint224).max) + 1;
    vm.expectRevert(abi.encodeWithSelector(FixedMathLib_A_GT_MaxUint224.selector, a));
    lib.div(a, UFixed32x4.wrap(type(uint32).max));
  }

  function testCannotDivByZero() public {
    vm.expectRevert(abi.encodeWithSelector(FixedMathLib_B_Zero.selector));
    lib.div(type(uint224).max, UFixed32x4.wrap(0));
  }
}
