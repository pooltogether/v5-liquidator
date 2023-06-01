// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { LiquidationPairFactory } from "src/LiquidationPairFactory.sol";
import { LiquidationPair } from "src/LiquidationPair.sol";
import { LiquidationRouter } from "src/LiquidationRouter.sol";

import { ILiquidationSource } from "src/interfaces/ILiquidationSource.sol";

import { LiquidatorLib } from "src/libraries/LiquidatorLib.sol";
import { UFixed32x4 } from "src/libraries/FixedMathLib.sol";

import { BaseSetup } from "./utils/BaseSetup.sol";

struct NewLiquidationPairArgs {
  address source;
  address tokenIn;
  address tokenOut;
  UFixed32x4 swapMultiplier;
  UFixed32x4 liquidityFraction;
  uint128 virtualReserveIn;
  uint128 virtualReserveOut;
  uint256 minK;
  UFixed32x4 maxPriceImpact;
}

contract LiquidationPairTestSetup is BaseSetup {
  /* ============ Variables ============ */

  address public target;
  address public tokenIn;
  address public tokenOut;
  address public source;

  /* ============ Events ============ */

  event Swapped(
    address indexed account,
    uint256 amountIn,
    uint256 amountOut,
    uint128 virtualReserveIn,
    uint128 virtualReserveOut
  );

  /* ============ Set up ============ */

  function setUp() public virtual override {
    super.setUp();
    target = utils.generateAddress("target");
    tokenIn = utils.generateAddress("tokenIn");
    tokenOut = utils.generateAddress("tokenOut");
    source = utils.generateAddress("source");
  }

  /* ============ Helper functions ============ */

  /* ============ swapExactAmountIn ============ */

  function swapExactAmountIn(
    address _user,
    uint256 _amountIn,
    uint256 _amountOfYield,
    LiquidationPair _liquidationPair,
    uint128 _expectedVirtualReserveIn,
    uint128 _expectedVirtualReserveOut
  ) internal {
    mockLiquidatableBalanceOf(
      address(_liquidationPair.source()),
      _liquidationPair.tokenOut(),
      _amountOfYield
    );

    mockLiquidateGivenAmountIn(_liquidationPair, _user, _amountIn, true);
    uint256 amountOut = _liquidationPair.computeExactAmountOut(_amountIn);

    vm.prank(_user);

    vm.expectEmit(true, false, false, true);
    emit Swapped(
      _user,
      _amountIn,
      amountOut,
      _expectedVirtualReserveIn,
      _expectedVirtualReserveOut
    );

    uint256 swappedAmountOut = _liquidationPair.swapExactAmountIn(_user, _amountIn, amountOut);

    // Verify swap results
    assertEq(swappedAmountOut, amountOut);
    assertEq(_liquidationPair.virtualReserveIn(), _expectedVirtualReserveIn);
    assertEq(_liquidationPair.virtualReserveOut(), _expectedVirtualReserveOut);
  }

  function swapExactAmountInNewLiquidationPair(
    address _user,
    uint256 _amountIn,
    uint256 _amountOfYield,
    NewLiquidationPairArgs memory _lpArgs,
    uint128 _expectedVirtualReserveIn,
    uint128 _expectedVirtualReserveOut
  ) internal {
    LiquidationPair liquidationPair = new LiquidationPair(
      ILiquidationSource(_lpArgs.source),
      _lpArgs.tokenIn,
      _lpArgs.tokenOut,
      _lpArgs.swapMultiplier,
      _lpArgs.liquidityFraction,
      _lpArgs.virtualReserveIn,
      _lpArgs.virtualReserveOut,
      _lpArgs.minK,
      _lpArgs.maxPriceImpact
    );
    swapExactAmountIn(
      _user,
      _amountIn,
      _amountOfYield,
      liquidationPair,
      _expectedVirtualReserveIn,
      _expectedVirtualReserveOut
    );
  }

  function swapExactAmountInNewLiquidationPairFromAmountOut(
    address _user,
    uint256 _amountOut,
    uint256 _amountOfYield,
    NewLiquidationPairArgs memory _lpArgs,
    uint128 _expectedVirtualReserveIn,
    uint128 _expectedVirtualReserveOut
  ) internal {
    LiquidationPair liquidationPair = new LiquidationPair(
      ILiquidationSource(_lpArgs.source),
      _lpArgs.tokenIn,
      _lpArgs.tokenOut,
      _lpArgs.swapMultiplier,
      _lpArgs.liquidityFraction,
      _lpArgs.virtualReserveIn,
      _lpArgs.virtualReserveOut,
      _lpArgs.minK,
      _lpArgs.maxPriceImpact
    );

    mockLiquidatableBalanceOf(_lpArgs.source, _lpArgs.tokenOut, _amountOfYield);

    uint256 amountIn = liquidationPair.computeExactAmountIn(_amountOut);
    uint256 amountOutMin = liquidationPair.computeExactAmountOut(amountIn);

    vm.prank(_user);

    mockLiquidateGivenAmountIn(liquidationPair, _user, amountIn, true);

    vm.expectEmit(true, false, false, true);
    emit Swapped(
      _user,
      amountIn,
      amountOutMin,
      _expectedVirtualReserveIn,
      _expectedVirtualReserveOut
    );

    uint256 swappedAmountOut = liquidationPair.swapExactAmountIn(_user, amountIn, amountOutMin);

    assertGe(swappedAmountOut, amountOutMin);
    assertEq(liquidationPair.virtualReserveIn(), _expectedVirtualReserveIn);
    assertEq(liquidationPair.virtualReserveOut(), _expectedVirtualReserveOut);
  }

  /* ============ swapExactAmountOut ============ */

  function swapExactAmountOut(
    address _user,
    uint256 _amountOut,
    uint256 _amountOfYield,
    LiquidationPair _liquidationPair,
    uint128 _expectedVirtualReserveIn,
    uint128 _expectedVirtualReserveOut
  ) internal {
    mockLiquidatableBalanceOf(
      address(_liquidationPair.source()),
      _liquidationPair.tokenOut(),
      _amountOfYield
    );
    uint256 maxAmountIn = _liquidationPair.computeExactAmountIn(_amountOut);
    mockLiquidateGivenAmountOut(_liquidationPair, alice, _amountOut, true);

    vm.expectEmit(true, false, false, true);
    emit Swapped(
      _user,
      maxAmountIn,
      _amountOut,
      _expectedVirtualReserveIn,
      _expectedVirtualReserveOut
    );

    vm.prank(_user);

    uint256 swappedAmountIn = _liquidationPair.swapExactAmountOut(_user, _amountOut, maxAmountIn);

    // Verify swap results
    assertLe(swappedAmountIn, maxAmountIn);
    assertEq(_liquidationPair.virtualReserveIn(), _expectedVirtualReserveIn);
    assertEq(_liquidationPair.virtualReserveOut(), _expectedVirtualReserveOut);
  }

  function swapExactAmountOutNewLiquidationPair(
    address _user,
    uint256 _amountOut,
    uint256 _amountOfYield,
    NewLiquidationPairArgs memory _lpArgs,
    uint128 _expectedVirtualReserveIn,
    uint128 _expectedVirtualReserveOut
  ) internal {
    LiquidationPair liquidationPair = new LiquidationPair(
      ILiquidationSource(_lpArgs.source),
      _lpArgs.tokenIn,
      _lpArgs.tokenOut,
      _lpArgs.swapMultiplier,
      _lpArgs.liquidityFraction,
      _lpArgs.virtualReserveIn,
      _lpArgs.virtualReserveOut,
      _lpArgs.minK,
      _lpArgs.maxPriceImpact
    );
    swapExactAmountOut(
      _user,
      _amountOut,
      _amountOfYield,
      liquidationPair,
      _expectedVirtualReserveIn,
      _expectedVirtualReserveOut
    );
  }

  /* ============ Mocks ============ */

  function mockLiquidatableBalanceOf(address _source, address _tokenOut, uint256 _result) internal {
    vm.mockCall(
      _source,
      abi.encodeWithSelector(ILiquidationSource.liquidatableBalanceOf.selector, _tokenOut),
      abi.encode(_result)
    );
  }

  function mockLiquidateGivenAmountOut(
    LiquidationPair liquidationPair,
    address _user,
    uint256 _amountOut,
    bool _result
  ) internal {
    uint256 amountIn = liquidationPair.computeExactAmountIn(_amountOut);
    address tokenIn = liquidationPair.tokenIn();
    address tokenOut = liquidationPair.tokenOut();
    address source = address(liquidationPair.source());
    mockLiquidate(source, _user, tokenIn, amountIn, tokenOut, _amountOut, _result);
  }

  function mockLiquidateGivenAmountIn(
    LiquidationPair liquidationPair,
    address _user,
    uint256 _amountIn,
    bool _result
  ) internal {
    uint256 amountOut = liquidationPair.computeExactAmountOut(_amountIn);
    address tokenIn = liquidationPair.tokenIn();
    address tokenOut = liquidationPair.tokenOut();
    address source = address(liquidationPair.source());
    mockLiquidate(source, _user, tokenIn, _amountIn, tokenOut, amountOut, _result);
  }

  function mockLiquidate(
    address _source,
    address _user,
    address _tokenIn,
    uint256 _amountIn,
    address _tokenOut,
    uint256 _amountOut,
    bool _result
  ) internal {
    vm.mockCall(
      _source,
      abi.encodeWithSelector(
        ILiquidationSource.liquidate.selector,
        _user,
        _tokenIn,
        _amountIn,
        _tokenOut,
        _amountOut
      ),
      abi.encode(_result)
    );
  }
}

contract LiquidationPairUnitTest is LiquidationPairTestSetup {
  /* ============ Variables ============ */

  UFixed32x4 public defaultSwapMultiplier;
  UFixed32x4 public defaultLiquidityFraction;
  uint128 public defaultVirtualReserveIn;
  uint128 public defaultVirtualReserveOut;
  uint256 public defaultMinK;
  UFixed32x4 public defaultMaxPriceImpact;

  LiquidationPair public defaultLiquidationPair;

  /* ============ Set up ============ */

  function setUp() public virtual override {
    super.setUp();
    defaultSwapMultiplier = UFixed32x4.wrap(0.3e4);
    defaultLiquidityFraction = UFixed32x4.wrap(0.02e4);
    defaultVirtualReserveIn = 100;
    defaultVirtualReserveOut = 100;
    defaultMinK = 100;
    defaultMaxPriceImpact = UFixed32x4.wrap(9999);

    defaultLiquidationPair = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      defaultSwapMultiplier,
      defaultLiquidityFraction,
      defaultVirtualReserveIn,
      defaultVirtualReserveOut,
      defaultMinK,
      defaultMaxPriceImpact
    );
  }

  /* ============ Constructor ============ */

  function testConstructor_HappyPath() public {
    assertEq(address(defaultLiquidationPair.source()), source);
    assertEq(address(defaultLiquidationPair.tokenIn()), tokenIn);
    assertEq(address(defaultLiquidationPair.tokenOut()), tokenOut);
    assertEq(
      UFixed32x4.unwrap(defaultLiquidationPair.swapMultiplier()),
      UFixed32x4.unwrap(defaultSwapMultiplier)
    );
    assertEq(
      UFixed32x4.unwrap(defaultLiquidationPair.liquidityFraction()),
      UFixed32x4.unwrap(defaultLiquidityFraction)
    );
    assertEq(defaultLiquidationPair.virtualReserveIn(), defaultVirtualReserveIn);
    assertEq(defaultLiquidationPair.virtualReserveOut(), defaultVirtualReserveOut);
  }

  function testConstructor_LiquidityFractionMinimum() public {
    vm.expectRevert(bytes("LiquidationPair/liquidity-fraction-greater-than-zero"));
    new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      defaultSwapMultiplier,
      UFixed32x4.wrap(0),
      defaultVirtualReserveIn,
      defaultVirtualReserveOut,
      defaultMinK,
      defaultMaxPriceImpact
    );
  }

  function testConstructor_LiquidityFractionTooLarge() public {
    vm.expectRevert(bytes("LiquidationPair/liquidity-fraction-less-than-one"));
    new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      defaultSwapMultiplier,
      UFixed32x4.wrap(1e4 + 1),
      defaultVirtualReserveIn,
      defaultVirtualReserveOut,
      defaultMinK,
      defaultMaxPriceImpact
    );
  }

  function testConstructor_SwapMultiplierTooLarge() public {
    vm.expectRevert(bytes("LiquidationPair/swap-multiplier-less-than-one"));
    new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      UFixed32x4.wrap(1e4 + 1),
      defaultLiquidityFraction,
      defaultVirtualReserveIn,
      defaultVirtualReserveOut,
      defaultMinK,
      defaultMaxPriceImpact
    );
  }

  function testConstructor_ReservesSmallerThanK() public {
    vm.expectRevert(bytes("LiquidationPair/virtual-reserves-greater-than-min-k"));
    new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      defaultSwapMultiplier,
      defaultLiquidityFraction,
      1,
      1,
      100,
      defaultMaxPriceImpact
    );
  }

  function testConstructor_VirtualReserveOutTooLarge() public {
    vm.expectRevert(bytes("LiquidationPair/virtual-reserve-out-too-large"));
    new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      defaultSwapMultiplier,
      defaultLiquidityFraction,
      defaultVirtualReserveIn,
      uint128(type(uint112).max) + 1,
      defaultMinK,
      defaultMaxPriceImpact
    );
  }

  function testConstructor_VirtualReserveInTooLarge() public {
    vm.expectRevert(bytes("LiquidationPair/virtual-reserve-in-too-large"));
    new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      defaultSwapMultiplier,
      defaultLiquidityFraction,
      uint128(type(uint112).max) + 1,
      defaultVirtualReserveOut,
      defaultMinK,
      defaultMaxPriceImpact
    );
  }

  /* ============ External functions ============ */

  /* ============ maxAmountIn ============ */

  function testMaxAmountIn_HappyPath() public {
    mockLiquidatableBalanceOf(source, tokenOut, 1e18);
    // With a low amount of virtual reserves, we can only liquidate a small amount
    uint256 amountIn = defaultLiquidationPair.maxAmountIn();
    assertEq(amountIn, 100);

    // However, with higher amounts, we can claim more
    LiquidationPair lp = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      defaultSwapMultiplier,
      defaultLiquidityFraction,
      100e18,
      100e18,
      defaultMinK,
      defaultMaxPriceImpact
    );
    amountIn = lp.maxAmountIn();
    assertEq(amountIn, 990099009900990100);
  }

  /* ============ maxAmountOut ============ */

  function testMaxAmountOut_HappyPath() public {
    mockLiquidatableBalanceOf(source, tokenOut, 1);
    uint256 amountOut = defaultLiquidationPair.maxAmountOut();
    assertEq(amountOut, 1);
  }

  function testMaxAmountOut_YieldExceedsPriceImpact() public {
    mockLiquidatableBalanceOf(source, tokenOut, 100);
    uint256 amountOut = defaultLiquidationPair.maxAmountOut();
    assertEq(amountOut, 100);

    mockLiquidatableBalanceOf(source, tokenOut, 10000);
    amountOut = defaultLiquidationPair.maxAmountOut();
    assertEq(amountOut, 9900);
  }

  /* ============ nextLiquidationState ============ */

  function testNextLiquidationState_HappyPath() public {
    mockLiquidatableBalanceOf(source, tokenOut, 0);

    (uint256 virtualReserveIn, uint256 virtualReserveOut, , ) = defaultLiquidationPair
      .nextLiquidationState();

    assertEq(virtualReserveIn, defaultVirtualReserveIn);
    assertEq(virtualReserveOut, defaultVirtualReserveOut);
  }

  /* ============ computeExactAmountIn ============ */

  function testComputeExactAmountIn_HappyPath() public {
    mockLiquidatableBalanceOf(source, tokenOut, 2);
    uint256 amountIn = defaultLiquidationPair.computeExactAmountIn(1);
    assertEq(amountIn, 1);
    vm.clearMockedCalls();

    mockLiquidatableBalanceOf(source, tokenOut, 5);
    amountIn = defaultLiquidationPair.computeExactAmountIn(2);
    assertEq(amountIn, 2);
    vm.clearMockedCalls();

    mockLiquidatableBalanceOf(source, tokenOut, 10);
    amountIn = defaultLiquidationPair.computeExactAmountIn(4);
    assertEq(amountIn, 4);
    vm.clearMockedCalls();
  }

  function testComputeExactAmountIn_HappyPathScaled() public {
    LiquidationPair liquidationPair = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      defaultSwapMultiplier,
      defaultLiquidityFraction,
      10000 * 1e18,
      10000 * 1e18,
      defaultMinK,
      defaultMaxPriceImpact
    );

    mockLiquidatableBalanceOf(source, tokenOut, 10);
    uint256 amountIn = liquidationPair.computeExactAmountIn(5);
    assertEq(amountIn, 5);
    vm.clearMockedCalls();

    mockLiquidatableBalanceOf(source, tokenOut, 10e8);
    amountIn = liquidationPair.computeExactAmountIn(5e8);
    assertEq(amountIn, 5e8);
    vm.clearMockedCalls();

    mockLiquidatableBalanceOf(source, tokenOut, 10e18);
    amountIn = liquidationPair.computeExactAmountIn(5e18);
    assertEq(amountIn, 4992508740634677667);
    vm.clearMockedCalls();
  }

  /* ============ computeExactAmountOut ============ */

  function testComputeExactAmountOut_HappyPath() public {
    mockLiquidatableBalanceOf(source, tokenOut, 10);
    uint256 amountOut = defaultLiquidationPair.computeExactAmountOut(1);
    assertEq(amountOut, 1);
    vm.clearMockedCalls();

    mockLiquidatableBalanceOf(source, tokenOut, 10e8);
    amountOut = defaultLiquidationPair.computeExactAmountOut(1);
    assertEq(amountOut, 5000);
    vm.clearMockedCalls();

    mockLiquidatableBalanceOf(source, tokenOut, 10e18);
    amountOut = defaultLiquidationPair.computeExactAmountOut(1);
    assertEq(amountOut, 5000);
    vm.clearMockedCalls();
  }

  function testComputeExactAmountOut_HappyPathScaled() public {
    LiquidationPair liquidationPair = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      defaultSwapMultiplier,
      defaultLiquidityFraction,
      10000 * 1e18,
      10000 * 1e18,
      defaultMinK,
      defaultMaxPriceImpact
    );

    mockLiquidatableBalanceOf(source, tokenOut, 10);
    uint256 amountOut = liquidationPair.computeExactAmountOut(5);
    assertEq(amountOut, 5);
    vm.clearMockedCalls();

    mockLiquidatableBalanceOf(source, tokenOut, 10e8);
    amountOut = liquidationPair.computeExactAmountOut(5e8);
    assertEq(amountOut, 5e8);
    vm.clearMockedCalls();

    mockLiquidatableBalanceOf(source, tokenOut, 10e18);
    amountOut = liquidationPair.computeExactAmountOut(5e18);
    assertEq(amountOut, 5007498746877187967);
    vm.clearMockedCalls();
  }

  /* ============ swapExactAmountIn ============ */

  function testSwapExactAmountIn_HappyPath() public {
    uint256 amountIn = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x4 swapMultiplier = defaultSwapMultiplier;
    UFixed32x4 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;
    uint128 expectedVirtualReserveIn = 425165511912977780518;
    uint128 expectedVirtualReserveOut = 500000000000000000000;

    swapExactAmountInNewLiquidationPair(
      alice,
      amountIn,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        defaultMinK,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountIn_MaximumAmountIn() public {
    uint256 amountIn = type(uint104).max;
    uint256 amountOfYield = type(uint112).max;
    UFixed32x4 swapMultiplier = UFixed32x4.wrap(0);
    UFixed32x4 liquidityFraction = UFixed32x4.wrap(1e4);
    uint128 virtualReserveIn = type(uint112).max;
    uint128 virtualReserveOut = type(uint112).max;
    uint128 expectedVirtualReserveIn = 1318435852399872841894164877541375;
    uint128 expectedVirtualReserveOut = 5192296858534827628530496329220095;

    swapExactAmountInNewLiquidationPair(
      alice,
      amountIn,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        1,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountIn_MaximumAmountOut() public {
    uint256 amountOut = type(uint112).max - 1;
    uint256 amountOfYield = type(uint112).max - 1;
    // Minimize the swap multiplier and maximize liquidity fraction
    UFixed32x4 swapMultiplier = UFixed32x4.wrap(0);
    UFixed32x4 liquidityFraction = UFixed32x4.wrap(1e4);
    uint128 virtualReserveIn = type(uint112).max;
    uint128 virtualReserveOut = type(uint112).max;
    uint128 expectedVirtualReserveIn = type(uint112).max;
    uint128 expectedVirtualReserveOut = type(uint112).max - 1;

    swapExactAmountInNewLiquidationPairFromAmountOut(
      alice,
      amountOut,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        1,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountIn_AllYieldOut() public {
    uint256 amountOut = 10e18;
    uint256 amountOfYield = 10e18;
    UFixed32x4 swapMultiplier = defaultSwapMultiplier;
    UFixed32x4 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;
    uint128 expectedVirtualReserveIn = 531406100542034222561;
    uint128 expectedVirtualReserveOut = 500000000000000000000;

    swapExactAmountInNewLiquidationPairFromAmountOut(
      alice,
      amountOut,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        defaultMinK,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountIn_NoAmountIn() public {
    uint256 amountIn = 0;
    uint256 amountOfYield = 10e18;
    UFixed32x4 swapMultiplier = defaultSwapMultiplier;
    UFixed32x4 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;
    uint128 expectedVirtualReserveIn = 413223140495867768600;
    uint128 expectedVirtualReserveOut = 500000000000000000000;

    swapExactAmountInNewLiquidationPair(
      alice,
      amountIn,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        defaultMinK,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountIn_MinAmountOut() public {
    uint256 amountOut = 1;
    uint256 amountOfYield = 10e18;
    UFixed32x4 swapMultiplier = defaultSwapMultiplier;
    UFixed32x4 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;
    uint128 expectedVirtualReserveIn = 413223140495867768608;
    uint128 expectedVirtualReserveOut = 500000000000000000000;

    swapExactAmountInNewLiquidationPairFromAmountOut(
      alice,
      amountOut,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        defaultMinK,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testFailSwapExactAmountIn_MoreThanYieldOut() public {
    uint256 amountOut = 100e18;
    uint256 amountOfYield = 10e18;
    UFixed32x4 swapMultiplier = defaultSwapMultiplier;
    UFixed32x4 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;
    uint128 expectedVirtualReserveIn = 100e18;
    uint128 expectedVirtualReserveOut = 100e18;

    swapExactAmountInNewLiquidationPairFromAmountOut(
      alice,
      amountOut,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        defaultMinK,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountIn_MoreThanVirtualReservesOut() public {
    uint256 amountIn = 1e8;
    uint256 amountOfYield = 100e8;
    UFixed32x4 swapMultiplier = defaultSwapMultiplier;
    UFixed32x4 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100;
    uint128 virtualReserveOut = 1;
    uint128 expectedVirtualReserveIn = 495000004950;
    uint128 expectedVirtualReserveOut = 4950;

    swapExactAmountInNewLiquidationPair(
      alice,
      amountIn,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        defaultMinK,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountIn_MaxSwapMultiplier() public {
    uint256 amountIn = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x4 swapMultiplier = UFixed32x4.wrap(1e4);
    UFixed32x4 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;
    uint128 expectedVirtualReserveIn = 431811656826483491815;
    uint128 expectedVirtualReserveOut = 500000000000000000000;

    swapExactAmountInNewLiquidationPair(
      alice,
      amountIn,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        defaultMinK,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountIn_MinSwapMultiplier() public {
    uint256 amountIn = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x4 swapMultiplier = UFixed32x4.wrap(0);
    UFixed32x4 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;
    uint128 expectedVirtualReserveIn = 422364049586776859505;
    uint128 expectedVirtualReserveOut = 500000000000000000000;

    swapExactAmountInNewLiquidationPair(
      alice,
      amountIn,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        defaultMinK,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountIn_MinLiquidityFraction() public {
    uint256 amountIn = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x4 swapMultiplier = defaultSwapMultiplier;
    UFixed32x4 liquidityFraction = UFixed32x4.wrap(1);
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;
    uint128 expectedVirtualReserveIn = 85033102382595556103775;
    uint128 expectedVirtualReserveOut = 100000000000000000000000;

    swapExactAmountInNewLiquidationPair(
      alice,
      amountIn,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        defaultMinK,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountIn_MaxLiquidityFraction() public {
    uint256 amountIn = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x4 swapMultiplier = defaultSwapMultiplier;
    UFixed32x4 liquidityFraction = UFixed32x4.wrap(1e4);
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;
    uint128 expectedVirtualReserveIn = 8503310238259555610;
    uint128 expectedVirtualReserveOut = 10000000000000000000;

    swapExactAmountInNewLiquidationPair(
      alice,
      amountIn,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        defaultMinK,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountIn_MinReserveOut() public {
    uint256 amountIn = 1;
    uint256 amountOfYield = 10;
    UFixed32x4 swapMultiplier = UFixed32x4.wrap(0.3e4);
    UFixed32x4 liquidityFraction = UFixed32x4.wrap(0.02e4);
    uint128 virtualReserveIn = 100;
    uint128 virtualReserveOut = 1;
    uint128 expectedVirtualReserveIn = 600;
    uint128 expectedVirtualReserveOut = 500;

    swapExactAmountInNewLiquidationPair(
      alice,
      amountIn,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        defaultMinK,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountIn_MinReserveIn() public {
    uint256 amountIn = 1;
    uint256 amountOfYield = 100;
    UFixed32x4 swapMultiplier = defaultSwapMultiplier;
    UFixed32x4 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 1;
    uint128 virtualReserveOut = 100;
    uint128 expectedVirtualReserveIn = 214;
    uint128 expectedVirtualReserveOut = 5000;

    swapExactAmountInNewLiquidationPair(
      alice,
      amountIn,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        1,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountIn_MinReserves() public {
    uint256 amountIn = 1;
    uint256 amountOfYield = 1;
    UFixed32x4 swapMultiplier = defaultSwapMultiplier;
    UFixed32x4 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100;
    uint128 virtualReserveOut = 100;
    uint128 expectedVirtualReserveIn = 51;
    uint128 expectedVirtualReserveOut = 50;

    swapExactAmountInNewLiquidationPair(
      alice,
      amountIn,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        1,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountIn_Properties() public {
    uint256 amountOfYield1 = 100;
    uint256 amountOfYield2 = 1000;
    uint256 amountOfYield3 = 10000;
    uint256 wantedAmountOut = 20;
    uint256[] memory exactAmountsIn = new uint256[](3);

    mockLiquidatableBalanceOf(source, tokenOut, amountOfYield1);
    exactAmountsIn[0] = defaultLiquidationPair.computeExactAmountIn(wantedAmountOut);
    vm.clearMockedCalls();
    mockLiquidatableBalanceOf(source, tokenOut, amountOfYield2);
    exactAmountsIn[1] = defaultLiquidationPair.computeExactAmountIn(wantedAmountOut);
    vm.clearMockedCalls();
    mockLiquidatableBalanceOf(source, tokenOut, amountOfYield3);
    exactAmountsIn[2] = defaultLiquidationPair.computeExactAmountIn(wantedAmountOut);

    // As yield increases => amount in decreases (lower price)
    assertGe(exactAmountsIn[0], exactAmountsIn[1]);
    assertGe(exactAmountsIn[1], exactAmountsIn[2]);
  }

  function testSwapExactAmountIn_MinimumValues() public {
    LiquidationPair liquidationPair = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      UFixed32x4.wrap(0),
      UFixed32x4.wrap(1),
      100,
      100,
      1,
      defaultMaxPriceImpact
    );
    uint256 amountOfYield = 1;

    mockLiquidatableBalanceOf(source, tokenOut, amountOfYield);

    uint256 wantedAmountOut = 1;
    uint256 exactAmountIn = liquidationPair.computeExactAmountIn(wantedAmountOut);
    uint256 amountOutMin = liquidationPair.computeExactAmountOut(exactAmountIn);
    mockLiquidateGivenAmountIn(liquidationPair, alice, exactAmountIn, true);

    vm.prank(alice);

    vm.expectEmit(true, false, false, false);
    emit Swapped(alice, exactAmountIn, amountOutMin, 0, 0);

    uint256 swappedAmountOut = liquidationPair.swapExactAmountIn(
      alice,
      exactAmountIn,
      amountOutMin
    );

    assertGe(swappedAmountOut, amountOutMin);
    assertGe(liquidationPair.virtualReserveIn(), swappedAmountOut);
    assertGe(liquidationPair.virtualReserveOut(), amountOfYield);
  }

  function testCannotSwapExactAmountIn_MinNotGuaranteed() public {
    uint256 amountOfYield = 100;

    mockLiquidatableBalanceOf(source, tokenOut, amountOfYield);

    uint256 amountOut = amountOfYield / 10;
    uint256 amountIn = defaultLiquidationPair.computeExactAmountIn(amountOut);

    mockLiquidateGivenAmountOut(defaultLiquidationPair, alice, amountOut, true);

    vm.prank(alice);

    vm.expectRevert(bytes("LiquidationPair/min-not-guaranteed"));
    defaultLiquidationPair.swapExactAmountIn(alice, amountIn, type(uint256).max);
  }

  /* ============ swapExactAmountOut ============ */

  function testSwapExactAmountOut_HappyPath() public {
    uint256 amountOut = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x4 swapMultiplier = defaultSwapMultiplier;
    UFixed32x4 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;
    uint128 expectedVirtualReserveIn = 423166146031251666218;
    uint128 expectedVirtualReserveOut = 500000000000000000000;

    swapExactAmountOutNewLiquidationPair(
      alice,
      amountOut,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        defaultMinK,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountOut_Attack() public {
    // Setup
    uint256 amountOut = 1e18;
    uint256 amountOfYield = 10000e18;
    uint256 maxAmountIn = type(uint256).max;
    UFixed32x4 swapMultiplier = defaultSwapMultiplier;
    UFixed32x4 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 1000000e18;
    uint128 virtualReserveOut = 1000000e18;
    LiquidationPair liquidationPair = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      swapMultiplier,
      liquidityFraction,
      virtualReserveIn,
      virtualReserveOut,
      defaultMinK,
      defaultMaxPriceImpact
    );

    // Swap for a small amount
    mockLiquidatableBalanceOf(source, tokenOut, amountOfYield);
    mockLiquidateGivenAmountOut(liquidationPair, alice, amountOut, true);
    vm.prank(alice);
    uint256 swappedAmountIn = liquidationPair.swapExactAmountOut(alice, amountOut, maxAmountIn);
    uint128 newVirtualReserveIn = liquidationPair.virtualReserveIn();
    uint128 newVirtualReserveOut = liquidationPair.virtualReserveOut();
    amountOfYield -= amountOut;
    logReserveData(newVirtualReserveIn, newVirtualReserveOut, virtualReserveIn, virtualReserveOut);

    // Swap for remainder
    mockLiquidatableBalanceOf(source, tokenOut, amountOfYield);
    mockLiquidateGivenAmountOut(liquidationPair, alice, amountOfYield, true);
    vm.prank(alice);
    swappedAmountIn += liquidationPair.swapExactAmountOut(alice, amountOfYield, maxAmountIn);
    amountOfYield -= amountOut;
  }

  function testSwapExactAmountOut_Attack2() public {
    // Setup
    uint256 amountOut = 1e18;
    uint256 amountOfYield = 10000e18;
    uint256 maxAmountIn = type(uint256).max;
    UFixed32x4 swapMultiplier = defaultSwapMultiplier;
    UFixed32x4 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 1000000e18;
    uint128 virtualReserveOut = 1000000e18;
    LiquidationPair liquidationPair = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      swapMultiplier,
      liquidityFraction,
      virtualReserveIn,
      virtualReserveOut,
      defaultMinK,
      defaultMaxPriceImpact
    );

    // Swap for a small amount
    mockLiquidatableBalanceOf(source, tokenOut, amountOfYield);
    mockLiquidateGivenAmountOut(liquidationPair, alice, amountOfYield, true);
    vm.prank(alice);
    uint256 swappedAmountIn = liquidationPair.swapExactAmountOut(alice, amountOfYield, maxAmountIn);
    uint128 newVirtualReserveIn = liquidationPair.virtualReserveIn();
    uint128 newVirtualReserveOut = liquidationPair.virtualReserveOut();
    logReserveData(newVirtualReserveIn, newVirtualReserveOut, virtualReserveIn, virtualReserveOut);
  }

  function logReserveData(
    uint256 reserveIn,
    uint256 reserveOut,
    uint256 prevReserveIn,
    uint256 prevReserveOut
  ) public {
    console2.log("~~~");
    console2.log("previous reserveIn:   %s ", prevReserveIn);
    console2.log("previous reserveOut:  %s ", prevReserveOut);
    console2.log("previous price:       %s", prevReserveOut / prevReserveIn);
    console2.log("reserveIn:            %s ", reserveIn);
    console2.log("reserveOut:           %s ", reserveOut);
    console2.log("price:                %s", reserveOut / reserveIn);
  }

  function testSwapExactAmountOut_MinSwapMultiplier() public {
    uint256 amountOut = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x4 swapMultiplier = UFixed32x4.wrap(0);
    UFixed32x4 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;
    uint128 expectedVirtualReserveIn = 420839996633280026940;
    uint128 expectedVirtualReserveOut = 500000000000000000000;

    swapExactAmountOutNewLiquidationPair(
      alice,
      amountOut,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        defaultMinK,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountOut_MaxSwapMultiplier() public {
    uint256 amountOut = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x4 swapMultiplier = UFixed32x4.wrap(1e4);
    UFixed32x4 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;
    uint128 expectedVirtualReserveIn = 428669410150891632379;
    uint128 expectedVirtualReserveOut = 500000000000000000000;

    swapExactAmountOutNewLiquidationPair(
      alice,
      amountOut,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        defaultMinK,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountOut_MinLiquidityFraction() public {
    uint256 amountOut = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x4 swapMultiplier = defaultSwapMultiplier;
    UFixed32x4 liquidityFraction = UFixed32x4.wrap(1);
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;
    uint128 expectedVirtualReserveIn = 84633229206250333243790;
    uint128 expectedVirtualReserveOut = 100000000000000000000000;

    swapExactAmountOutNewLiquidationPair(
      alice,
      amountOut,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        defaultMinK,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountOut_MaxLiquidityFraction() public {
    uint256 amountOut = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x4 swapMultiplier = defaultSwapMultiplier;
    UFixed32x4 liquidityFraction = UFixed32x4.wrap(1e4);
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;
    uint128 expectedVirtualReserveIn = 8463322920625033324;
    uint128 expectedVirtualReserveOut = 10000000000000000000;

    swapExactAmountOutNewLiquidationPair(
      alice,
      amountOut,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        defaultMinK,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountOut_MaximumAmountOut() public {
    uint256 amountOut = type(uint112).max;
    uint256 amountOfYield = type(uint112).max;
    uint128 virtualReserveIn = 1000;
    uint128 virtualReserveOut = type(uint112).max;
    UFixed32x4 swapMultiplier = UFixed32x4.wrap(0);
    UFixed32x4 liquidityFraction = UFixed32x4.wrap(1e4);
    uint128 expectedVirtualReserveIn = 1002;
    uint128 expectedVirtualReserveOut = type(uint112).max;

    swapExactAmountOutNewLiquidationPair(
      alice,
      amountOut,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        1,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountOut_MaximumAmountIn() public {
    uint256 amountOfYield = type(uint112).max;
    uint128 _expectedVirtualReserveIn = 1318435852399872841894164877541375;
    uint128 _expectedVirtualReserveOut = type(uint112).max;
    // Higher virtual reserves => higher amount out in virtual buyback => reserves aren't sufficient
    // Need to minimize the virtual reserves to maximize amount in
    uint128 virtualReserveIn = type(uint112).max;
    uint128 virtualReserveOut = type(uint112).max;
    // Minimize the swap multiplier and maximize liquidity fraction
    UFixed32x4 swapMultiplier = UFixed32x4.wrap(0);
    UFixed32x4 liquidityFraction = UFixed32x4.wrap(1e4);

    LiquidationPair liquidationPair = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      swapMultiplier,
      liquidityFraction,
      virtualReserveIn,
      virtualReserveOut,
      1,
      defaultMaxPriceImpact
    );

    mockLiquidatableBalanceOf(source, tokenOut, amountOfYield);
    // Maximum realistic amount is 100% of POOL. 20000x less than this cap.
    uint256 amountOut = liquidationPair.computeExactAmountOut(type(uint104).max);

    swapExactAmountOut(
      alice,
      amountOut,
      amountOfYield,
      liquidationPair,
      _expectedVirtualReserveIn,
      _expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountOut_AllYieldOut() public {
    uint256 amountOut = 10e18;
    uint256 amountOfYield = 10e18;
    UFixed32x4 swapMultiplier = defaultSwapMultiplier;
    UFixed32x4 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;
    uint128 expectedVirtualReserveIn = 531406100542034222561;
    uint128 expectedVirtualReserveOut = 500000000000000000000;

    swapExactAmountOutNewLiquidationPair(
      alice,
      amountOut,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        defaultMinK,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testFailSwapExactAmountOut_MoreThanYieldOut() public {
    uint256 amountOut = 100e18;
    uint256 amountOfYield = 10e18;
    UFixed32x4 swapMultiplier = defaultSwapMultiplier;
    UFixed32x4 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;
    uint128 expectedVirtualReserveIn = 100e18;
    uint128 expectedVirtualReserveOut = 100e18;

    swapExactAmountOutNewLiquidationPair(
      alice,
      amountOut,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        defaultMinK,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountOut_MoreThanVirtualReservesOut() public {
    uint256 amountOut = 4950;
    uint256 amountOfYield = 10e18;
    UFixed32x4 swapMultiplier = defaultSwapMultiplier;
    UFixed32x4 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100;
    uint128 virtualReserveOut = 50;
    uint128 expectedVirtualReserveIn = 2525500000000000000000000;
    uint128 expectedVirtualReserveOut = 500000000000000000000;

    swapExactAmountOutNewLiquidationPair(
      alice,
      amountOut,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        defaultMinK,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountOut_MinAmountOut() public {
    uint256 amountOut = 1;
    uint256 amountOfYield = 10e18;
    UFixed32x4 swapMultiplier = defaultSwapMultiplier;
    UFixed32x4 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;
    uint128 expectedVirtualReserveIn = 413223140495867768608;
    uint128 expectedVirtualReserveOut = 500000000000000000000;

    swapExactAmountOutNewLiquidationPair(
      alice,
      amountOut,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        defaultMinK,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountOut_MinAmountIn() public {
    uint256 amountOfYield = 5e18;
    UFixed32x4 swapMultiplier = defaultSwapMultiplier;
    UFixed32x4 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 10e18;
    uint128 virtualReserveOut = 10e18;
    uint128 expectedVirtualReserveIn = 111111111111111111164;
    uint128 expectedVirtualReserveOut = 250000000000000000000;

    LiquidationPair liquidationPair = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      swapMultiplier,
      liquidityFraction,
      virtualReserveIn,
      virtualReserveOut,
      defaultMinK,
      defaultMaxPriceImpact
    );

    mockLiquidatableBalanceOf(source, tokenOut, amountOfYield);
    uint256 amountOut = liquidationPair.computeExactAmountOut(1);

    swapExactAmountOut(
      alice,
      amountOut,
      amountOfYield,
      liquidationPair,
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountOut_MinReserveOut() public {
    uint256 amountOut = 99;
    uint256 amountOfYield = 10e18;
    UFixed32x4 swapMultiplier = UFixed32x4.wrap(0.3e4);
    UFixed32x4 liquidityFraction = UFixed32x4.wrap(0.02e4);
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 1;
    uint128 expectedVirtualReserveIn = 100000000000000000001;
    uint128 expectedVirtualReserveOut = 1;

    swapExactAmountOutNewLiquidationPair(
      alice,
      amountOut,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        defaultMinK,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountOut_MinReserveIn() public {
    uint256 amountOut = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x4 swapMultiplier = defaultSwapMultiplier;
    UFixed32x4 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 1;
    uint128 virtualReserveOut = 100e18;
    uint128 expectedVirtualReserveIn = 13;
    uint128 expectedVirtualReserveOut = 500000000000000000000;

    swapExactAmountOutNewLiquidationPair(
      alice,
      amountOut,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        defaultMinK,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountOut_MinReserves() public {
    uint256 amountOut = 1;
    uint256 amountOfYield = 10;
    UFixed32x4 swapMultiplier = defaultSwapMultiplier;
    UFixed32x4 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100;
    uint128 virtualReserveOut = 100;
    uint128 expectedVirtualReserveIn = 426;
    uint128 expectedVirtualReserveOut = 500;

    swapExactAmountOutNewLiquidationPair(
      alice,
      amountOut,
      amountOfYield,
      NewLiquidationPairArgs(
        source,
        tokenIn,
        tokenOut,
        swapMultiplier,
        liquidityFraction,
        virtualReserveIn,
        virtualReserveOut,
        1,
        defaultMaxPriceImpact
      ),
      expectedVirtualReserveIn,
      expectedVirtualReserveOut
    );
  }

  function testSwapExactAmountOut_Properties() public {
    uint256 amountOfYield1 = 100;
    uint256 amountOfYield2 = 1000;
    uint256 amountOfYield3 = 10000;
    uint256 wantedAmountIn = 20;
    uint256[] memory exactAmountsOut = new uint256[](3);

    mockLiquidatableBalanceOf(source, tokenOut, amountOfYield1);
    exactAmountsOut[0] = defaultLiquidationPair.computeExactAmountOut(wantedAmountIn);
    vm.clearMockedCalls();
    mockLiquidatableBalanceOf(source, tokenOut, amountOfYield2);
    exactAmountsOut[1] = defaultLiquidationPair.computeExactAmountOut(wantedAmountIn);
    vm.clearMockedCalls();
    mockLiquidatableBalanceOf(source, tokenOut, amountOfYield3);
    exactAmountsOut[2] = defaultLiquidationPair.computeExactAmountOut(wantedAmountIn);

    assertLe(exactAmountsOut[0], exactAmountsOut[1]);
    assertLe(exactAmountsOut[1], exactAmountsOut[2]);
  }

  function testSwapExactAmountOut_MinimumValues() public {
    LiquidationPair liquidationPair = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      UFixed32x4.wrap(0),
      UFixed32x4.wrap(1),
      100,
      100,
      1,
      defaultMaxPriceImpact
    );

    uint256 amountOfYield = 10;
    mockLiquidatableBalanceOf(source, tokenOut, amountOfYield);

    uint256 wantedAmountOut = 1;
    uint256 amountInMax = liquidationPair.computeExactAmountIn(wantedAmountOut);
    mockLiquidateGivenAmountOut(liquidationPair, alice, wantedAmountOut, true);

    vm.prank(alice);

    vm.expectEmit(true, false, false, false);
    emit Swapped(alice, amountInMax, wantedAmountOut, 0, 0);

    uint256 swappedAmountIn = liquidationPair.swapExactAmountOut(
      alice,
      wantedAmountOut,
      amountInMax
    );

    assertLe(swappedAmountIn, amountInMax);
    assertGe(liquidationPair.virtualReserveIn(), swappedAmountIn);
    assertGe(liquidationPair.virtualReserveOut(), amountOfYield);
  }

  function testCannotSwapExactAmountOut_MaxNotGuaranteed() public {
    uint256 amountOfYield = 100;
    mockLiquidatableBalanceOf(source, tokenOut, amountOfYield);

    uint256 amountOut = amountOfYield / 10;

    mockLiquidateGivenAmountOut(defaultLiquidationPair, alice, amountOut, true);

    vm.prank(alice);

    vm.expectRevert(bytes("LiquidationPair/max-not-guaranteed"));
    defaultLiquidationPair.swapExactAmountOut(alice, amountOut, 0);
  }

  /* ============ swapMultiplier ============ */

  function testSwapMultiplier_Properties() public {
    vm.startPrank(alice);

    uint256 amountOut = 100;
    uint256 amountOfYield = 100e18;
    uint128 virtualReserveIn = 1000e18;
    uint128 virtualReserveOut = 1000e18;

    mockLiquidatableBalanceOf(source, tokenOut, amountOfYield);

    LiquidationPair liquidationPair1 = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      UFixed32x4.wrap(0),
      UFixed32x4.wrap(1),
      virtualReserveIn,
      virtualReserveOut,
      defaultMinK,
      defaultMaxPriceImpact
    );

    mockLiquidateGivenAmountOut(liquidationPair1, alice, amountOut, true);
    uint256 amountIn1 = liquidationPair1.swapExactAmountOut(alice, amountOut, type(uint256).max);

    LiquidationPair liquidationPair2 = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      UFixed32x4.wrap(1e4),
      UFixed32x4.wrap(1),
      virtualReserveIn,
      virtualReserveOut,
      defaultMinK,
      defaultMaxPriceImpact
    );

    mockLiquidateGivenAmountOut(liquidationPair2, alice, amountOut, true);
    uint256 amountIn2 = liquidationPair2.swapExactAmountOut(alice, amountOut, type(uint256).max);

    LiquidationPair liquidationPair3 = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      UFixed32x4.wrap(1e4),
      UFixed32x4.wrap(1),
      virtualReserveIn,
      virtualReserveOut,
      defaultMinK,
      defaultMaxPriceImpact
    );

    mockLiquidateGivenAmountOut(liquidationPair3, alice, amountOut, true);
    uint256 amountIn3 = liquidationPair3.swapExactAmountOut(alice, amountOut, type(uint256).max);

    vm.stopPrank();

    assertEq(amountIn1, amountIn2);
    assertEq(amountIn2, amountIn3);
    assertGe(liquidationPair2.virtualReserveIn(), liquidationPair1.virtualReserveIn());
    assertGe(liquidationPair3.virtualReserveIn(), liquidationPair2.virtualReserveIn());
    assertLe(liquidationPair2.virtualReserveOut(), liquidationPair1.virtualReserveOut());
    assertLe(liquidationPair3.virtualReserveOut(), liquidationPair2.virtualReserveOut());
  }

  function testSwapMultiplier_ReserveOutIsHigherWhenSMIsHigher() public {
    vm.startPrank(alice);

    uint256 amountOut = 1e18;
    uint256 amountOfYield = 100e18;
    uint128 virtualReserveIn = 1000e18;
    uint128 virtualReserveOut = 1000e18;

    mockLiquidatableBalanceOf(source, tokenOut, amountOfYield);

    LiquidationPair liquidationPair1 = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      UFixed32x4.wrap(0),
      UFixed32x4.wrap(1),
      virtualReserveIn,
      virtualReserveOut,
      defaultMinK,
      defaultMaxPriceImpact
    );

    mockLiquidateGivenAmountOut(liquidationPair1, alice, amountOut, true);
    uint256 amountIn1 = liquidationPair1.swapExactAmountOut(alice, amountOut, type(uint256).max);

    LiquidationPair liquidationPair2 = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      UFixed32x4.wrap(1e4),
      UFixed32x4.wrap(1),
      virtualReserveIn,
      virtualReserveOut,
      defaultMinK,
      defaultMaxPriceImpact
    );

    mockLiquidateGivenAmountOut(liquidationPair2, alice, amountOut, true);
    uint256 amountIn2 = liquidationPair2.swapExactAmountOut(alice, amountOut, type(uint256).max);

    LiquidationPair liquidationPair3 = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      UFixed32x4.wrap(1e4),
      UFixed32x4.wrap(1),
      virtualReserveIn,
      virtualReserveOut,
      defaultMinK,
      defaultMaxPriceImpact
    );

    mockLiquidateGivenAmountOut(liquidationPair3, alice, amountOut, true);
    uint256 amountIn3 = liquidationPair3.swapExactAmountOut(alice, amountOut, type(uint256).max);

    vm.stopPrank();

    assertEq(amountIn1, amountIn2);
    assertEq(amountIn2, amountIn3);
    assertGe(liquidationPair2.virtualReserveIn(), liquidationPair1.virtualReserveIn());
    assertGe(liquidationPair3.virtualReserveIn(), liquidationPair2.virtualReserveIn());
    assertLe(liquidationPair2.virtualReserveOut(), liquidationPair1.virtualReserveOut());
    assertLe(liquidationPair3.virtualReserveOut(), liquidationPair2.virtualReserveOut());
  }

  /* ============ liquidityFraction ============ */

  function testLiquidityFraction_Properties() public {
    mockLiquidatableBalanceOf(source, tokenOut, 1000);

    vm.startPrank(alice);

    LiquidationPair liquidationPair1 = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      UFixed32x4.wrap(0),
      UFixed32x4.wrap(1),
      1000,
      1000,
      defaultMinK,
      defaultMaxPriceImpact
    );
    uint256 amountOut = 10;

    mockLiquidateGivenAmountOut(liquidationPair1, alice, amountOut, true);
    uint256 amountIn1 = liquidationPair1.swapExactAmountOut(alice, amountOut, type(uint256).max);

    LiquidationPair liquidationPair2 = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      UFixed32x4.wrap(0),
      UFixed32x4.wrap(1e4),
      1000,
      1000,
      defaultMinK,
      defaultMaxPriceImpact
    );

    mockLiquidateGivenAmountOut(liquidationPair2, alice, amountOut, true);
    uint256 amountIn2 = liquidationPair2.swapExactAmountOut(alice, amountOut, type(uint256).max);

    LiquidationPair liquidationPair3 = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      UFixed32x4.wrap(0),
      UFixed32x4.wrap(1e4),
      1000,
      1000,
      defaultMinK,
      defaultMaxPriceImpact
    );

    mockLiquidateGivenAmountOut(liquidationPair3, alice, amountOut, true);
    uint256 amountIn3 = liquidationPair3.swapExactAmountOut(alice, amountOut, type(uint256).max);

    // Asserts that lower liquidity fractions => higher amplification of swaps =>  higher virtual reserves
    assertEq(amountIn1, amountIn2);
    assertEq(amountIn2, amountIn3);
    assertGe(liquidationPair1.virtualReserveIn(), liquidationPair2.virtualReserveIn());
    assertGe(liquidationPair2.virtualReserveIn(), liquidationPair3.virtualReserveIn());
    assertGe(liquidationPair1.virtualReserveOut(), liquidationPair2.virtualReserveOut());
    assertGe(liquidationPair2.virtualReserveOut(), liquidationPair3.virtualReserveOut());

    vm.stopPrank();
  }
}

// Assume tokenOut is wrapped BTC, tokenIn is a USD stablecoin
// Initial reserve ratio is ~ 1:25000
contract LiquidationPairBitcoinScenarioTest is LiquidationPairTestSetup {
  /* ============ Variables ============ */

  UFixed32x4 public defaultSwapMultiplier;
  UFixed32x4 public defaultLiquidityFraction;
  uint128 public defaultVirtualReserveIn;
  uint128 public defaultVirtualReserveOut;
  uint256 public defaultMinK;
  UFixed32x4 public defaultMaxPriceImpact;

  LiquidationPair public defaultLiquidationPair;

  /* ============ Set up ============ */

  function setUp() public virtual override {
    super.setUp();
    defaultSwapMultiplier = UFixed32x4.wrap(0.3e4);
    defaultLiquidityFraction = UFixed32x4.wrap(0.02e4);
    defaultVirtualReserveIn = 1198574999999999899456; // 1e18
    defaultVirtualReserveOut = 4794300; //1e8
    defaultMinK = 5746328122499999517961900800;
    defaultMaxPriceImpact = UFixed32x4.wrap(9999);

    defaultLiquidationPair = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      defaultSwapMultiplier,
      defaultLiquidityFraction,
      defaultVirtualReserveIn,
      defaultVirtualReserveOut,
      defaultMinK,
      defaultMaxPriceImpact
    );
  }

  /* ============ External Functions ============ */

  /* ============ computeExactAmountIn ============ */

  function testComputeExactAmountIn_HappyPath() public {
    mockLiquidatableBalanceOf(source, tokenOut, 1e8);
    uint256 amountIn = defaultLiquidationPair.computeExactAmountIn(1e6); // 1% of yield
    assertEq(amountIn, 528298351814435099);
  }

  /* ============ computeExactAmountOut ============ */

  function testComputeExactAmountOut_HappyPath() public {
    mockLiquidatableBalanceOf(source, tokenOut, 1e8);
    uint256 amountOut = defaultLiquidationPair.computeExactAmountOut(25000e16);
    assertEq(amountOut, 85943642);
  }

  /* ============ computeExactAmount ============ */

  function testComputeExactAmount_Fuzz(uint256 amountOfYield) public {
    // Semi-realistic range of yield
    amountOfYield = bound(amountOfYield, 101, 100000e8);
    mockLiquidatableBalanceOf(source, tokenOut, amountOfYield);
    uint256 maxAmountOut = defaultLiquidationPair.maxAmountOut();
    uint256 _amountOut = maxAmountOut / 100; // 1% of max amount out
    uint256 amountIn = defaultLiquidationPair.computeExactAmountIn(_amountOut);
    uint256 amountOut = defaultLiquidationPair.computeExactAmountOut(amountIn);
    assertEq(_amountOut, amountOut);
  }

  /* ============ swapExactAmountIn ============ */
  function testSwapExactAmountIn_MaxOut(uint112 amountOfYield) public {
    // Semi-realistic range of yield
    amountOfYield = uint112(bound(amountOfYield, 1, 1e13));
    mockLiquidatableBalanceOf(source, tokenOut, amountOfYield);
    uint256 amountOut = defaultLiquidationPair.maxAmountOut();
    uint256 amountIn = defaultLiquidationPair.computeExactAmountIn(amountOut);
    mockLiquidateGivenAmountIn(defaultLiquidationPair, alice, amountIn, true);
    vm.prank(alice);
    defaultLiquidationPair.swapExactAmountIn(alice, amountIn, 0);
  }

  /* ============ swapExactAmountOut ============ */

  function testSwapExactAmountOut_MaxOut(uint112 amountOfYield) public {
    amountOfYield = uint112(bound(amountOfYield, 1, 1e13));
    mockLiquidatableBalanceOf(source, tokenOut, amountOfYield);
    uint256 amountOut = defaultLiquidationPair.maxAmountOut();
    mockLiquidateGivenAmountOut(defaultLiquidationPair, alice, amountOut, true);
    vm.prank(alice);
    defaultLiquidationPair.swapExactAmountOut(alice, amountOut, type(uint112).max);
  }
}
