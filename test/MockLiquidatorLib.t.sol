// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { UFixed32x9 } from "../src/libraries/FixedMathLib.sol";
import { BaseSetup } from "./utils/BaseSetup.sol";
import { MockLiquidatorLib } from "./mocks/MockLiquidatorLib.sol";
import { UFixed32x9, FixedMathLib } from "../src/libraries/FixedMathLib.sol";

contract MockLiquidatorLibTest is BaseSetup {
  // Contracts
  MockLiquidatorLib public mockLiquidatorLib;

  function setUp() public virtual override {
    super.setUp();
    mockLiquidatorLib = new MockLiquidatorLib();
  }

  // Tests

  function testGetAmountOutHappyPath() public {
    uint256 amountOut = mockLiquidatorLib.getAmountOut(10, 10, 10);
    assertEq(amountOut, 5);
  }

  function testCannotGetAmountOut() public {
    vm.expectRevert(bytes("LiquidatorLib/insufficient-reserve-liquidity"));
    mockLiquidatorLib.getAmountOut(100, 0, 100);
    vm.expectRevert(bytes("LiquidatorLib/insufficient-reserve-liquidity"));
    mockLiquidatorLib.getAmountOut(100, 100, 0);
  }

  function testGetAmountOutFuzz(uint256 amountIn, uint128 reserve1, uint128 reserve0) public view {
    getAmountOutAssumptions(amountIn, reserve1, reserve0);
    mockLiquidatorLib.getAmountOut(amountIn, reserve1, reserve0);
  }

  function testFailGetAmountOutOverflow() public view {
    mockLiquidatorLib.getAmountOut(type(uint256).max, type(uint128).max, type(uint128).max);
  }

  function testGetAmountInHappyPath() public {
    uint256 amountOut = mockLiquidatorLib.getAmountIn(5, 10, 10);
    assertEq(amountOut, 10);
  }

  function testCannotGetAmountIn() public {
    vm.expectRevert(bytes("LiquidatorLib/insufficient-reserve-liquidity"));
    mockLiquidatorLib.getAmountIn(1000, 10, 100);
    vm.expectRevert(bytes("LiquidatorLib/insufficient-reserve-liquidity"));
    mockLiquidatorLib.getAmountIn(10, 0, 100);
  }

  function testGetAmountInFuzz(uint256 amountOut, uint128 reserve1, uint128 reserve0) public view {
    getAmountInAssumptions(amountOut, reserve1, reserve0);
    mockLiquidatorLib.getAmountIn(amountOut, reserve1, reserve0);
  }

  function testFailGetAmountInOverflow() public view {
    mockLiquidatorLib.getAmountIn(type(uint256).max - 1, type(uint128).max, type(uint128).max);
  }

  function testVirtualBuybackHappyPath() public {
    (uint256 reserveA, uint256 reserveB) = mockLiquidatorLib.virtualBuyback(10, 10, 10);
    assertEq(reserveA, 5);
    assertEq(reserveB, 20);
  }

  function testCannotVirtualBuybackRequire() public {
    vm.expectRevert(bytes("LiquidatorLib/insufficient-reserve-liquidity"));
    mockLiquidatorLib.virtualBuyback(10, 0, 10);
    vm.expectRevert(bytes("LiquidatorLib/insufficient-reserve-liquidity"));
    mockLiquidatorLib.virtualBuyback(0, 10, 10);
  }

  function testPerpareSwapFuzz(uint128 reserve0, uint128 reserve1, uint256 amountIn1) public view {
    virtualBuybackAssumptions(reserve0, reserve1, amountIn1);
    mockLiquidatorLib.virtualBuyback(reserve0, reserve1, amountIn1);
  }

  function testComputeExactAmountInHappyPath() public {
    uint256 amountOut = mockLiquidatorLib.computeExactAmountIn(10, 10, 10, 10);
    uint256 expectedAmountOut = 5;
    assertEq(amountOut, expectedAmountOut);
  }

  function testCannotComputeExactAmountInRequire() public {
    vm.expectRevert(bytes("LiquidatorLib/insufficient-balance-liquidity"));
    mockLiquidatorLib.computeExactAmountIn(10, 10, 10, 100);
  }

  function testComputeExactAmountInFuzz(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    uint256 _amountOut1
  ) public view {
    computeExactAmountInAssumptions(_reserve0, _reserve1, _amountIn1, _amountOut1);
    mockLiquidatorLib.computeExactAmountIn(_reserve0, _reserve1, _amountIn1, _amountOut1);
  }

  function testComputeExactAmountOutHappyPath() public {
    uint256 amountOut = mockLiquidatorLib.computeExactAmountOut(10, 10, 10, 5);
    uint256 expectedAmountOut = 10;
    assertEq(amountOut, expectedAmountOut);
  }

  function testCannotComputeExactAmountOut() public {
    vm.expectRevert(bytes("LiquidatorLib/insufficient-balance-liquidity"));
    mockLiquidatorLib.computeExactAmountOut(10, 10, 0, 100);
  }

  function testComputeExactAmountOutFuzz(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    uint256 _amountIn0
  ) public view {
    computeExactAmountOutAssumptions(_reserve0, _reserve1, _amountIn1, _amountIn0);
    mockLiquidatorLib.computeExactAmountOut(_reserve0, _reserve1, _amountIn1, _amountIn0);
  }

  function testVirtualSwapHappyPath() public {
    (uint256 reserveA, uint256 reserveB) = mockLiquidatorLib.virtualSwap(
      10,
      10,
      10,
      10,
      UFixed32x9.wrap(0.1e9),
      UFixed32x9.wrap(0.01e9)
    );
    assertEq(reserveA, 1222);
    assertEq(reserveB, 999);
  }

  function testVirtualSwapFuzz(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    uint256 _amountOut1,
    UFixed32x9 _swapMultiplier,
    UFixed32x9 _liquidityFraction
  ) public view {
    vm.assume(_amountOut1 <= _amountIn1);
    vm.assume(_amountIn1 < type(uint112).max);
    vm.assume(_amountOut1 < type(uint112).max);
    vm.assume(UFixed32x9.unwrap(_liquidityFraction) > 0);
    vm.assume(UFixed32x9.unwrap(_swapMultiplier) <= 1e9);

    uint256 extraVirtualReserveOut1 = FixedMathLib.mul(_amountOut1, _swapMultiplier);
    vm.assume(extraVirtualReserveOut1 < type(uint256).max - _reserve1);
    vm.assume(extraVirtualReserveOut1 > 0);
    getAmountInAssumptions(extraVirtualReserveOut1, _reserve0, _reserve1);
    uint256 extraVirtualReserveIn0 = mockLiquidatorLib.getAmountIn(
      extraVirtualReserveOut1,
      _reserve0,
      _reserve1
    );
    vm.assume(_reserve0 + extraVirtualReserveIn0 < type(uint128).max);

    uint256 reserve0 = _reserve0 + uint128(extraVirtualReserveIn0); // Note: unsafe cast
    uint256 reserve1 = _reserve1 - uint128(extraVirtualReserveOut1); // Note: unsafe cast

    vm.assume((_amountIn1 * 1e9) < type(uint256).max);
    uint256 reserveFraction = (_amountIn1 * 1e9) / reserve1;
    vm.assume((reserveFraction * 1e9) < type(uint256).max);
    uint256 multiplier = FixedMathLib.div(reserveFraction, _liquidityFraction);
    vm.assume(multiplier < type(uint128).max);
    vm.assume((reserve0 * multiplier) < type(uint256).max);
    vm.assume((reserve1 * multiplier) < type(uint256).max);

    mockLiquidatorLib.virtualSwap(
      _reserve0,
      _reserve1,
      _amountIn1,
      _amountOut1,
      _swapMultiplier,
      _liquidityFraction
    );
  }

  function testSwapExactAmountInHappyPath() public {
    (uint256 reserveA, uint256 reserveB, uint256 amountOut) = mockLiquidatorLib.swapExactAmountIn(
      10,
      10,
      100,
      5,
      UFixed32x9.wrap(0.1e9),
      UFixed32x9.wrap(0.01e9)
    );
    assertEq(reserveA, 11000);
    assertEq(reserveB, 10000);
    assertEq(amountOut, 91);
  }

  function testCannotSwapExactAmountInRequire() public {
    vm.expectRevert(bytes("LiquidatorLib/insufficient-balance-liquidity"));
    mockLiquidatorLib.swapExactAmountIn(
      10,
      10,
      10,
      10,
      UFixed32x9.wrap(0.1e9),
      UFixed32x9.wrap(0.01e9)
    );
  }

  function testSwapExactAmountOutHappyPath() public {
    (uint256 reserveA, uint256 reserveB, uint256 amountIn) = mockLiquidatorLib.swapExactAmountOut(
      10,
      10,
      100,
      91,
      UFixed32x9.wrap(0.1e9),
      UFixed32x9.wrap(0.01e9)
    );
    assertEq(reserveA, 9000);
    assertEq(reserveB, 10000);
    assertEq(amountIn, 4);
  }

  function testCannotSwapExactAmountOutRequire() public {
    vm.expectRevert(bytes("LiquidatorLib/insufficient-balance-liquidity"));
    mockLiquidatorLib.swapExactAmountOut(
      10,
      10,
      10,
      100,
      UFixed32x9.wrap(0.1e9),
      UFixed32x9.wrap(0.01e9)
    );
  }

  // ------------- Assumptions for restriction fuzz tests -------------

  function getAmountOutAssumptions(
    uint256 amountIn,
    uint128 reserve1,
    uint128 reserve0
  ) public pure {
    vm.assume(reserve0 > 0);
    vm.assume(reserve1 > 0);
    vm.assume(amountIn < type(uint112).max);
    vm.assume(reserve0 < type(uint112).max);
    vm.assume(reserve1 < type(uint112).max);
    vm.assume(amountIn * reserve0 < type(uint128).max);
    vm.assume(amountIn + reserve1 < type(uint128).max);
  }

  function getAmountInAssumptions(
    uint256 amountOut,
    uint128 reserve1,
    uint128 reserve0
  ) public pure {
    uint256 maxSafeValue = type(uint128).max;
    vm.assume(reserve0 > 0);
    vm.assume(reserve1 > 0);
    vm.assume(amountOut < maxSafeValue);
    vm.assume(reserve0 < maxSafeValue);
    vm.assume(reserve1 < maxSafeValue);
    vm.assume(amountOut < reserve0);
    vm.assume(amountOut * reserve1 < type(uint128).max);
    vm.assume(reserve0 - amountOut > 0);
  }

  function virtualBuybackAssumptions(
    uint128 reserve0,
    uint128 reserve1,
    uint256 amountIn1
  ) public view {
    getAmountOutAssumptions(amountIn1, reserve1, reserve0);
    uint256 amountOut0 = mockLiquidatorLib.getAmountOut(amountIn1, reserve1, reserve0);
    vm.assume(reserve0 - amountOut0 > 0);
    vm.assume(reserve1 + amountIn1 < type(uint128).max);
  }

  function computeExactAmountInAssumptions(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    uint256 _amountOut1
  ) public view {
    vm.assume(_amountOut1 <= _amountIn1);
    virtualBuybackAssumptions(_reserve0, _reserve1, _amountIn1);
    (uint128 reserve0, uint128 reserve1) = mockLiquidatorLib.virtualBuyback(
      _reserve0,
      _reserve1,
      _amountIn1
    );
    getAmountInAssumptions(_amountIn1, reserve0, reserve1);
    mockLiquidatorLib.getAmountIn(_amountOut1, reserve0, reserve1);
  }

  function computeExactAmountOutAssumptions(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    uint256 _amountIn0
  ) public view {
    virtualBuybackAssumptions(_reserve0, _reserve1, _amountIn1);
    (uint128 reserve0, uint128 reserve1) = mockLiquidatorLib.virtualBuyback(
      _reserve0,
      _reserve1,
      _amountIn1
    );
    getAmountOutAssumptions(_amountIn0, reserve0, reserve1);
    uint256 amountOut1 = mockLiquidatorLib.getAmountOut(_amountIn0, reserve0, reserve1);
    vm.assume(amountOut1 <= _amountIn1);
  }

  function scaleReserveAssumptions(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    uint32 _liquidityFraction
  ) public pure {
    vm.assume(_liquidityFraction <= 1e9);
    vm.assume(_liquidityFraction > 0);

    vm.assume(_reserve1 > 0);
    vm.assume(_reserve0 > 0);

    vm.assume(_amountIn1 <= type(uint112).max);
    vm.assume(_amountIn1 > 0);

    uint256 denominator = FixedMathLib.mul(_reserve1, UFixed32x9.wrap(_liquidityFraction));
    vm.assume(denominator > 0);
    uint256 multiplier = _amountIn1 / denominator;
    vm.assume(multiplier * _reserve0 < type(uint128).max);
    vm.assume(multiplier * _reserve1 < type(uint128).max);
  }

  function virtualSwapAssumptions(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    uint256 _amountOut1,
    uint32 _swapMultiplier,
    uint32 _liquidityFraction
  ) public view {}
}
