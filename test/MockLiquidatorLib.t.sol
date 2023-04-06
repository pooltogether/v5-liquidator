// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { UFixed32x4 } from "../src/libraries/FixedMathLib.sol";
import { BaseSetup } from "./utils/BaseSetup.sol";
import { MockLiquidatorLib } from "./mocks/MockLiquidatorLib.sol";
import { UFixed32x4, FixedMathLib } from "../src/libraries/FixedMathLib.sol";

contract BaseLiquidatorLibTest is BaseSetup {
  /* ============ Variables ============ */

  MockLiquidatorLib public mockLiquidatorLib;

  /* ============ Set up ============ */

  function setUp() public virtual override {
    super.setUp();
    mockLiquidatorLib = new MockLiquidatorLib();
  }

  // ============ Assumptions for restricting fuzz tests ============

  function getAmountOut_Assumptions(
    uint256 amountIn,
    uint128 reserve1,
    uint128 reserve0
  ) public view returns (uint256, uint128, uint128) {
    amountIn = bound(amountIn, 0, type(uint112).max);
    reserve1 = uint128(bound(reserve1, 1, type(uint112).max));
    reserve0 = uint128(bound(reserve0, 1, type(uint112).max));

    vm.assume(amountIn * reserve0 < type(uint128).max);
    vm.assume(amountIn + reserve1 < type(uint128).max);

    return (amountIn, reserve1, reserve0);
  }

  function getAmountIn_Assumptions(
    uint256 amountOut,
    uint128 reserve1,
    uint128 reserve0
  ) public view returns (uint256, uint128, uint128) {
    amountOut = bound(amountOut, 0, type(uint128).max);
    reserve1 = uint128(bound(reserve1, 1, type(uint128).max));
    reserve0 = uint128(bound(reserve0, 1, type(uint128).max));

    vm.assume(amountOut < reserve0);
    vm.assume(amountOut * reserve1 < type(uint128).max);
    vm.assume(reserve0 - amountOut > 0);

    return (amountOut, reserve1, reserve0);
  }

  function applyLiquidityFraction_Assumptions(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    UFixed32x4 _liquidityFraction,
    uint256 _minK
  ) public view returns (uint128, uint128, uint256, UFixed32x4, uint256) {
    _reserve0 = uint128(bound(_reserve0, 1, type(uint112).max));
    _reserve1 = uint128(bound(_reserve1, 1, type(uint112).max));
    _amountIn1 = bound(_amountIn1, 0, type(uint112).max);
    _liquidityFraction = UFixed32x4.wrap(
      uint32(bound(UFixed32x4.unwrap(_liquidityFraction), 1, 1e4))
    );
    _minK = bound(_minK, 100, type(uint128).max);

    vm.assume(uint256(_reserve0) * _reserve1 > _minK);

    return (_reserve0, _reserve1, _amountIn1, _liquidityFraction, _minK);
  }

  function virtualBuyback_Assumptions(
    uint128 reserve0,
    uint128 reserve1,
    uint256 amountIn1
  ) public view returns (uint128, uint128, uint256) {
    (amountIn1, reserve1, reserve0) = getAmountOut_Assumptions(amountIn1, reserve1, reserve0);
    uint256 amountOut0 = mockLiquidatorLib.getAmountOut(amountIn1, reserve1, reserve0);
    vm.assume(reserve0 - amountOut0 > 0);
    vm.assume(reserve1 + amountIn1 < type(uint128).max);
    return (reserve0, reserve1, amountIn1);
  }

  function computeExactAmountIn_Assumptions(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    uint256 _amountOut1
  ) public view returns (uint128, uint128, uint256, uint256) {
    (_reserve0, _reserve1, _amountIn1) = virtualBuyback_Assumptions(
      _reserve0,
      _reserve1,
      _amountIn1
    );
    vm.assume(_amountOut1 <= _amountIn1);

    return (_reserve0, _reserve1, _amountIn1, _amountOut1);
  }

  function computeExactAmountOut_Assumptions(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    uint256 _amountIn0
  ) public view returns (uint128, uint128, uint256, uint256) {
    (_reserve0, _reserve1, _amountIn1) = virtualBuyback_Assumptions(
      _reserve0,
      _reserve1,
      _amountIn1
    );
    (uint128 reserve0, uint128 reserve1) = mockLiquidatorLib.virtualBuyback(
      _reserve0,
      _reserve1,
      _amountIn1
    );

    // Need to use vm.assume. Don't bound results of virtualBuyback.
    vm.assume(reserve0 > 0);
    vm.assume(reserve1 > 0);
    vm.assume(_amountIn0 < type(uint112).max);
    vm.assume(reserve0 < type(uint112).max);
    vm.assume(reserve1 < type(uint112).max);
    vm.assume(_amountIn0 * reserve0 < type(uint128).max);
    vm.assume(_amountIn0 + reserve1 < type(uint128).max);

    uint256 amountOut1 = mockLiquidatorLib.getAmountOut(_amountIn0, reserve0, reserve1);
    vm.assume(amountOut1 <= _amountIn1);
    return (_reserve0, _reserve1, _amountIn1, _amountIn0);
  }
}

contract MockLiquidatorLibTest is BaseLiquidatorLibTest {
  /* ============ Constructor ============ */

  /* ============ getAmountOut ============ */

  function testGetAmountOut_HappyPath() public {
    uint256 amountOut = mockLiquidatorLib.getAmountOut(10, 10, 10);
    assertEq(amountOut, 5);
  }

  function testCannotGetAmountOut_InsufficientLiquidity() public {
    vm.expectRevert(bytes("LiquidatorLib/insufficient-reserve-liquidity-a"));
    mockLiquidatorLib.getAmountOut(100, 0, 100);
    vm.expectRevert(bytes("LiquidatorLib/insufficient-reserve-liquidity-a"));
    mockLiquidatorLib.getAmountOut(100, 100, 0);
  }

  function testGetAmountOut_Fuzz(uint256 amountIn, uint128 reserve1, uint128 reserve0) public view {
    (amountIn, reserve1, reserve0) = getAmountOut_Assumptions(amountIn, reserve1, reserve0);
    mockLiquidatorLib.getAmountOut(amountIn, reserve1, reserve0);
  }

  function testFailGetAmountOut_Overflow() public view {
    mockLiquidatorLib.getAmountOut(type(uint256).max, type(uint128).max, type(uint128).max);
  }

  /* ============ getAmountIn ============ */

  function testGetAmountIn_HappyPath() public {
    uint256 amountOut = mockLiquidatorLib.getAmountIn(5, 10, 10);
    assertEq(amountOut, 11);
  }

  function testCannotGetAmountIn_InsufficientLiquidity() public {
    vm.expectRevert(bytes("LiquidatorLib/insufficient-reserve-liquidity-c"));
    mockLiquidatorLib.getAmountIn(1000, 10, 100);
    vm.expectRevert(bytes("LiquidatorLib/insufficient-reserve-liquidity-d"));
    mockLiquidatorLib.getAmountIn(10, 0, 100);
  }

  function testGetAmountIn_Fuzz(uint256 amountOut, uint128 reserve1, uint128 reserve0) public view {
    (amountOut, reserve1, reserve0) = getAmountIn_Assumptions(amountOut, reserve1, reserve0);
    mockLiquidatorLib.getAmountIn(amountOut, reserve1, reserve0);
  }

  function testFailGetAmountIn_Overflow() public view {
    mockLiquidatorLib.getAmountIn(type(uint256).max - 1, type(uint128).max, type(uint128).max);
  }

  /* ============ virtualBuyback ============ */

  function testVirtualBuyback_HappyPath() public {
    (uint256 reserveA, uint256 reserveB) = mockLiquidatorLib.virtualBuyback(10, 10, 10);
    assertEq(reserveA, 5);
    assertEq(reserveB, 20);
  }

  function testCannotVirtualBuyback_InsufficientLiquidity() public {
    vm.expectRevert(bytes("LiquidatorLib/insufficient-reserve-liquidity-a"));
    mockLiquidatorLib.virtualBuyback(10, 0, 10);
    vm.expectRevert(bytes("LiquidatorLib/insufficient-reserve-liquidity-a"));
    mockLiquidatorLib.virtualBuyback(0, 10, 10);
  }

  function testVirtualBuyback_Fuzz(
    uint128 reserve0,
    uint128 reserve1,
    uint256 amountIn1
  ) public view {
    (reserve0, reserve1, amountIn1) = virtualBuyback_Assumptions(reserve0, reserve1, amountIn1);
    mockLiquidatorLib.virtualBuyback(reserve0, reserve1, amountIn1);
  }

  /* ============ computeExactAmountIn ============ */

  function testComputeExactAmountIn_HappyPath() public {
    uint256 amountOut = mockLiquidatorLib.computeExactAmountIn(10, 10, 10, 10);
    uint256 expectedAmountOut = 6;
    assertEq(amountOut, expectedAmountOut);
  }

  function testCannotComputeExactAmountIn_InsufficientLiquidity() public {
    vm.expectRevert(bytes("LiquidatorLib/insufficient-balance-liquidity-a"));
    mockLiquidatorLib.computeExactAmountIn(10, 10, 10, 100);
  }

  function testComputeExactAmountIn_Fuzz(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    uint256 _amountOut1
  ) public view {
    (_reserve0, _reserve1, _amountIn1, _amountOut1) = computeExactAmountIn_Assumptions(
      _reserve0,
      _reserve1,
      _amountIn1,
      _amountOut1
    );
    mockLiquidatorLib.computeExactAmountIn(_reserve0, _reserve1, _amountIn1, _amountOut1);
  }

  /* ============ computeExactAmountOut ============ */

  function testComputeExactAmountOut_HappyPath() public {
    uint256 amountOut = mockLiquidatorLib.computeExactAmountOut(10, 10, 10, 5);
    uint256 expectedAmountOut = 10;
    assertEq(amountOut, expectedAmountOut);
  }

  function testCannotComputeExactAmountOut_InsufficientLiquidity() public {
    vm.expectRevert(bytes("LiquidatorLib/insufficient-balance-liquidity-b"));
    mockLiquidatorLib.computeExactAmountOut(10, 10, 0, 100);
  }

  function testComputeExactAmountOut_Fuzz(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    uint256 _amountIn0
  ) public view {
    (_reserve0, _reserve1, _amountIn1, _amountIn0) = computeExactAmountOut_Assumptions(
      _reserve0,
      _reserve1,
      _amountIn1,
      _amountIn0
    );
    mockLiquidatorLib.computeExactAmountOut(_reserve0, _reserve1, _amountIn1, _amountIn0);
  }

  /* ============ virtualSwap ============ */

  function testVirtualSwap_HappyPath() public {
    (uint256 reserveA, uint256 reserveB) = mockLiquidatorLib.virtualSwap(
      10,
      10,
      10,
      10,
      UFixed32x4.wrap(0.1e4),
      UFixed32x4.wrap(0.01e4),
      100
    );
    assertEq(reserveA, 1333);
    assertEq(reserveB, 1000);
  }

  /* ============ applyLiquidityFraction ============ */

  function testApplyLiquidityFraction_HappyPath() public {
    (uint256 reserveA, uint256 reserveB) = mockLiquidatorLib.applyLiquidityFraction(
      10000,
      10000,
      10,
      UFixed32x4.wrap(0.01e4),
      100
    );
    assertEq(reserveA, 1000);
    assertEq(reserveB, 1000);
  }

  function testApplyLiquidityFraction_InsufficientMinK() public {
    (uint256 reserveA, uint256 reserveB) = mockLiquidatorLib.applyLiquidityFraction(
      100,
      100,
      100,
      UFixed32x4.wrap(0.01e4),
      1e8
    );
    assertEq(reserveA, 100);
    assertEq(reserveB, 100);
  }

  function testApplyLiquidityFraction_Fuzz(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    UFixed32x4 _liquidityFraction,
    uint256 _minK
  ) public {
    (
      _reserve0,
      _reserve1,
      _amountIn1,
      _liquidityFraction,
      _minK
    ) = applyLiquidityFraction_Assumptions(
      _reserve0,
      _reserve1,
      _amountIn1,
      _liquidityFraction,
      _minK
    );

    (uint256 reserveA, uint256 reserveB) = mockLiquidatorLib.applyLiquidityFraction(
      _reserve0,
      _reserve1,
      _amountIn1,
      _liquidityFraction,
      _minK
    );

    uint256 expectedAmountIn = FixedMathLib.mul(reserveB, _liquidityFraction);

    if (_reserve1 != reserveB || _reserve0 != reserveA) {
      // Liquidity fraction was applied successfully
      assertLe(expectedAmountIn, _amountIn1);
      assertGe(expectedAmountIn + 1, _amountIn1);
    } else {
      // Min K check was triggered
      assertEq(reserveA, _reserve0);
      assertEq(reserveB, _reserve1);
    }
  }

  function testApplyLiquidityFraction_MaxM() public {
    uint128 _reserve0 = type(uint112).max;
    uint128 _reserve1 = 1;
    uint256 _amountIn1 = type(uint112).max;
    UFixed32x4 _liquidityFraction = UFixed32x4.wrap(1);
    uint256 _minK = 1;

    (uint256 reserveA, uint256 reserveB) = mockLiquidatorLib.applyLiquidityFraction(
      _reserve0,
      _reserve1,
      _amountIn1,
      _liquidityFraction,
      _minK
    );
    assertEq(reserveA, 236436429750241910892764680847366301456);
    assertEq(reserveB, 51922968585348276285304963292200950000);
  }

  function testApplyLiquidityFraction_MinM(UFixed32x4 _liquidityFraction) public {
    vm.assume(UFixed32x4.unwrap(_liquidityFraction) > 0);
    vm.assume(UFixed32x4.unwrap(_liquidityFraction) <= 1e4);

    uint128 reserve0 = type(uint112).max;
    uint128 reserve1 = type(uint112).max;
    uint256 amountIn1 = 1;
    uint256 minK = 1;

    (uint256 reserveA, uint256 reserveB) = mockLiquidatorLib.applyLiquidityFraction(
      reserve0,
      reserve1,
      amountIn1,
      _liquidityFraction,
      minK
    );

    assertEq(reserveA, reserveB);
  }

  /* ============ swapExactAmountIn ============ */

  function testSwapExactAmountIn_HappyPath() public {
    (uint256 reserveA, uint256 reserveB, uint256 amountOut) = mockLiquidatorLib.swapExactAmountIn(
      10,
      10,
      100,
      5,
      UFixed32x4.wrap(0.1e4),
      UFixed32x4.wrap(0.01e4),
      500
    );
    assertEq(reserveA, 12000);
    assertEq(reserveB, 10000);
    assertEq(amountOut, 91);
  }

  function testCannotSwapExactAmountIn_InsufficientLiquidity() public {
    vm.expectRevert(bytes("LiquidatorLib/insufficient-balance-liquidity-c"));
    mockLiquidatorLib.swapExactAmountIn(
      10,
      10,
      10,
      10,
      UFixed32x4.wrap(0.1e4),
      UFixed32x4.wrap(0.01e4),
      100
    );
  }

  /* ============ swapExactAmountOut ============ */

  function testSwapExactAmountOut_HappyPath() public {
    (uint256 reserveA, uint256 reserveB, uint256 amountIn) = mockLiquidatorLib.swapExactAmountOut(
      10,
      10,
      100,
      91,
      UFixed32x4.wrap(0.1e4),
      UFixed32x4.wrap(0.01e4),
      100
    );
    assertEq(reserveA, 12000);
    assertEq(reserveB, 10000);
    assertEq(amountIn, 5);
  }

  function testCannotSwapExactAmountOut_InsufficientLiquidity() public {
    vm.expectRevert(bytes("LiquidatorLib/insufficient-balance-liquidity-d"));
    mockLiquidatorLib.swapExactAmountOut(
      10,
      10,
      10,
      100,
      UFixed32x4.wrap(0.1e4),
      UFixed32x4.wrap(0.01e4),
      1000
    );
  }
}
