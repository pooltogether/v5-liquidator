// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";

import { LiquidationPairFactory } from "src/LiquidationPairFactory.sol";
import { LiquidationPair } from "src/LiquidationPair.sol";
import { LiquidationRouter } from "src/LiquidationRouter.sol";

import { ILiquidationSource } from "src/interfaces/ILiquidationSource.sol";

import { LiquidatorLib } from "src/libraries/LiquidatorLib.sol";
import { UFixed32x9 } from "src/libraries/FixedMathLib.sol";

import { BaseSetup } from "./utils/BaseSetup.sol";

struct NewLiquidationPairArgs {
  address source;
  address tokenIn;
  address tokenOut;
  UFixed32x9 swapMultiplier;
  UFixed32x9 liquidityFraction;
  uint128 virtualReserveIn;
  uint128 virtualReserveOut;
  uint256 minK;
}

contract LiquidationPairTestSetup is BaseSetup {
  /* ============ Variables ============ */

  address public target;
  address public tokenIn;
  address public tokenOut;
  address public source;

  /* ============ Events ============ */

  event Swapped(address indexed account, uint256 amountIn, uint256 amountOut);

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
    LiquidationPair _liquidationPair
  ) internal {
    mockAvailableBalanceOf(
      address(_liquidationPair.source()),
      _liquidationPair.tokenOut(),
      _amountOfYield
    );

    mockLiquidateGivenAmountIn(_liquidationPair, _user, _amountIn, true);
    uint256 amountOut = _liquidationPair.computeExactAmountOut(_amountIn);

    vm.startPrank(_user);

    vm.expectEmit(true, false, false, true);
    emit Swapped(_user, _amountIn, amountOut);

    uint256 swappedAmountOut = _liquidationPair.swapExactAmountIn(_user, _amountIn, amountOut);

    vm.stopPrank();

    assertGe(swappedAmountOut, amountOut);
  }

  function swapExactAmountInNewLiquidationPair(
    address _user,
    uint256 _amountIn,
    uint256 _amountOfYield,
    NewLiquidationPairArgs memory _lpArgs
  ) internal {
    LiquidationPair liquidationPair = new LiquidationPair(
      ILiquidationSource(_lpArgs.source),
      _lpArgs.tokenIn,
      _lpArgs.tokenOut,
      _lpArgs.swapMultiplier,
      _lpArgs.liquidityFraction,
      _lpArgs.virtualReserveIn,
      _lpArgs.virtualReserveOut,
      _lpArgs.minK
    );
    swapExactAmountIn(_user, _amountIn, _amountOfYield, liquidationPair);
  }

  function swapExactAmountInNewLiquidationPairFromAmountOut(
    address _user,
    uint256 _amountOut,
    uint256 _amountOfYield,
    NewLiquidationPairArgs memory _lpArgs
  ) internal {
    LiquidationPair liquidationPair = new LiquidationPair(
      ILiquidationSource(_lpArgs.source),
      _lpArgs.tokenIn,
      _lpArgs.tokenOut,
      _lpArgs.swapMultiplier,
      _lpArgs.liquidityFraction,
      _lpArgs.virtualReserveIn,
      _lpArgs.virtualReserveOut,
      _lpArgs.minK
    );

    mockAvailableBalanceOf(_lpArgs.source, _lpArgs.tokenOut, _amountOfYield);

    uint256 amountIn = liquidationPair.computeExactAmountIn(_amountOut);
    uint256 amountOutMin = liquidationPair.computeExactAmountOut(amountIn);

    vm.startPrank(_user);

    mockLiquidateGivenAmountIn(liquidationPair, _user, amountIn, true);

    vm.expectEmit(true, false, false, true);
    emit Swapped(_user, amountIn, amountOutMin);

    uint256 swappedAmountOut = liquidationPair.swapExactAmountIn(_user, amountIn, amountOutMin);

    vm.stopPrank();

    assertGe(swappedAmountOut, amountOutMin);
  }

  /* ============ swapExactAmountOut ============ */

  function swapExactAmountOut(
    address _user,
    uint256 _amountOut,
    uint256 _amountOfYield,
    LiquidationPair _liquidationPair
  ) internal {
    mockAvailableBalanceOf(
      address(_liquidationPair.source()),
      _liquidationPair.tokenOut(),
      _amountOfYield
    );
    uint256 amountIn = _liquidationPair.computeExactAmountIn(_amountOut);
    mockLiquidateGivenAmountOut(_liquidationPair, alice, _amountOut, true);

    vm.expectEmit(true, false, false, true);
    emit Swapped(_user, amountIn, _amountOut);

    vm.prank(_user);
    uint256 swappedAmountIn = _liquidationPair.swapExactAmountOut(_user, _amountOut, amountIn);

    assertEq(swappedAmountIn, amountIn);
    // TODO: Get expected values!!!!!!!!!!!
    // assertEq(_liquidationPair.virtualReserveIn(), expectedReserveIn);
    // assertEq(_liquidationPair.virtualReserveOut(), expectedReserveOut);
  }

  function swapExactAmountOutNewLiquidationPair(
    address _user,
    uint256 _amountOut,
    uint256 _amountOfYield,
    NewLiquidationPairArgs memory _lpArgs
  ) internal {
    LiquidationPair liquidationPair = new LiquidationPair(
      ILiquidationSource(_lpArgs.source),
      _lpArgs.tokenIn,
      _lpArgs.tokenOut,
      _lpArgs.swapMultiplier,
      _lpArgs.liquidityFraction,
      _lpArgs.virtualReserveIn,
      _lpArgs.virtualReserveOut,
      _lpArgs.minK
    );
    swapExactAmountOut(alice, _amountOut, _amountOfYield, liquidationPair);
  }

  /* ============ Mocks ============ */

  function mockAvailableBalanceOf(address _source, address _tokenOut, uint256 _result) internal {
    vm.mockCall(
      _source,
      abi.encodeWithSelector(ILiquidationSource.availableBalanceOf.selector, _tokenOut),
      abi.encode(_result)
    );
  }

  function mockTarget(address _source, uint256 _result) internal {
    vm.mockCall(
      _source,
      abi.encodeWithSelector(ILiquidationSource.targetOf.selector),
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

  UFixed32x9 public defaultSwapMultiplier;
  UFixed32x9 public defaultLiquidityFraction;
  uint128 public defaultVirtualReserveIn;
  uint128 public defaultVirtualReserveOut;
  uint256 public defaultMinK;

  LiquidationPair public defaultLiquidationPair;

  /* ============ Set up ============ */

  function setUp() public virtual override {
    super.setUp();
    defaultSwapMultiplier = UFixed32x9.wrap(0.3e9);
    defaultLiquidityFraction = UFixed32x9.wrap(0.02e9);
    defaultVirtualReserveIn = 100;
    defaultVirtualReserveOut = 100;
    defaultMinK = 100;

    defaultLiquidationPair = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      defaultSwapMultiplier,
      defaultLiquidityFraction,
      defaultVirtualReserveIn,
      defaultVirtualReserveOut,
      defaultMinK
    );
  }

  /* ============ Constructor ============ */

  function testConstructor_HappyPath() public {
    assertEq(address(defaultLiquidationPair.source()), source);
    assertEq(address(defaultLiquidationPair.tokenIn()), tokenIn);
    assertEq(address(defaultLiquidationPair.tokenOut()), tokenOut);
    assertEq(
      UFixed32x9.unwrap(defaultLiquidationPair.swapMultiplier()),
      UFixed32x9.unwrap(defaultSwapMultiplier)
    );
    assertEq(
      UFixed32x9.unwrap(defaultLiquidationPair.liquidityFraction()),
      UFixed32x9.unwrap(defaultLiquidityFraction)
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
      UFixed32x9.wrap(0),
      defaultVirtualReserveIn,
      defaultVirtualReserveOut,
      defaultMinK
    );
  }

  function testConstructor_LiquidityFractionTooLarge() public {
    vm.expectRevert(bytes("LiquidationPair/liquidity-fraction-less-than-one"));
    new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      defaultSwapMultiplier,
      UFixed32x9.wrap(1e9 + 1),
      defaultVirtualReserveIn,
      defaultVirtualReserveOut,
      defaultMinK
    );
  }

  function testConstructor_SwapMultiplierTooLarge() public {
    vm.expectRevert(bytes("LiquidationPair/swap-multiplier-less-than-one"));
    new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      UFixed32x9.wrap(1e9 + 1),
      defaultLiquidityFraction,
      defaultVirtualReserveIn,
      defaultVirtualReserveOut,
      defaultMinK
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
      100
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
      defaultMinK
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
      defaultMinK
    );
  }

  /* ============ External functions ============ */

  // function testSwapExactAmountOut_TEST() public {
  //   // Happy path
  //   // swapExactAmountOutNewLiquidationPair(
  //   //   alice,
  //   //   1e18,
  //   //   10e18,
  //   //   source,
  //   //   tokenOut,
  //   //   UFixed32x9.wrap(0.3e9),
  //   //   UFixed32x9.wrap(0.02e9),
  //   //   100e18,
  //   //   100e18
  //   // );
  //   // Reserves set to 0
  //   swapExactAmountOutNewLiquidationPair(
  //     alice,
  //     10,
  //     100,
  //     source,
  //     tokenOut,
  //     UFixed32x9.wrap(0.3e9),
  //     UFixed32x9.wrap(0.02e9),
  //     1e18,
  //     1e18,
  //     defaultMinK
  //   );
  //   // Reserves set to 0
  //   // swapExactAmountOutNewLiquidationPair(
  //   //   alice,
  //   //   1e18,
  //   //   10e18,
  //   //   source,
  //   //   tokenOut,
  //   //   UFixed32x9.wrap(0.3e9),
  //   //   UFixed32x9.wrap(0.02e9),
  //   //   100e18,
  //   //   100e18
  //   // );
  // }

  // function testSwapExactAmountOut_TEST() public {
  //   uint256 amountOut = 1e5;
  //   uint256 amountOfYield = 1e10;
  //   UFixed32x9 swapMultiplier = defaultSwapMultiplier;
  //   UFixed32x9 liquidityFraction = defaultLiquidityFraction;
  //   uint128 virtualReserveIn = 1e6;
  //   uint128 virtualReserveOut = 1e18;

  //   LiquidationPair _liquidationPair = new LiquidationPair(
  //     ILiquidationSource(source),
  //     tokenIn,
  //     tokenOut,
  //     swapMultiplier,
  //     liquidityFraction,
  //     virtualReserveIn,
  //     virtualReserveOut
  //   );

  //   swapExactAmountOut(alice, amountOut, amountOfYield, _liquidationPair, source, tokenOut);
  // }

  /* ============ maxAmountOut ============ */

  function testMaxAmountOut_HappyPath() public {
    mockAvailableBalanceOf(source, tokenOut, 0);
    uint256 amountOut = defaultLiquidationPair.maxAmountOut();
    assertEq(amountOut, 0);
  }

  /* ============ nextLiquidationState ============ */

  function testNextLiquidationState_HappyPath() public {
    mockAvailableBalanceOf(source, tokenOut, 0);

    (uint256 virtualReserveIn, uint256 virtualReserveOut) = defaultLiquidationPair
      .nextLiquidationState();

    assertEq(virtualReserveIn, defaultVirtualReserveIn);
    assertEq(virtualReserveOut, defaultVirtualReserveOut);
  }

  /* ============ computeExactAmountIn ============ */

  function testComputeExactAmountIn_HappyPath() public {
    // NOTE: This looks strange. But since virtual reserves are so low, prices change accordingly
    mockAvailableBalanceOf(source, tokenOut, 10);
    uint256 amountIn = defaultLiquidationPair.computeExactAmountIn(1);
    assertEq(amountIn, 1);
    vm.clearMockedCalls();

    mockAvailableBalanceOf(source, tokenOut, 10e8);
    amountIn = defaultLiquidationPair.computeExactAmountIn(5e8);
    assertEq(amountIn, 1);
    vm.clearMockedCalls();

    mockAvailableBalanceOf(source, tokenOut, 10e18);
    amountIn = defaultLiquidationPair.computeExactAmountIn(5e18);
    assertEq(amountIn, 1);
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
      defaultMinK
    );

    mockAvailableBalanceOf(source, tokenOut, 10);
    uint256 amountIn = liquidationPair.computeExactAmountIn(5);
    assertEq(amountIn, 5);
    vm.clearMockedCalls();

    mockAvailableBalanceOf(source, tokenOut, 10e8);
    amountIn = liquidationPair.computeExactAmountIn(5e8);
    assertEq(amountIn, 5e8);
    vm.clearMockedCalls();

    mockAvailableBalanceOf(source, tokenOut, 10e18);
    amountIn = liquidationPair.computeExactAmountIn(5e18);
    assertEq(amountIn, 4992508740634677667);
    vm.clearMockedCalls();
  }

  /* ============ computeExactAmountOut ============ */

  function testComputeExactAmountOut_HappyPath() public {
    mockAvailableBalanceOf(source, tokenOut, 10);
    uint256 amountOut = defaultLiquidationPair.computeExactAmountOut(1);
    assertEq(amountOut, 1);
    vm.clearMockedCalls();

    mockAvailableBalanceOf(source, tokenOut, 10e8);
    amountOut = defaultLiquidationPair.computeExactAmountOut(1);
    assertEq(amountOut, 500000050);
    vm.clearMockedCalls();

    mockAvailableBalanceOf(source, tokenOut, 10e18);
    amountOut = defaultLiquidationPair.computeExactAmountOut(1);
    assertEq(amountOut, 5000000000000000050);
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
      defaultMinK
    );

    mockAvailableBalanceOf(source, tokenOut, 10);
    uint256 amountOut = liquidationPair.computeExactAmountOut(5);
    assertEq(amountOut, 5);
    vm.clearMockedCalls();

    mockAvailableBalanceOf(source, tokenOut, 10e8);
    amountOut = liquidationPair.computeExactAmountOut(5e8);
    assertEq(amountOut, 5e8);
    vm.clearMockedCalls();

    mockAvailableBalanceOf(source, tokenOut, 10e18);
    amountOut = liquidationPair.computeExactAmountOut(5e18);
    assertEq(amountOut, 5007498746877187967);
    vm.clearMockedCalls();
  }

  /* ============ swapExactAmountIn ============ */

  function testSwapExactAmountIn_HappyPath() public {
    uint256 amountIn = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x9 swapMultiplier = defaultSwapMultiplier;
    UFixed32x9 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;

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
        defaultMinK
      )
    );
  }

  function testSwapExactAmountIn_MaximumAmountIn() public {
    uint256 amountIn = type(uint112).max;
    uint256 amountOfYield = type(uint112).max;
    // Minimize the swap multiplier and maximize liquidity fraction
    UFixed32x9 swapMultiplier = UFixed32x9.wrap(0);
    UFixed32x9 liquidityFraction = UFixed32x9.wrap(1e9);
    // Need to minimize the virtual reserves to maximize amount in
    uint128 virtualReserveIn = 1;
    uint128 virtualReserveOut = 1;

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
        1
      )
    );
  }

  function testSwapExactAmountIn_MaximumAmountOut() public {
    uint256 amountOut = type(uint112).max;
    uint256 amountOfYield = type(uint112).max;
    UFixed32x9 swapMultiplier = defaultSwapMultiplier;
    UFixed32x9 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = type(uint112).max;
    uint128 virtualReserveOut = type(uint112).max;

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
        defaultMinK
      )
    );
  }

  function testSwapExactAmountIn_AllYieldOut() public {
    uint256 amountOut = 10e18;
    uint256 amountOfYield = 10e18;
    UFixed32x9 swapMultiplier = defaultSwapMultiplier;
    UFixed32x9 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;

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
        defaultMinK
      )
    );
  }

  function testSwapExactAmountIn_NoAmountIn() public {
    uint256 amountIn = 0;
    uint256 amountOfYield = 10e18;
    UFixed32x9 swapMultiplier = defaultSwapMultiplier;
    UFixed32x9 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;

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
        defaultMinK
      )
    );
  }

  function testSwapExactAmountIn_MinAmountOut() public {
    uint256 amountOut = 1;
    uint256 amountOfYield = 10e18;
    UFixed32x9 swapMultiplier = defaultSwapMultiplier;
    UFixed32x9 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;

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
        defaultMinK
      )
    );
  }

  function testFailSwapExactAmountIn_MoreThanYieldOut() public {
    uint256 amountOut = 100e18;
    uint256 amountOfYield = 10e18;
    UFixed32x9 swapMultiplier = defaultSwapMultiplier;
    UFixed32x9 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;

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
        defaultMinK
      )
    );
  }

  function testSwapExactAmountIn_MoreThanVirtualReservesOut() public {
    uint256 amountIn = 1e8;
    uint256 amountOfYield = 10e18;
    UFixed32x9 swapMultiplier = defaultSwapMultiplier;
    UFixed32x9 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100;
    uint128 virtualReserveOut = 100;

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
        defaultMinK
      )
    );
  }

  function testSwapExactAmountIn_MaxSwapMultiplier() public {
    uint256 amountIn = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x9 swapMultiplier = UFixed32x9.wrap(1e9);
    UFixed32x9 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;

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
        defaultMinK
      )
    );
  }

  function testSwapExactAmountIn_MinSwapMultiplier() public {
    uint256 amountIn = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x9 swapMultiplier = UFixed32x9.wrap(0);
    UFixed32x9 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;

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
        defaultMinK
      )
    );
  }

  function testSwapExactAmountIn_MinLiquidityFraction() public {
    uint256 amountIn = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x9 swapMultiplier = defaultSwapMultiplier;
    UFixed32x9 liquidityFraction = UFixed32x9.wrap(1);
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;

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
        defaultMinK
      )
    );
  }

  function testSwapExactAmountIn_MaxLiquidityFraction() public {
    uint256 amountIn = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x9 swapMultiplier = defaultSwapMultiplier;
    UFixed32x9 liquidityFraction = UFixed32x9.wrap(1e9);
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;

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
        defaultMinK
      )
    );
  }

  function testSwapExactAmountIn_MinReserveOut() public {
    uint256 amountIn = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x9 swapMultiplier = UFixed32x9.wrap(0.3e9);
    UFixed32x9 liquidityFraction = UFixed32x9.wrap(0.02e9);
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 1;

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
        defaultMinK
      )
    );
  }

  function testSwapExactAmountIn_MinReserveIn() public {
    uint256 amountIn = 1e18;
    uint256 amountOfYield = 100e18;
    UFixed32x9 swapMultiplier = defaultSwapMultiplier;
    UFixed32x9 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 1;
    uint128 virtualReserveOut = 100;

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
        1
      )
    );
  }

  function testSwapExactAmountIn_MinReserves() public {
    uint256 amountIn = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x9 swapMultiplier = defaultSwapMultiplier;
    UFixed32x9 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 1;
    uint128 virtualReserveOut = 1;

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
        1
      )
    );
  }

  function testSwapExactAmountIn_Properties() public {
    uint256 amountOfYield1 = 100;
    uint256 amountOfYield2 = 1000;
    uint256 amountOfYield3 = 10000;
    uint256 wantedAmountOut = 20;
    uint256[] memory exactAmountsIn = new uint256[](3);

    mockAvailableBalanceOf(source, tokenOut, amountOfYield1);
    exactAmountsIn[0] = defaultLiquidationPair.computeExactAmountIn(wantedAmountOut);
    vm.clearMockedCalls();
    mockAvailableBalanceOf(source, tokenOut, amountOfYield2);
    exactAmountsIn[1] = defaultLiquidationPair.computeExactAmountIn(wantedAmountOut);
    vm.clearMockedCalls();
    mockAvailableBalanceOf(source, tokenOut, amountOfYield3);
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
      UFixed32x9.wrap(0),
      UFixed32x9.wrap(1),
      1,
      1,
      1
    );
    uint256 amountOfYield = 1;

    mockAvailableBalanceOf(source, tokenOut, amountOfYield);

    uint256 wantedAmountOut = 1;
    uint256 exactAmountIn = liquidationPair.computeExactAmountIn(wantedAmountOut);
    uint256 amountOutMin = liquidationPair.computeExactAmountOut(exactAmountIn);
    mockLiquidateGivenAmountIn(liquidationPair, alice, exactAmountIn, true);

    vm.startPrank(alice);

    vm.expectEmit(true, false, false, true);
    emit Swapped(alice, exactAmountIn, amountOutMin);

    uint256 swappedAmountOut = liquidationPair.swapExactAmountIn(
      alice,
      exactAmountIn,
      amountOutMin
    );

    vm.stopPrank();

    assertGe(swappedAmountOut, amountOutMin);
    assertGe(liquidationPair.virtualReserveIn(), swappedAmountOut);
    assertGe(liquidationPair.virtualReserveOut(), amountOfYield);
  }

  function testCannotSwapExactAmountIn_MinNotGuaranteed() public {
    uint256 amountOfYield = 100;

    mockAvailableBalanceOf(source, tokenOut, amountOfYield);

    uint256 amountOut = amountOfYield / 10;
    uint256 amountIn = defaultLiquidationPair.computeExactAmountIn(amountOut);

    mockLiquidateGivenAmountOut(defaultLiquidationPair, alice, amountOut, true);

    vm.startPrank(alice);

    vm.expectRevert(bytes("LiquidationPair/min-not-guaranteed"));
    defaultLiquidationPair.swapExactAmountIn(alice, amountIn, type(uint256).max);

    vm.stopPrank();
  }

  /* ============ swapExactAmountOut ============ */

  // 1. Switch all of these to use amountOutNewLiq
  // Compute all of the expected values and hardcode them.

  // 2. Implement the scaling again.

  // 3. implement setting the minimum and find a counter case where that
  // doesn't really matter. ie getting the reserves to be set to 0 with
  // a swap that has a large amount of virtual reserve.

  function testSwapExactAmountOut_HappyPath() public {
    uint256 amountOut = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x9 swapMultiplier = defaultSwapMultiplier;
    UFixed32x9 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;

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
        defaultMinK
      )
    );
  }

  function testSwapExactAmountOut_MinSwapMultiplier() public {
    uint256 amountOut = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x9 swapMultiplier = UFixed32x9.wrap(0);
    UFixed32x9 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;

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
        defaultMinK
      )
    );
  }

  function testSwapExactAmountOut_MaxSwapMultiplier() public {
    uint256 amountOut = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x9 swapMultiplier = UFixed32x9.wrap(1e9);
    UFixed32x9 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;

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
        defaultMinK
      )
    );
  }

  function testSwapExactAmountOut_MinLiquidityFraction() public {
    uint256 amountOut = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x9 swapMultiplier = defaultSwapMultiplier;
    UFixed32x9 liquidityFraction = UFixed32x9.wrap(1);
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;

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
        defaultMinK
      )
    );
  }

  function testSwapExactAmountOut_MaxLiquidityFraction() public {
    uint256 amountOut = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x9 swapMultiplier = defaultSwapMultiplier;
    UFixed32x9 liquidityFraction = UFixed32x9.wrap(1e9);
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;

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
        defaultMinK
      )
    );
  }

  function testSwapExactAmountOut_MaximumAmountOut() public {
    uint256 amountOut = type(uint112).max;
    uint256 amountOfYield = type(uint112).max;
    uint128 virtualReserveIn = type(uint112).max;
    uint128 virtualReserveOut = type(uint112).max;
    UFixed32x9 swapMultiplier = defaultSwapMultiplier;
    UFixed32x9 liquidityFraction = defaultLiquidityFraction;

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
        defaultMinK
      )
    );
  }

  function testSwapExactAmountOut_MaximumAmountIn() public {
    uint256 amountOfYield = type(uint112).max;
    // Higher virtual reserves -> higher amount out in virtual buyback -> reserves aren't sufficient
    // Need to minimize the virtual reserves to maximize amount in
    uint128 virtualReserveIn = 1;
    uint128 virtualReserveOut = 1;
    // Minimize the swap multiplier and maximize liquidity fraction
    UFixed32x9 swapMultiplier = UFixed32x9.wrap(0);
    UFixed32x9 liquidityFraction = UFixed32x9.wrap(1e9);

    LiquidationPair liquidationPair = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      swapMultiplier,
      liquidityFraction,
      virtualReserveIn,
      virtualReserveOut,
      1
    );

    mockAvailableBalanceOf(source, tokenOut, amountOfYield);
    uint256 amountOut = liquidationPair.computeExactAmountOut(type(uint112).max);

    swapExactAmountOut(alice, amountOut, amountOfYield, liquidationPair);
  }

  function testSwapExactAmountOut_AllYieldOut() public {
    uint256 amountOut = 10e18;
    uint256 amountOfYield = 10e18;
    UFixed32x9 swapMultiplier = defaultSwapMultiplier;
    UFixed32x9 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;

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
        defaultMinK
      )
    );
  }

  function testFailSwapExactAmountOut_MoreThanYieldOut() public {
    uint256 amountOut = 100e18;
    uint256 amountOfYield = 10e18;
    UFixed32x9 swapMultiplier = defaultSwapMultiplier;
    UFixed32x9 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;

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
        defaultMinK
      )
    );
  }

  function testSwapExactAmountOut_MoreThanVirtualReservesOut() public {
    uint256 amountOut = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x9 swapMultiplier = defaultSwapMultiplier;
    UFixed32x9 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100;
    uint128 virtualReserveOut = 100;

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
        defaultMinK
      )
    );
  }

  function testSwapExactAmountOut_MinAmountOut() public {
    uint256 amountOut = 1;
    uint256 amountOfYield = 10e18;
    UFixed32x9 swapMultiplier = defaultSwapMultiplier;
    UFixed32x9 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 100e18;

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
        defaultMinK
      )
    );
  }

  function testSwapExactAmountOut_MinAmountIn() public {
    uint256 amountOfYield = 5e18;
    UFixed32x9 swapMultiplier = defaultSwapMultiplier;
    UFixed32x9 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 10e18;
    uint128 virtualReserveOut = 10e18;

    LiquidationPair liquidationPair = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      swapMultiplier,
      liquidityFraction,
      virtualReserveIn,
      virtualReserveOut,
      defaultMinK
    );

    mockAvailableBalanceOf(source, tokenOut, amountOfYield);
    uint256 amountOut = liquidationPair.computeExactAmountOut(1);

    swapExactAmountOut(alice, amountOut, amountOfYield, liquidationPair);
  }

  function testSwapExactAmountOut_MinReserveOut() public {
    uint256 amountOut = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x9 swapMultiplier = UFixed32x9.wrap(0.3e9);
    UFixed32x9 liquidityFraction = UFixed32x9.wrap(0.02e9);
    uint128 virtualReserveIn = 100e18;
    uint128 virtualReserveOut = 1;

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
        defaultMinK
      )
    );
  }

  function testSwapExactAmountOut_MinReserveIn() public {
    uint256 amountOut = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x9 swapMultiplier = defaultSwapMultiplier;
    UFixed32x9 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 1;
    uint128 virtualReserveOut = 100e18;

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
        defaultMinK
      )
    );
  }

  function testSwapExactAmountOut_MinReserves() public {
    uint256 amountOut = 1e18;
    uint256 amountOfYield = 10e18;
    UFixed32x9 swapMultiplier = defaultSwapMultiplier;
    UFixed32x9 liquidityFraction = defaultLiquidityFraction;
    uint128 virtualReserveIn = 1;
    uint128 virtualReserveOut = 1;

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
        1
      )
    );
  }

  function testSwapExactAmountOut_Properties() public {
    uint256 amountOfYield1 = 100;
    uint256 amountOfYield2 = 1000;
    uint256 amountOfYield3 = 10000;
    uint256 wantedAmountIn = 20;
    uint256[] memory exactAmountsOut = new uint256[](3);

    mockAvailableBalanceOf(source, tokenOut, amountOfYield1);
    exactAmountsOut[0] = defaultLiquidationPair.computeExactAmountOut(wantedAmountIn);
    vm.clearMockedCalls();
    mockAvailableBalanceOf(source, tokenOut, amountOfYield2);
    exactAmountsOut[1] = defaultLiquidationPair.computeExactAmountOut(wantedAmountIn);
    vm.clearMockedCalls();
    mockAvailableBalanceOf(source, tokenOut, amountOfYield3);
    exactAmountsOut[2] = defaultLiquidationPair.computeExactAmountOut(wantedAmountIn);

    assertLe(exactAmountsOut[0], exactAmountsOut[1]);
    assertLe(exactAmountsOut[1], exactAmountsOut[2]);
  }

  function testSwapExactAmountOut_MinimumValues() public {
    LiquidationPair liquidationPair = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      UFixed32x9.wrap(0),
      UFixed32x9.wrap(1),
      1,
      1,
      1
    );

    uint256 amountOfYield = 10;
    mockAvailableBalanceOf(source, tokenOut, amountOfYield);

    uint256 wantedAmountOut = 1;
    uint256 amountInMax = liquidationPair.computeExactAmountIn(wantedAmountOut);
    mockLiquidateGivenAmountOut(liquidationPair, alice, wantedAmountOut, true);

    vm.startPrank(alice);

    vm.expectEmit(true, true, true, true);

    emit Swapped(alice, amountInMax, wantedAmountOut);
    uint256 swappedAmountIn = liquidationPair.swapExactAmountOut(
      alice,
      wantedAmountOut,
      amountInMax
    );

    assertLe(swappedAmountIn, amountInMax);
    assertGe(liquidationPair.virtualReserveIn(), swappedAmountIn);
    assertGe(liquidationPair.virtualReserveOut(), amountOfYield);

    vm.stopPrank();
  }

  function testCannotSwapExactAmountOut_MaxNotGuaranteed() public {
    uint256 amountOfYield = 100;
    mockAvailableBalanceOf(source, tokenOut, amountOfYield);

    uint256 amountOut = amountOfYield / 10;
    uint256 amountInMax = defaultLiquidationPair.computeExactAmountIn(amountOut);

    mockLiquidateGivenAmountOut(defaultLiquidationPair, alice, amountOut, true);

    vm.startPrank(alice);

    vm.expectRevert(bytes("LiquidationPair/max-not-guaranteed"));
    defaultLiquidationPair.swapExactAmountOut(alice, amountOut, 0);

    vm.stopPrank();
  }

  // function testSeriesOfSwaps(uint128 amountOfYield) public {
  //   vm.startPrank(alice);
  //   vm.assume(amountOfYield / 10 > 0);
  //   vm.assume(amountOfYield < type(uint112).max);
  //   mockSource.accrueYield(address(tokenOut), amountOfYield);

  //   uint256 amountOut = amountOfYield / 10;
  //   uint256 amountIn = liquidationPair.computeExactAmountIn(amountOut);

  //   // MockERC20(tokenIn).approve(address(liquidationRouter), type(uint256).max);
  //   MockERC20(tokenIn).mint(alice, 100);

  //   vm.expectEmit(true, false, false, true);
  //   emit Swapped(alice, amountIn, amountOut);

  //   uint256 swappedAmountIn = liquidationPair.swapExactAmountOut(
  //     alice,
  //     amountOut,
  //     type(uint256).max
  //   );

  //   assertGe(liquidationPair.virtualReserveIn(), amountIn);
  //   assertGe(liquidationPair.virtualReserveOut(), amountOfYield);

  //   assertEq(MockERC20(tokenOut).balanceOf(alice), amountOut);
  //   assertEq(MockERC20(tokenIn).balanceOf(alice), 100 - swappedAmountIn);
  //   assertEq(liquidationPair.maxAmountOut(), amountOfYield - amountOut);
  //   assertEq(MockERC20(tokenIn).balanceOf(defaultTarget), swappedAmountIn);

  //   uint256 swappedAmountOut = liquidationPair.swapExactAmountIn(alice, swappedAmountIn, 0);

  //   assertEq(MockERC20(tokenOut).balanceOf(alice), amountOut + swappedAmountOut);
  //   assertEq(MockERC20(tokenIn).balanceOf(alice), 100 - swappedAmountIn - swappedAmountIn);
  //   assertEq(liquidationPair.maxAmountOut(), amountOfYield - amountOut - swappedAmountOut);
  //   assertEq(MockERC20(tokenIn).balanceOf(defaultTarget), swappedAmountIn + swappedAmountIn);

  //   assertGe(liquidationPair.virtualReserveIn(), amountIn);
  //   assertGe(liquidationPair.virtualReserveOut(), amountOfYield);
  //   vm.stopPrank();
  // }

  /* ============ swapMultiplier ============ */

  function testSwapMultiplier_Properties() public {
    vm.startPrank(alice);

    uint256 amountOut = 100;
    uint256 amountOfYield = 100e18;
    uint128 virtualReserveIn = 1000e18;
    uint128 virtualReserveOut = 1000e18;

    mockAvailableBalanceOf(source, tokenOut, amountOfYield);

    LiquidationPair liquidationPair1 = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      UFixed32x9.wrap(0),
      UFixed32x9.wrap(1),
      virtualReserveIn,
      virtualReserveOut,
      defaultMinK
    );

    mockLiquidateGivenAmountOut(liquidationPair1, alice, amountOut, true);
    uint256 amountIn1 = liquidationPair1.swapExactAmountOut(alice, amountOut, type(uint256).max);

    LiquidationPair liquidationPair2 = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      UFixed32x9.wrap(1e5),
      UFixed32x9.wrap(1),
      virtualReserveIn,
      virtualReserveOut,
      defaultMinK
    );

    mockLiquidateGivenAmountOut(liquidationPair2, alice, amountOut, true);
    uint256 amountIn2 = liquidationPair2.swapExactAmountOut(alice, amountOut, type(uint256).max);

    LiquidationPair liquidationPair3 = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      UFixed32x9.wrap(1e9),
      UFixed32x9.wrap(1),
      virtualReserveIn,
      virtualReserveOut,
      defaultMinK
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

    uint256 amountOut = 1e18; // AO is higher than other test case.
    uint256 amountOfYield = 100e18;
    uint128 virtualReserveIn = 1000e18;
    uint128 virtualReserveOut = 1000e18;

    mockAvailableBalanceOf(source, tokenOut, amountOfYield);

    LiquidationPair liquidationPair1 = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      UFixed32x9.wrap(0),
      UFixed32x9.wrap(1),
      virtualReserveIn,
      virtualReserveOut,
      defaultMinK
    );

    mockLiquidateGivenAmountOut(liquidationPair1, alice, amountOut, true);
    uint256 amountIn1 = liquidationPair1.swapExactAmountOut(alice, amountOut, type(uint256).max);

    LiquidationPair liquidationPair2 = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      UFixed32x9.wrap(1e5),
      UFixed32x9.wrap(1),
      virtualReserveIn,
      virtualReserveOut,
      defaultMinK
    );

    mockLiquidateGivenAmountOut(liquidationPair2, alice, amountOut, true);
    uint256 amountIn2 = liquidationPair2.swapExactAmountOut(alice, amountOut, type(uint256).max);

    LiquidationPair liquidationPair3 = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      UFixed32x9.wrap(1e9),
      UFixed32x9.wrap(1),
      virtualReserveIn,
      virtualReserveOut,
      defaultMinK
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
    mockAvailableBalanceOf(source, tokenOut, 1000);

    vm.startPrank(alice);

    LiquidationPair liquidationPair1 = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      UFixed32x9.wrap(0),
      UFixed32x9.wrap(1),
      1000,
      1000,
      defaultMinK
    );
    uint256 amountOut = 10;

    mockLiquidateGivenAmountOut(liquidationPair1, alice, amountOut, true);
    uint256 amountIn1 = liquidationPair1.swapExactAmountOut(alice, amountOut, type(uint256).max);

    LiquidationPair liquidationPair2 = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      UFixed32x9.wrap(0),
      UFixed32x9.wrap(1e5),
      1000,
      1000,
      defaultMinK
    );

    mockLiquidateGivenAmountOut(liquidationPair2, alice, amountOut, true);
    uint256 amountIn2 = liquidationPair2.swapExactAmountOut(alice, amountOut, type(uint256).max);

    LiquidationPair liquidationPair3 = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      UFixed32x9.wrap(0),
      UFixed32x9.wrap(1e9),
      1000,
      1000,
      defaultMinK
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

// Assume tokenOut is WBTC, tokenIn is USDC
// Initial reserve ratio is ~ 1:25000
contract LiquidationPairBitcoinScenarioTest is LiquidationPairTestSetup {
  /* ============ Variables ============ */

  UFixed32x9 public defaultSwapMultiplier;
  UFixed32x9 public defaultLiquidityFraction;
  uint128 public defaultVirtualReserveIn;
  uint128 public defaultVirtualReserveOut;
  uint256 public defaultMinK;

  LiquidationPair public defaultLiquidationPair;

  /* ============ Set up ============ */

  function setUp() public virtual override {
    super.setUp();
    defaultSwapMultiplier = UFixed32x9.wrap(0.3e9);
    defaultLiquidityFraction = UFixed32x9.wrap(0.02e9);
    defaultVirtualReserveIn = 1198574999999999899456; // 1e18
    defaultVirtualReserveOut = 4794300; //1e8
    defaultMinK = 5746328122499999517961900800;

    defaultLiquidationPair = new LiquidationPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      defaultSwapMultiplier,
      defaultLiquidityFraction,
      defaultVirtualReserveIn,
      defaultVirtualReserveOut,
      defaultMinK
    );
  }

  /* ============ External Functions ============ */

  /* ============ maxAmountOut ============ */

  /* ============ nextLiquidationState ============ */

  /* ============ computeExactAmountIn ============ */

  function testComputeExactAmountIn_HappyPath() public {
    mockAvailableBalanceOf(source, tokenOut, 1e8);
    uint256 amountIn = defaultLiquidationPair.computeExactAmountIn(1e6); // 1% of yield
    assertEq(amountIn, 528298351814435099);
  }

  /* ============ computeExactAmountOut ============ */

  function testComputeExactAmountOut_HappyPath() public {
    mockAvailableBalanceOf(source, tokenOut, 1e8);
    uint256 amountOut = defaultLiquidationPair.computeExactAmountOut(25000e16);
    assertEq(amountOut, 85943642);
  }

  /* ============ computeExactAmount ============ */

  function testComputeExactAmount_Fuzz(uint256 amountOfYield) public {
    // Semi-realistic range of yield
    vm.assume(amountOfYield > 100);
    vm.assume(amountOfYield < 100000e8);
    mockAvailableBalanceOf(source, tokenOut, amountOfYield);
    uint256 _amountOut = amountOfYield / 100; // 1% of yield
    uint256 amountIn = defaultLiquidationPair.computeExactAmountIn(_amountOut);
    uint256 amountOut = defaultLiquidationPair.computeExactAmountOut(amountIn);
    assertEq(_amountOut, amountOut);
  }

  /* ============ swapExactAmountIn ============ */

  function testSwapExactAmountIn_AllYieldOut(uint112 amountOfYield) public {
    vm.assume(amountOfYield > 0);
    vm.assume(amountOfYield < 100000e8);
    mockAvailableBalanceOf(source, tokenOut, amountOfYield);
    uint256 amountIn = defaultLiquidationPair.computeExactAmountIn(amountOfYield);
    mockLiquidateGivenAmountIn(defaultLiquidationPair, alice, amountIn, true);
    vm.prank(alice);
    defaultLiquidationPair.swapExactAmountIn(alice, amountIn, 0);
  }

  /* ============ swapExactAmountOut ============ */

  function testSwapExactAmountOut_AllYieldOut(uint112 amountOfYield) public {
    vm.assume(amountOfYield > 0);
    vm.assume(amountOfYield < 100000e8);
    mockAvailableBalanceOf(source, tokenOut, amountOfYield);
    uint256 amountOut = amountOfYield;
    mockLiquidateGivenAmountOut(defaultLiquidationPair, alice, amountOut, true);
    vm.prank(alice);
    defaultLiquidationPair.swapExactAmountOut(alice, amountOut, type(uint112).max);
  }

  /* ============ swapMultiplier ============ */

  /* ============ liquidityFraction ============ */
}
