// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { LiquidatorLib_InsufficientReserveLiquidity, LiquidatorLib_InsufficientReserveLiquidity_Out, LiquidatorLib_InsufficientBalanceLiquidity_In } from "../src/libraries/LiquidatorLib.sol";
import { UFixed32x4 } from "../src/libraries/FixedMathLib.sol";
import { BaseSetup } from "./utils/BaseSetup.sol";
import { MockLiquidatorLib } from "./mocks/MockLiquidatorLib.sol";
import { UFixed32x4, FixedMathLib } from "../src/libraries/FixedMathLib.sol";

contract BaseLiquidatorLibTest is BaseSetup {
  /* ============ Variables ============ */

  UFixed32x4 public MAX_IMPACT = UFixed32x4.wrap(type(uint32).max);

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
    amountIn = bound(amountIn, 1, type(uint112).max);
    reserve1 = uint128(bound(reserve1, 1000, type(uint112).max));
    reserve0 = uint128(bound(reserve0, 1000, type(uint112).max));

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
    reserve1 = uint128(bound(reserve1, 1000, type(uint128).max));
    reserve0 = uint128(bound(reserve0, 1000, type(uint128).max));

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
    _reserve0 = uint128(bound(_reserve0, 1000, type(uint112).max));
    _reserve1 = uint128(bound(_reserve1, 1000, type(uint112).max));
    _amountIn1 = bound(_amountIn1, 0, type(uint112).max);
    _liquidityFraction = UFixed32x4.wrap(
      uint32(bound(UFixed32x4.unwrap(_liquidityFraction), 1, 1e4))
    );
    _minK = bound(_minK, 100, type(uint128).max);

    vm.assume(uint256(_reserve0) * _reserve1 > _minK);

    return (_reserve0, _reserve1, _amountIn1, _liquidityFraction, _minK);
  }

  function virtualBuyback_Assumptions(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    UFixed32x4 _maxPriceImpact
  ) public view returns (uint128, uint128, uint256, UFixed32x4) {
    UFixed32x4 maxPriceImpact = UFixed32x4.wrap(
      uint32(bound(UFixed32x4.unwrap(_maxPriceImpact), 10, 9999))
    );
    (uint256 amountIn1, uint128 reserve1, uint128 reserve0) = getAmountOut_Assumptions(
      _amountIn1,
      _reserve1,
      _reserve0
    );
    uint256 amountOut0 = mockLiquidatorLib.getAmountOut(amountIn1, reserve1, reserve0);
    vm.assume(reserve0 - amountOut0 > 0);
    vm.assume(reserve1 + amountIn1 < type(uint128).max);
    return (reserve0, reserve1, amountIn1, maxPriceImpact);
  }

  function computeExactAmountIn_Assumptions(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    uint256 _amountOut1,
    UFixed32x4 _maxPriceImpact
  ) public view returns (uint128, uint128, uint256, uint256, UFixed32x4) {
    (
      uint128 reserve0,
      uint128 reserve1,
      uint256 amountIn1,
      UFixed32x4 maxPriceImpact
    ) = virtualBuyback_Assumptions(_reserve0, _reserve1, _amountIn1, _maxPriceImpact);

    uint256 maxAmountOut1 = mockLiquidatorLib.calculateMaxAmountOut(
      amountIn1,
      reserve1,
      reserve0,
      maxPriceImpact
    );
    uint256 amountOut1 = bound(_amountOut1, 0, maxAmountOut1);

    // Need to use vm.assume. Don't bound results of virtualBuyback.
    vm.assume(amountOut1 <= amountIn1);

    return (reserve0, reserve1, amountIn1, amountOut1, maxPriceImpact);
  }

  function computeExactAmountOut_Assumptions(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    uint256 _amountIn0,
    UFixed32x4 _maxPriceImpact
  ) public view returns (uint128, uint128, uint256, uint256, UFixed32x4) {
    (_reserve0, _reserve1, _amountIn1, _maxPriceImpact) = virtualBuyback_Assumptions(
      _reserve0,
      _reserve1,
      _amountIn1,
      _maxPriceImpact
    );
    (uint128 reserve0, uint128 reserve1, uint256 maxAmountOut1, ) = mockLiquidatorLib
      .virtualBuyback(_reserve0, _reserve1, _amountIn1, _maxPriceImpact);

    // Need to use vm.assume. Don't bound results of virtualBuyback.
    vm.assume(reserve0 > 0);
    vm.assume(reserve1 > 0);
    vm.assume(_amountIn0 < type(uint112).max);
    vm.assume(reserve0 < type(uint112).max);
    vm.assume(reserve1 < type(uint112).max);
    vm.assume(_amountIn0 * reserve0 < type(uint128).max);
    vm.assume(_amountIn0 + reserve1 < type(uint128).max);

    uint256 amountOut1 = mockLiquidatorLib.getAmountOut(_amountIn0, reserve0, reserve1);
    vm.assume(amountOut1 <= maxAmountOut1);

    return (_reserve0, _reserve1, _amountIn1, _amountIn0, _maxPriceImpact);
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
    vm.expectRevert(abi.encodeWithSelector(LiquidatorLib_InsufficientReserveLiquidity.selector, 100, 0));
    mockLiquidatorLib.getAmountOut(100, 0, 100);
    vm.expectRevert(abi.encodeWithSelector(LiquidatorLib_InsufficientReserveLiquidity.selector, 0, 100));
    mockLiquidatorLib.getAmountOut(100, 100, 0);
  }

  function testGetAmountOut_Fuzz(uint256 amountIn, uint128 reserve1, uint128 reserve0) public view {
    (amountIn, reserve1, reserve0) = getAmountOut_Assumptions(amountIn, reserve1, reserve0);
    mockLiquidatorLib.getAmountOut(amountIn, reserve1, reserve0);
  }

  function testFailGetAmountOut_Overflow() public view {
    mockLiquidatorLib.getAmountOut(type(uint256).max, type(uint128).max, type(uint128).max);
  }

  /* ============ getVirtualBuybackAmountOut ============ */

  function testGetVirtualBuybackAmountOut_HappyPath() public view {
    uint128 reserve1 = 500e18;
    uint128 reserve0 = 500e18;
    UFixed32x4 maxPriceImpact = UFixed32x4.wrap(75e3); // 20%
    // UFixed32x4 maxPriceImpact = UFixed32x4.wrap(10e4); // 1000%

    mockLiquidatorLib.getVirtualBuybackAmounts(500e18, reserve1, reserve0, maxPriceImpact);
  }

  function testGetVirtualBuybackAmountOut_Sample() public view {
    uint128 reserve1 = 100e18;
    uint128 reserve0 = 100e18;
    UFixed32x4 maxPriceImpact = UFixed32x4.wrap(4294967295); // 20%
    // UFixed32x4 maxPriceImpact = UFixed32x4.wrap(10e4); // 1000%

    (uint256 amountOut0, uint256 amountIn1) = mockLiquidatorLib.getVirtualBuybackAmounts(
      10e18,
      reserve1,
      reserve0,
      maxPriceImpact
    );
  }

  /* ============ calculateRestrictedAmounts ============ */

  function testCalculateRestrictedAmounts_EqualAmounts_RegularImpact() public {
    uint128 reserve1 = 1000000e18;
    uint128 reserve0 = 1000000e18;
    UFixed32x4 priceImpact1 = UFixed32x4.wrap(50e2); // 50%
    (uint256 amountIn1, uint256 amountOut0) = mockLiquidatorLib.calculateRestrictedAmounts(
      reserve1,
      reserve0,
      priceImpact1
    );

    assertEq(amountOut0, 292893218813452475599156);
    assertEq(amountIn1, 414213562373095048801689);
  }

  function testCalculateRestrictedAmounts_HigherPrice_RegularImpact() public {
    uint128 reserve1 = 5000000e18;
    uint128 reserve0 = 1000000e18;
    UFixed32x4 priceImpact1 = UFixed32x4.wrap(50e2);
    (uint256 amountIn1, uint256 amountOut0) = mockLiquidatorLib.calculateRestrictedAmounts(
      reserve1,
      reserve0,
      priceImpact1
    );

    assertEq(amountOut0, 292893218813452475599156);
    assertEq(amountIn1, 2071067811865475244008443);
  }

  function testCalculateRestrictedAmounts_LowerPrice_RegularImpact() public {
    uint128 reserve1 = 1000000e18;
    uint128 reserve0 = 5000000e18;
    UFixed32x4 priceImpact1 = UFixed32x4.wrap(50e2);
    (uint256 amountIn1, uint256 amountOut0) = mockLiquidatorLib.calculateRestrictedAmounts(
      reserve1,
      reserve0,
      priceImpact1
    );
    assertEq(amountOut0, 1464466094067262377995779);
    assertEq(amountIn1, 414213562373095048801689);
  }

  function testCalculateRestrictedAmounts_HighPrice_LowImpact() public {
    uint128 reserve1 = type(uint88).max;
    uint128 reserve0 = 1;
    UFixed32x4 priceImpact1 = UFixed32x4.wrap(10);
    (uint256 amountIn1, uint256 amountOut0) = mockLiquidatorLib.calculateRestrictedAmounts(
      reserve1,
      reserve0,
      priceImpact1
    );

    assertEq(amountOut0, 1);
    assertEq(amountIn1, 154703838615177178005579);
  }

  function testCalculateRestrictedAmounts_LowPrice_LowImpact() public {
    uint128 reserve1 = 1;
    uint128 reserve0 = type(uint112).max;
    UFixed32x4 priceImpact1 = UFixed32x4.wrap(10);
    (uint256 amountIn1, uint256 amountOut0) = mockLiquidatorLib.calculateRestrictedAmounts(
      reserve1,
      reserve0,
      priceImpact1
    );

    assertEq(amountOut0, 2596797791096250505615666918986);
    assertEq(amountIn1, 0);
  }

  function testCalculateRestrictedAmounts_HigherPrice_RegImpact_DeltaGt10() public {
    // If r1 - r0 > 1e10, the scaling used for accuracy
    uint128 reserve1 = 1e20;
    uint128 reserve0 = 1e8;
    UFixed32x4 priceImpact1 = UFixed32x4.wrap(10);
    (uint256 amountIn1, uint256 amountOut0) = mockLiquidatorLib.calculateRestrictedAmounts(
      reserve1,
      reserve0,
      priceImpact1
    );

    assertEq(amountOut0, 49963);
    assertEq(amountIn1, 49987506246096482);
  }

  // Can't decrease the price any further!
  function testCalculateRestrictedAmounts_HighPrice_HighImpact() public {
    uint128 reserve1 = type(uint32).max;
    uint128 reserve0 = 1;
    UFixed32x4 priceImpact1 = UFixed32x4.wrap(9999);
    (uint256 amountIn1, uint256 amountOut0) = mockLiquidatorLib.calculateRestrictedAmounts(
      reserve1,
      reserve0,
      priceImpact1
    );

    assertEq(amountOut0, 1);
    assertEq(amountIn1, 425201762205);
  }

  function testCalculateRestrictedAmounts_LowPrice_HighImpact() public {
    uint128 reserve1 = 10000;
    uint128 reserve0 = type(uint88).max;
    UFixed32x4 priceImpact1 = UFixed32x4.wrap(9999);
    (uint256 amountIn1, uint256 amountOut0) = mockLiquidatorLib.calculateRestrictedAmounts(
      reserve1,
      reserve0,
      priceImpact1
    );
    assertEq(amountOut0, 306390159723131618037533245);
    assertEq(amountIn1, 990000);
  }

  function testCalculateRestrictedAmounts_EqualPrice_HighImpact() public {
    uint128 reserve1 = 1000000e18;
    uint128 reserve0 = 1000000e18;
    UFixed32x4 priceImpact1 = UFixed32x4.wrap(9999);
    (uint256 amountIn1, uint256 amountOut0) = mockLiquidatorLib.calculateRestrictedAmounts(
      reserve1,
      reserve0,
      priceImpact1
    );

    assertEq(amountOut0, 990000000000000000000000);
    assertEq(amountIn1, 99000000000000000000000000);
  }

  function testCalculateRestrictedAmounts_EqualPrice_HighImpact_MaxInt() public {
    uint128 reserve1 = type(uint112).max;
    uint128 reserve0 = type(uint112).max;
    UFixed32x4 priceImpact1 = UFixed32x4.wrap(9999);
    (uint256 amountIn1, uint256 amountOut0) = mockLiquidatorLib.calculateRestrictedAmounts(
      reserve1,
      reserve0,
      priceImpact1
    );

    assertEq(amountOut0, 5140373889949479352245191365927895);
    assertEq(amountIn1, 514037388994947935224519136592798905);
  }

  function testCalculateRestrictedAmounts_EqualPrice_LowImpact() public {
    uint128 reserve1 = 1000000e18;
    uint128 reserve0 = 1000000e18;
    UFixed32x4 priceImpact1 = UFixed32x4.wrap(10);
    (uint256 amountIn1, uint256 amountOut0) = mockLiquidatorLib.calculateRestrictedAmounts(
      reserve1,
      reserve0,
      priceImpact1
    );

    assertEq(amountOut0, 500125062539089864274);
    assertEq(amountIn1, 500375312773683819545);
  }

  function testCalculateRestrictedAmounts_SeventyFive() public {
    uint128 reserve1 = 1000000e18;
    uint128 reserve0 = 1000000e18;
    UFixed32x4 priceImpact1 = UFixed32x4.wrap(75e2);
    (uint256 amountIn1, uint256 amountOut0) = mockLiquidatorLib.calculateRestrictedAmounts(
      reserve1,
      reserve0,
      priceImpact1
    );

    assertEq(amountOut0, 500000e18);
    assertEq(amountIn1, 1000000e18);
  }

  function testCalculateRestrictedAmounts_LowAmounts_LowImpact() public {
    uint128 reserve1 = 1000;
    uint128 reserve0 = 1000;
    UFixed32x4 priceImpact1 = UFixed32x4.wrap(10);
    (uint256 amountIn1, uint256 amountOut0) = mockLiquidatorLib.calculateRestrictedAmounts(
      reserve1,
      reserve0,
      priceImpact1
    );

    assertEq(amountOut0, 1);
    assertEq(amountIn1, 1);
  }

  function testCalculateRestrictedAmounts_LowAmounts_HighImpact() public {
    uint128 reserve1 = 1000;
    uint128 reserve0 = 1000;
    UFixed32x4 priceImpact1 = UFixed32x4.wrap(9999);
    (uint256 amountIn1, uint256 amountOut0) = mockLiquidatorLib.calculateRestrictedAmounts(
      reserve1,
      reserve0,
      priceImpact1
    );

    assertEq(amountOut0, 990);
    assertEq(amountIn1, 99000);
  }

  function testCalculateRestrictedAmounts_HighAmounts_LowImpact() public {
    uint128 reserve1 = type(uint88).max;
    uint128 reserve0 = type(uint88).max;
    UFixed32x4 priceImpact1 = UFixed32x4.wrap(10);
    (uint256 amountIn1, uint256 amountOut0) = mockLiquidatorLib.calculateRestrictedAmounts(
      reserve1,
      reserve0,
      priceImpact1
    );
    assertEq(amountOut0, 154781209891811043358783);
    assertEq(amountIn1, 154858658588122147513511);
  }

  function testCalculateRestrictedAmounts_HighAmounts_HighImpact() public {
    uint128 reserve1 = type(uint88).max;
    uint128 reserve0 = type(uint88).max;
    UFixed32x4 priceImpact1 = UFixed32x4.wrap(9999);
    (uint256 amountIn1, uint256 amountOut0) = mockLiquidatorLib.calculateRestrictedAmounts(
      reserve1,
      reserve0,
      priceImpact1
    );
    assertEq(amountOut0, 306390159723131618037533245);
    assertEq(amountIn1, 30639015972313161803753329945);
  }

  function testCalculateRestrictedAmounts_LowAmounts_HighImpact2() public {
    uint128 reserve1 = 1;
    uint128 reserve0 = 100;
    UFixed32x4 priceImpact1 = UFixed32x4.wrap(9999);
    (uint256 amountIn1, uint256 amountOut0) = mockLiquidatorLib.calculateRestrictedAmounts(
      reserve1,
      reserve0,
      priceImpact1
    );
    assertEq(amountOut0, 99);
    assertEq(amountIn1, 99);
  }

  /* ============ getAmountIn ============ */

  function testGetAmountIn_HappyPath() public {
    uint256 amountOut = mockLiquidatorLib.getAmountIn(5, 10, 10);
    assertEq(amountOut, 11);
  }

  function testCannotGetAmountIn_InsufficientLiquidity() public {
    vm.expectRevert(abi.encodeWithSelector(LiquidatorLib_InsufficientReserveLiquidity_Out.selector, 1000, 100));
    mockLiquidatorLib.getAmountIn(1000, 10, 100);
    vm.expectRevert(abi.encodeWithSelector(LiquidatorLib_InsufficientReserveLiquidity.selector, 100, 0));
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
    (uint256 reserveA, uint256 reserveB, , ) = mockLiquidatorLib.virtualBuyback(
      10,
      10,
      10,
      MAX_IMPACT
    );
    assertEq(reserveA, 5);
    assertEq(reserveB, 20);
  }

  function testVirtualBuyback_Sample() public {
    uint128 _reserveA = 1119826692191245346783598304909069;
    uint128 _reserveB = 18663;
    uint256 _amountInB = 22789;
    UFixed32x4 _maxPriceImpact = UFixed32x4.wrap(10);

    (uint256 reserveA, uint256 reserveB, , ) = mockLiquidatorLib.virtualBuyback(
      _reserveA,
      _reserveB,
      _amountInB,
      _maxPriceImpact
    );
    assertEq(reserveA, 504181355697317666385754491086509);
    assertEq(reserveB, 41452);
  }

  function testCannotVirtualBuyback_InsufficientLiquidity() public {
    vm.expectRevert(abi.encodeWithSelector(LiquidatorLib_InsufficientReserveLiquidity.selector, 10, 0));
    mockLiquidatorLib.virtualBuyback(10, 0, 10, MAX_IMPACT);
    vm.expectRevert(abi.encodeWithSelector(LiquidatorLib_InsufficientReserveLiquidity.selector, 0, 10));
    mockLiquidatorLib.virtualBuyback(0, 10, 10, MAX_IMPACT);
  }

  function testVirtualBuyback_Fuzz(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    UFixed32x4 _maxPriceImpact
  ) public view {
    (
      uint128 reserve0,
      uint128 reserve1,
      uint256 amountIn1,
      UFixed32x4 maxPriceImpact
    ) = virtualBuyback_Assumptions(_reserve0, _reserve1, _amountIn1, _maxPriceImpact);
    mockLiquidatorLib.virtualBuyback(reserve0, reserve1, amountIn1, maxPriceImpact);
  }

  /* ============ computeExactAmountIn ============ */

  function testComputeExactAmountIn_HappyPath() public {
    uint256 amountOut = mockLiquidatorLib.computeExactAmountIn(10, 10, 10, 10, MAX_IMPACT);
    uint256 expectedAmountOut = 6;
    assertEq(amountOut, expectedAmountOut);
  }

  function testCannotComputeExactAmountIn_InsufficientLiquidity() public {
    vm.expectRevert(abi.encodeWithSelector(LiquidatorLib_InsufficientBalanceLiquidity_In.selector, 100, 10));
    mockLiquidatorLib.computeExactAmountIn(10, 10, 10, 100, MAX_IMPACT);
  }

  function testComputeExactAmountIn_Fuzz(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    uint256 _amountOut1,
    UFixed32x4 _maxPriceImpact
  ) public view {
    (
      uint128 reserve0,
      uint128 reserve1,
      uint256 amountIn1,
      uint256 amountOut1,
      UFixed32x4 maxPriceImpact
    ) = computeExactAmountIn_Assumptions(
        _reserve0,
        _reserve1,
        _amountIn1,
        _amountOut1,
        _maxPriceImpact
      );

    mockLiquidatorLib.computeExactAmountIn(
      reserve0,
      reserve1,
      amountIn1,
      amountOut1,
      maxPriceImpact
    );
  }

  /* ============ computeExactAmountOut ============ */

  function testComputeExactAmountOut_HappyPath() public {
    uint256 amountOut = mockLiquidatorLib.computeExactAmountOut(10, 10, 10, 5, MAX_IMPACT);
    uint256 expectedAmountOut = 10;
    assertEq(amountOut, expectedAmountOut);
  }

  function testCannotComputeExactAmountOut_InsufficientLiquidity() public {
    vm.expectRevert(abi.encodeWithSelector(LiquidatorLib_InsufficientBalanceLiquidity_In.selector, 9, 0));
    mockLiquidatorLib.computeExactAmountOut(10, 10, 0, 100, MAX_IMPACT);
  }

  // Fuzzer rejected too many times. Assertions need to be rewritten. Or better, use a different testing method.
  // function testComputeExactAmountOut_Fuzz(
  //   uint128 _reserve0,
  //   uint128 _reserve1,
  //   uint256 _amountIn1,
  //   uint256 _amountIn0,
  //   UFixed32x4 _maxPriceImpact
  // ) public view {
  //   (
  //     uint128 reserve0,
  //     uint128 reserve1,
  //     uint256 amountIn1,
  //     uint256 amountIn0,
  //     UFixed32x4 maxPriceImpact
  //   ) = computeExactAmountOut_Assumptions(
  //       _reserve0,
  //       _reserve1,
  //       _amountIn1,
  //       _amountIn0,
  //       _maxPriceImpact
  //     );

  //   mockLiquidatorLib.computeExactAmountOut(
  //     reserve0,
  //     reserve1,
  //     amountIn1,
  //     amountIn0,
  //     maxPriceImpact
  //   );
  // }

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

  function testVirtualSwap_Capped() public {
    (uint256 reserveA, uint256 reserveB) = mockLiquidatorLib.virtualSwap(
      1e18,
      1e18,
      1e18,
      1e18,
      UFixed32x4.wrap(1e4),
      UFixed32x4.wrap(1e4),
      1e18
    );
    assertEq(reserveA, 1000000000000000000000000000000000001);
    assertEq(reserveB, 1);
  }

  function testVirtualSwap_AmountOutIsZero() public {
    (uint256 reserveA, uint256 reserveB) = mockLiquidatorLib.virtualSwap(
      1,
      1,
      10,
      10,
      UFixed32x4.wrap(1e4),
      UFixed32x4.wrap(0.01e4),
      100
    );
    assertEq(reserveA, 1000);
    assertEq(reserveB, 1000);
  }

  /* ============ applyLiquidityFraction ============ */

  function testApplyLiquidityFraction_HappyPath() public {
    uint128 _reserve0 = 100e18;
    uint128 _reserve1 = 100e18;
    uint256 _amountIn1 = 10e18;
    UFixed32x4 _liquidityFraction = UFixed32x4.wrap(0.01e4);
    uint256 _minK = 1e8;

    (uint256 reserveA, uint256 reserveB) = mockLiquidatorLib.applyLiquidityFraction(
      _reserve0,
      _reserve1,
      _amountIn1,
      _liquidityFraction,
      _minK
    );
    assertEq(reserveA, 1e21);
    assertEq(reserveB, 1e21);
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

  // Maximizes the reserve0 numerator and sets a minimum denominator such that the resulting reserve0 is larger than the max uint112. This results in a passthrough of the original reserve0.
  function testApplyLiquidityFraction_MaxReserve0_Overflow() public {
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
    assertEq(reserveA, type(uint112).max);
    assertEq(reserveB, 1);
  }

  // Maximizes the reserve0 numerator and sets a minimum denominator such that the resulting reserve0 doesn't overflow
  function testApplyLiquidityFraction_MaxNumeratorMaxDenominator() public {
    // 0 is token in, 1 is token out
    uint128 _reserve0 = type(uint112).max;
    uint128 _reserve1 = type(uint112).max;
    uint256 _amountIn1 = type(uint112).max;
    UFixed32x4 _liquidityFraction = UFixed32x4.wrap(1e4);
    uint256 _minK = 1;

    (uint256 reserveA, uint256 reserveB) = mockLiquidatorLib.applyLiquidityFraction(
      _reserve0,
      _reserve1,
      _amountIn1,
      _liquidityFraction,
      _minK
    );
    assertEq(reserveA, type(uint112).max);
    assertEq(reserveB, type(uint112).max);
  }

  // Minimizes the initial reserve0 and maximizes the yield, the parameters for computing the final reserve0
  function testApplyLiquidityFraction_MaxNumerator_MaxAmountIn1MinReserve0() public {
    // 0 is token in, 1 is token out
    uint128 _reserve0 = 1;
    uint128 _reserve1 = 1;
    uint256 _amountIn1 = type(uint112).max;
    UFixed32x4 _liquidityFraction = UFixed32x4.wrap(1e4);
    uint256 _minK = 1;

    (uint256 reserveA, uint256 reserveB) = mockLiquidatorLib.applyLiquidityFraction(
      _reserve0,
      _reserve1,
      _amountIn1,
      _liquidityFraction,
      _minK
    );
    assertEq(reserveA, uint256(type(uint112).max));
    assertEq(reserveB, uint256(type(uint112).max));
  }

  // Minimizes the parameters for computing the final reserve0
  // Resulting K will be too small and initial reserves will be passed through
  function testApplyLiquidityFraction_MinReserve0() public {
    // 0 is token in, 1 is token out
    uint128 _reserve0 = 1;
    uint128 _reserve1 = type(uint112).max;
    uint256 _amountIn1 = 0;
    UFixed32x4 _liquidityFraction = UFixed32x4.wrap(1e4);
    uint256 _minK = 1;

    (uint256 reserve0, uint256 reserve1) = mockLiquidatorLib.applyLiquidityFraction(
      _reserve0,
      _reserve1,
      _amountIn1,
      _liquidityFraction,
      _minK
    );
    assertEq(reserve0, _reserve0);
    assertEq(reserve1, _reserve1);
  }

  // Maximizes the parameters for computing the final reserve1
  function testApplyLiquidityFraction_MaxReserve1() public {
    // 0 is token in, 1 is token out
    uint128 _reserve0 = 1;
    uint128 _reserve1 = 1;
    uint256 _amountIn1 = type(uint112).max;
    UFixed32x4 _liquidityFraction = UFixed32x4.wrap(1e4);
    uint256 _minK = 1;

    (uint256 reserveA, uint256 reserveB) = mockLiquidatorLib.applyLiquidityFraction(
      _reserve0,
      _reserve1,
      _amountIn1,
      _liquidityFraction,
      _minK
    );
    assertEq(reserveA, uint256(type(uint112).max));
    assertEq(reserveB, uint256(type(uint112).max));
  }

  // Minimizes the parameters for computing the final reserve1
  function testApplyLiquidityFraction_MinReserve1() public {
    // 0 is token in, 1 is token out
    uint128 _reserve0 = 1;
    uint128 _reserve1 = 1;
    uint256 _amountIn1 = 1;
    UFixed32x4 _liquidityFraction = UFixed32x4.wrap(1e4);
    uint256 _minK = 1;

    (uint256 reserveA, uint256 reserveB) = mockLiquidatorLib.applyLiquidityFraction(
      _reserve0,
      _reserve1,
      _amountIn1,
      _liquidityFraction,
      _minK
    );
    assertEq(reserveA, 1);
    assertEq(reserveB, 1);
  }

  function testApplyLiquidityFraction_Fuzz(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    UFixed32x4 _liquidityFraction,
    uint256 _minK
  ) public {
    (
      uint128 reserve0,
      uint128 reserve1,
      uint256 amountIn1,
      UFixed32x4 liquidityFraction,
      uint256 minK
    ) = applyLiquidityFraction_Assumptions(
        _reserve0,
        _reserve1,
        _amountIn1,
        _liquidityFraction,
        _minK
      );

    (uint256 reserveA, uint256 reserveB) = mockLiquidatorLib.applyLiquidityFraction(
      reserve0,
      reserve1,
      amountIn1,
      liquidityFraction,
      minK
    );

    uint256 expectedReserveA = (uint256(reserve0) * amountIn1 * FixedMathLib.multiplier) /
      (uint256(reserve1) * UFixed32x4.unwrap(liquidityFraction));
    uint256 expectedReserveB = FixedMathLib.div(amountIn1, liquidityFraction);

    if (reserve1 != reserveB || reserve0 != reserveA) {
      // Liquidity fraction was applied successfully
      assertEq(expectedReserveA, reserveA);
      assertEq(expectedReserveB, reserveB);
    } else {
      // Min K check was triggered
      assertEq(reserveA, reserve0);
      assertEq(reserveB, reserve1);
    }
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
      500,
      MAX_IMPACT
    );
    assertEq(reserveA, 12000);
    assertEq(reserveB, 10000);
    assertEq(amountOut, 91);
  }

  function testCannotSwapExactAmountIn_InsufficientLiquidity() public {
    vm.expectRevert(abi.encodeWithSelector(LiquidatorLib_InsufficientBalanceLiquidity_In.selector, 13, 10));
    mockLiquidatorLib.swapExactAmountIn(
      10,
      10,
      10,
      10,
      UFixed32x4.wrap(0.1e4),
      UFixed32x4.wrap(0.01e4),
      100,
      MAX_IMPACT
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
      100,
      MAX_IMPACT
    );
    assertEq(reserveA, 12000);
    assertEq(reserveB, 10000);
    assertEq(amountIn, 5);
  }

  function testCannotSwapExactAmountOut_InsufficientLiquidity() public {
    vm.expectRevert(abi.encodeWithSelector(LiquidatorLib_InsufficientBalanceLiquidity_In.selector, 100, 10));
    mockLiquidatorLib.swapExactAmountOut(
      10,
      10,
      10,
      100,
      UFixed32x4.wrap(0.1e4),
      UFixed32x4.wrap(0.01e4),
      1000,
      MAX_IMPACT
    );
  }

  ////////////////////////////////////////

  function testInverted1() public {
    // Prev: Overflow on reserve1_1 in `calculateRestrictedAmounts`
    uint128 reserve1 = type(uint112).max;
    uint128 reserve0 = type(uint112).max;
    UFixed32x4 priceImpact1 = UFixed32x4.wrap(9999);
    (uint256 amountIn1, uint256 amountOut0) = mockLiquidatorLib.calculateRestrictedAmounts(
      reserve1,
      reserve0,
      priceImpact1
    );

    assertEq(amountOut0, 5140373889949479352245191365927895);
    assertEq(amountIn1, 514037388994947935224519136592798905);
  }

  function testInverted2() public {
    // Prev: Division by 0 on reserve0_1 in `calculateRestrictedAmounts`
    uint128 reserve1 = 18663;
    uint128 reserve0 = 1119826692191245346783598304909069;
    UFixed32x4 priceImpact1 = UFixed32x4.wrap(10);
    (uint256 amountIn1, uint256 amountOut0) = mockLiquidatorLib.calculateRestrictedAmounts(
      reserve1,
      reserve0,
      priceImpact1
    );

    assertEq(amountOut0, 560053394465088714421070991239);
    assertEq(amountIn1, 9);
  }

  /* ============ calculateVirtualSwapPriceImpact ============ */

  function testCalculateVirtualSwapPriceImpact_HappyPath() public {
    uint256 amountIn1 = 1000e18;
    uint128 reserve1 = 1000000e18;
    uint128 reserve0 = 1000000e18;
    UFixed32x4 priceImpact1 = mockLiquidatorLib.calculateVirtualSwapPriceImpact(
      amountIn1,
      reserve1,
      reserve0
    );
    assertEq(UFixed32x4.unwrap(priceImpact1), 0);
  }

  function testCalculateVirtualSwapPriceImpact_NoImpact() public {
    uint256 amountIn1 = 10;
    uint128 reserve1 = 1000000;
    uint128 reserve0 = 1000000;
    UFixed32x4 priceImpact1 = mockLiquidatorLib.calculateVirtualSwapPriceImpact(
      amountIn1,
      reserve1,
      reserve0
    );
    assertEq(UFixed32x4.unwrap(priceImpact1), 0);
  }

  function testCalculateVirtualSwapPriceImpact_RegularAmount_Half() public {
    uint256 amountIn1 = 5000e18;
    uint128 reserve1 = 10000e18;
    uint128 reserve0 = 10000e18;
    UFixed32x4 priceImpact1 = mockLiquidatorLib.calculateVirtualSwapPriceImpact(
      amountIn1,
      reserve1,
      reserve0
    );
    assertEq(UFixed32x4.unwrap(priceImpact1), 1);
  }

  function testCalculateVirtualSwapPriceImpact_LowAmounts_Half() public {
    uint256 amountIn1 = 5;
    uint128 reserve1 = 10;
    uint128 reserve0 = 10;
    UFixed32x4 priceImpact1 = mockLiquidatorLib.calculateVirtualSwapPriceImpact(
      amountIn1,
      reserve1,
      reserve0
    );
    assertEq(UFixed32x4.unwrap(priceImpact1), 1);
  }

  function testCalculateVirtualSwapPriceImpact_HighAmounts_Half() public {
    uint256 amountIn1 = type(uint112).max / 2;
    uint128 reserve1 = type(uint112).max;
    uint128 reserve0 = type(uint112).max;
    UFixed32x4 priceImpact1 = mockLiquidatorLib.calculateVirtualSwapPriceImpact(
      amountIn1,
      reserve1,
      reserve0
    );
    assertEq(UFixed32x4.unwrap(priceImpact1), 1);
  }

  function testCalculateVirtualSwapPriceImpact_RegularAmounts_One() public {
    uint256 amountIn1 = 1000000e18;
    uint128 reserve1 = 1000000e18;
    uint128 reserve0 = 1000000e18;
    UFixed32x4 priceImpact1 = mockLiquidatorLib.calculateVirtualSwapPriceImpact(
      amountIn1,
      reserve1,
      reserve0
    );
    assertEq(UFixed32x4.unwrap(priceImpact1), 3);
  }

  function testCalculateVirtualSwapPriceImpact_MinAmounts_One() public {
    uint256 amountIn1 = 10;
    uint128 reserve1 = 10;
    uint128 reserve0 = 10;
    UFixed32x4 priceImpact1 = mockLiquidatorLib.calculateVirtualSwapPriceImpact(
      amountIn1,
      reserve1,
      reserve0
    );
    assertEq(UFixed32x4.unwrap(priceImpact1), 3);
  }

  function testCalculateVirtualSwapPriceImpact_LowAmounts_One() public {
    uint256 amountIn1 = 10;
    uint128 reserve1 = 10;
    uint128 reserve0 = 10;
    UFixed32x4 priceImpact1 = mockLiquidatorLib.calculateVirtualSwapPriceImpact(
      amountIn1,
      reserve1,
      reserve0
    );
    assertEq(UFixed32x4.unwrap(priceImpact1), 3);
  }

  function testCalculateVirtualSwapPriceImpact_HighAmounts_One() public {
    uint256 amountIn1 = type(uint112).max;
    uint128 reserve1 = type(uint112).max;
    uint128 reserve0 = type(uint112).max;
    UFixed32x4 priceImpact1 = mockLiquidatorLib.calculateVirtualSwapPriceImpact(
      amountIn1,
      reserve1,
      reserve0
    );
    assertEq(UFixed32x4.unwrap(priceImpact1), 2);
  }

  function testCalculateVirtualSwapPriceImpact_HighPrice_One() public {
    uint256 amountIn1 = type(uint112).max;
    uint128 reserve1 = type(uint112).max;
    uint128 reserve0 = 2;
    UFixed32x4 priceImpact1 = mockLiquidatorLib.calculateVirtualSwapPriceImpact(
      amountIn1,
      reserve1,
      reserve0
    );
    assertEq(UFixed32x4.unwrap(priceImpact1), 3);
  }

  function testCalculateVirtualSwapPriceImpact_RegularAmounts_OneAndAHalf() public {
    uint256 amountIn1 = 1500000e18;
    uint128 reserve1 = 1000000e18;
    uint128 reserve0 = 1000000e18;
    UFixed32x4 priceImpact1 = mockLiquidatorLib.calculateVirtualSwapPriceImpact(
      amountIn1,
      reserve1,
      reserve0
    );
    assertEq(UFixed32x4.unwrap(priceImpact1), 5);
  }

  function testCalculateVirtualSwapPriceImpact_LowAmounts_OneAndAHalf() public {
    uint256 amountIn1 = 30;
    uint128 reserve1 = 20;
    uint128 reserve0 = 20;
    UFixed32x4 priceImpact1 = mockLiquidatorLib.calculateVirtualSwapPriceImpact(
      amountIn1,
      reserve1,
      reserve0
    );
    assertEq(UFixed32x4.unwrap(priceImpact1), 5);
  }

  function testCalculateVirtualSwapPriceImpact_HighAmounts_OneAndAHalf() public {
    uint256 amountIn1 = type(uint112).max;
    uint128 reserve1 = (type(uint112).max / 3) * 2;
    uint128 reserve0 = (type(uint112).max / 3) * 2;
    UFixed32x4 priceImpact1 = mockLiquidatorLib.calculateVirtualSwapPriceImpact(
      amountIn1,
      reserve1,
      reserve0
    );
    assertEq(UFixed32x4.unwrap(priceImpact1), 5);
  }

  function testCalculateVirtualSwapPriceImpact_RegularAmounts_Double() public {
    uint256 amountIn1 = 2000000e18;
    uint128 reserve1 = 1000000e18;
    uint128 reserve0 = 1000000e18;
    UFixed32x4 priceImpact1 = mockLiquidatorLib.calculateVirtualSwapPriceImpact(
      amountIn1,
      reserve1,
      reserve0
    );
    assertEq(UFixed32x4.unwrap(priceImpact1), 7);
  }

  function testCalculateVirtualSwapPriceImpact_LowAmounts_Double() public {
    uint256 amountIn1 = 20;
    uint128 reserve1 = 10;
    uint128 reserve0 = 10;
    UFixed32x4 priceImpact1 = mockLiquidatorLib.calculateVirtualSwapPriceImpact(
      amountIn1,
      reserve1,
      reserve0
    );
    assertEq(UFixed32x4.unwrap(priceImpact1), 6);
  }

  function testCalculateVirtualSwapPriceImpact_HighAmounts_Double() public {
    uint256 amountIn1 = type(uint112).max;
    uint128 reserve1 = type(uint112).max / 2;
    uint128 reserve0 = type(uint112).max / 2;
    UFixed32x4 priceImpact1 = mockLiquidatorLib.calculateVirtualSwapPriceImpact(
      amountIn1,
      reserve1,
      reserve0
    );
    assertEq(UFixed32x4.unwrap(priceImpact1), 7);
  }

  // Swapping nothing should have no impact
  function testCalculateVirtualSwapPriceImpact_SwappingNone() public {
    uint256 amountIn1 = 0;
    uint128 reserve1 = 100e18;
    uint128 reserve0 = 100e18;
    UFixed32x4 priceImpact1 = mockLiquidatorLib.calculateVirtualSwapPriceImpact(
      amountIn1,
      reserve1,
      reserve0
    );

    assertEq(UFixed32x4.unwrap(priceImpact1), 0);
  }

  function testCalculateVirtualSwapPriceImpact_MaxImpact() public {
    uint256 amountIn1 = type(uint112).max;
    uint128 reserve1 = 1;
    uint128 reserve0 = type(uint112).max;
    UFixed32x4 priceImpact1 = mockLiquidatorLib.calculateVirtualSwapPriceImpact(
      amountIn1,
      reserve1,
      reserve0
    );
    assertEq(UFixed32x4.unwrap(priceImpact1), 461186580);
  }

  function testCalculateVirtualSwapPriceImpact_MaxValues() public {
    uint256 amountIn1 = type(uint112).max;
    uint128 reserve1 = type(uint112).max;
    uint128 reserve0 = type(uint112).max;
    UFixed32x4 priceImpact1 = mockLiquidatorLib.calculateVirtualSwapPriceImpact(
      amountIn1,
      reserve1,
      reserve0
    );
    assertEq(UFixed32x4.unwrap(priceImpact1), 2);
  }

  function testCalculateVirtualSwapPriceImpact_r1PrimeGreaterThanK() public {
    uint256 amountIn1 = 1e33;
    uint128 reserve1 = 1e1;
    uint128 reserve0 = 1e2;
    UFixed32x4 priceImpact1 = mockLiquidatorLib.calculateVirtualSwapPriceImpact(
      amountIn1,
      reserve1,
      reserve0
    );
    assertEq(UFixed32x4.unwrap(priceImpact1), 99);
  }

  function testCalculateVirtualSwapPriceImpact_LowAmounts() public {
    uint256 amountIn1 = 10;
    uint128 reserve1 = 1;
    uint128 reserve0 = 100;
    UFixed32x4 priceImpact1 = mockLiquidatorLib.calculateVirtualSwapPriceImpact(
      amountIn1,
      reserve1,
      reserve0
    );
    assertEq(UFixed32x4.unwrap(priceImpact1), 109);
  }

  function testCalculateVirtualSwapPriceImpact_LowAmounts2() public {
    uint256 amountIn1 = 99;
    uint128 reserve1 = 1;
    uint128 reserve0 = 100;
    UFixed32x4 priceImpact1 = mockLiquidatorLib.calculateVirtualSwapPriceImpact(
      amountIn1,
      reserve1,
      reserve0
    );
    assertEq(UFixed32x4.unwrap(priceImpact1), 9999);
  }
}
