// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {LiquidationPairFactory} from "src/LiquidationPairFactory.sol";
import {LiquidationPair} from "src/LiquidationPair.sol";
import {LiquidationRouter} from "src/LiquidationRouter.sol";

import {ILiquidationSource} from "src/interfaces/ILiquidationSource.sol";

import {LiquidatorLib} from "src/libraries/LiquidatorLib.sol";
import {UFixed32x9} from "src/libraries/FixedMathLib.sol";

import {BaseSetup} from "./utils/BaseSetup.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockLiquidationPairFactory} from "./mocks/MockLiquidationPairFactory.sol";
import {MockLiquidationPairYieldSource} from "./mocks/MockLiquidationPairYieldSource.sol";

abstract contract LiquidationPairBaseSetup is BaseSetup {
    address defaultTarget;

    UFixed32x9 defaultSwapMultiplier;
    UFixed32x9 defaultLiquidityFraction;
    uint128 defaultVirtualReserveIn;
    uint128 defaultVirtualReserveOut;

    LiquidationRouter public liquidationRouter;
    LiquidationPair public liquidationPair;

    address public tokenIn;
    address public tokenOut;

    MockLiquidationPairFactory public factory;
    MockLiquidationPairYieldSource public liquidationPairYieldSource;

    event Swapped(address indexed account, uint256 amountIn, uint256 amountOut);

    function initializeContracts(
        address _target,
        UFixed32x9 _swapMultiplier,
        UFixed32x9 _liquidityFraction,
        uint128 _virtualReserveIn,
        uint128 _virtualReserveOut
    ) public {
        defaultTarget = _target;
        defaultSwapMultiplier = _swapMultiplier;
        defaultLiquidityFraction = _liquidityFraction;
        defaultVirtualReserveIn = _virtualReserveIn;
        defaultVirtualReserveOut = _virtualReserveOut;


        tokenIn = address(new MockERC20("tokenIn", "IN", 18));
        tokenOut = address(new MockERC20("tokenOut", "OUT", 18));

        liquidationPairYieldSource = new MockLiquidationPairYieldSource(_target);

        factory = new MockLiquidationPairFactory();

        liquidationRouter = new LiquidationRouter(factory);

        liquidationPair = factory.createPair(
            liquidationPairYieldSource,
            tokenIn,
            tokenOut,
            defaultSwapMultiplier,
            defaultLiquidityFraction,
            defaultVirtualReserveIn,
            defaultVirtualReserveOut
        );
    }
}

contract LiquidationPairUnitTest is LiquidationPairBaseSetup {
    function setUp() public virtual override {
        super.setUp();
        initializeContracts(
            0x27fcf06DcFFdDB6Ec5F62D466987e863ec6aE6A0, UFixed32x9.wrap(0.3e9), UFixed32x9.wrap(0.02e9), 100, 50
        );
    }

    function testMaxAmountOut() public {
        uint256 amountOut = liquidationPair.maxAmountOut();
        assertEq(amountOut, 0);
        liquidationPairYieldSource.accrueYield(address(tokenOut), 100);
        amountOut = liquidationPair.maxAmountOut();
        assertEq(amountOut, 100);
    }

    function testNextLiquidationState() public {
        (uint256 virtualReserveIn, uint256 virtualReserveOut) = liquidationPair.nextLiquidationState();
        assertEq(virtualReserveIn, defaultVirtualReserveIn);
        assertEq(virtualReserveOut, defaultVirtualReserveOut);
        liquidationPairYieldSource.accrueYield(address(tokenOut), defaultVirtualReserveOut);
        (virtualReserveIn, virtualReserveOut) = liquidationPair.nextLiquidationState();
        assertEq(virtualReserveIn, defaultVirtualReserveIn / 2);
        assertEq(virtualReserveOut, 2 * defaultVirtualReserveOut);
    }

    function testComputeExactAmountIn() public {
        liquidationPairYieldSource.accrueYield(address(tokenOut), 10);
        uint256 amountIn = liquidationPair.computeExactAmountIn(5);
        uint256 expectedAmountIn = 7;
        assertEq(amountIn, expectedAmountIn);
    }

    function testComputeExactAmountOut() public {
        liquidationPairYieldSource.accrueYield(address(tokenOut), 10);
        uint256 amountOut = liquidationPair.computeExactAmountOut(5);
        uint256 expectedAmountOut = 3;
        assertEq(amountOut, expectedAmountOut);
    }

    function testSwapExactAmountIn(uint256 amountOfYield) public {
        vm.assume(amountOfYield / 100 > 0);
        vm.assume(amountOfYield < type(uint112).max);
        liquidationPairYieldSource.accrueYield(address(tokenOut), amountOfYield);

        uint256 wantedAmountOut = amountOfYield / 10;
        uint256 exactAmountIn = liquidationPair.computeExactAmountIn(wantedAmountOut);
        uint256 amountOutMin = liquidationPair.computeExactAmountOut(exactAmountIn);

        vm.startPrank(alice);

        MockERC20(tokenIn).mint(alice, exactAmountIn);
        MockERC20(tokenIn).approve(address(liquidationRouter), exactAmountIn);

        vm.expectEmit(true, false, false, true);
        emit Swapped(alice, exactAmountIn, amountOutMin);

        uint256 swappedAmountOut = liquidationRouter.swapExactAmountIn(
            [tokenIn, tokenOut],
            alice,
            exactAmountIn,
            amountOutMin
        );

        vm.stopPrank();

        assertGe(swappedAmountOut, amountOutMin);
        assertEq(MockERC20(tokenOut).balanceOf(alice), swappedAmountOut);
        assertEq(MockERC20(tokenIn).balanceOf(alice), 0);
        assertEq(MockERC20(tokenIn).balanceOf(defaultTarget), exactAmountIn);
        assertEq(liquidationPair.maxAmountOut(), amountOfYield - amountOutMin);
        assertGe(liquidationPair.virtualReserveIn(), exactAmountIn);
        assertGe(liquidationPair.virtualReserveOut(), amountOfYield);
    }

    function testSwapExactAmountInProperties() public {
        uint256 amountOfYield = 100;
        uint256 wantedAmountOut = 50;
        uint256[] memory exactAmountsIn = new uint256[](3);

        liquidationPairYieldSource.accrueYield(address(tokenOut), amountOfYield);
        exactAmountsIn[0] = liquidationPair.computeExactAmountIn(wantedAmountOut);
        liquidationPairYieldSource.accrueYield(address(tokenOut), amountOfYield);
        exactAmountsIn[1] = liquidationPair.computeExactAmountIn(wantedAmountOut);
        liquidationPairYieldSource.accrueYield(address(tokenOut), amountOfYield);
        exactAmountsIn[2] = liquidationPair.computeExactAmountIn(wantedAmountOut);

        assertGt(exactAmountsIn[0], exactAmountsIn[1]);
        assertGt(exactAmountsIn[1], exactAmountsIn[2]);
    }

    function testSwapExactAmountInMinimumValues() public {
        factory.deletePair(tokenIn, tokenOut);

        LiquidationPair lp = factory.createPair(
            liquidationPairYieldSource,
            tokenIn,
            tokenOut,
            UFixed32x9.wrap(0),
            UFixed32x9.wrap(1),
            1,
            1
        );
        uint256 amountOfYield = 1;
        liquidationPairYieldSource.accrueYield(address(tokenOut), amountOfYield);

        uint256 wantedAmountOut = 1;
        uint256 exactAmountIn = lp.computeExactAmountIn(wantedAmountOut);
        uint256 amountOutMin = lp.computeExactAmountOut(exactAmountIn);

        vm.startPrank(alice);

        MockERC20(tokenIn).mint(alice, exactAmountIn);
        MockERC20(tokenIn).approve(address(liquidationRouter), exactAmountIn);

        vm.expectEmit(true, false, false, true);
        emit Swapped(alice, exactAmountIn, amountOutMin);

        uint256 swappedAmountOut = liquidationRouter.swapExactAmountIn(
            [tokenIn, tokenOut],
            alice,
            exactAmountIn,
            amountOutMin
        );

        vm.stopPrank();

        assertGe(swappedAmountOut, amountOutMin);
        assertEq(MockERC20(tokenOut).balanceOf(alice), swappedAmountOut);
        assertEq(MockERC20(tokenIn).balanceOf(alice), 0);
        assertEq(MockERC20(tokenIn).balanceOf(defaultTarget), exactAmountIn);
        assertEq(lp.maxAmountOut(), amountOfYield - amountOutMin);
        assertGe(liquidationPair.virtualReserveIn(), exactAmountIn);
        assertGe(liquidationPair.virtualReserveOut(), amountOfYield);
    }

    function testSwapExactAmountOut(uint256 amountOut) public {
        vm.assume(amountOut > 0);
        vm.assume(amountOut <= type(uint112).max);
        uint256 amountOfYield = amountOut * 2;
        liquidationPairYieldSource.accrueYield(address(tokenOut), amountOfYield);

        uint256 amountInMax = liquidationPair.computeExactAmountIn(amountOut);

        vm.startPrank(alice);

        MockERC20(tokenIn).mint(alice, amountInMax);
        MockERC20(tokenIn).approve(address(liquidationRouter), amountInMax);

        vm.expectEmit(true, false, false, true);
        emit Swapped(alice, amountInMax, amountOut);

        uint256 swappedAmountIn = liquidationRouter.swapExactAmountOut(
            [tokenIn, tokenOut],
            alice,
            amountOut,
            amountInMax
        );

        assertLe(swappedAmountIn, amountInMax);
        assertEq(MockERC20(tokenOut).balanceOf(alice), amountOut);
        assertEq(MockERC20(tokenIn).balanceOf(alice), amountInMax - swappedAmountIn);
        assertEq(MockERC20(tokenIn).balanceOf(defaultTarget), swappedAmountIn);
        assertEq(liquidationPair.maxAmountOut(), amountOfYield - amountOut);
        assertGe(liquidationPair.virtualReserveIn(), amountInMax);
        assertGe(liquidationPair.virtualReserveOut(), amountOfYield);

        vm.stopPrank();
    }

    function testPropertiesSwapExactAmountOut() public {
        uint256 amountOfYield = 100;
        uint256 wantedAmountIn = 20;
        uint256[] memory exactAmountsOut = new uint256[](3);

        liquidationPairYieldSource.accrueYield(address(tokenOut), amountOfYield);
        exactAmountsOut[0] = liquidationPair.computeExactAmountOut(wantedAmountIn);
        liquidationPairYieldSource.accrueYield(address(tokenOut), amountOfYield);
        exactAmountsOut[1] = liquidationPair.computeExactAmountOut(wantedAmountIn);
        liquidationPairYieldSource.accrueYield(address(tokenOut), amountOfYield);
        exactAmountsOut[2] = liquidationPair.computeExactAmountOut(wantedAmountIn);

        assertLt(exactAmountsOut[0], exactAmountsOut[1]);
        assertLt(exactAmountsOut[1], exactAmountsOut[2]);
    }

    function testMinimumValuesSwapExactAmountOut() public {
        factory.deletePair(tokenIn, tokenOut);

        LiquidationPair lp = factory.createPair(
            liquidationPairYieldSource,
            tokenIn,
            tokenOut,
            UFixed32x9.wrap(0),
            UFixed32x9.wrap(1),
            1,
            1
        );

        uint256 amountOfYield = 10;
        liquidationPairYieldSource.accrueYield(address(tokenOut), amountOfYield);

        uint256 wantedAmountOut = 1;
        uint256 amountInMax = lp.computeExactAmountIn(wantedAmountOut);

        vm.startPrank(alice);

        MockERC20(tokenIn).mint(alice, amountInMax);
        MockERC20(tokenIn).approve(address(liquidationRouter), amountInMax);

        vm.expectEmit(true, true, true, true);

        emit Swapped(alice, amountInMax, wantedAmountOut);
        uint256 swappedAmountIn = liquidationRouter.swapExactAmountOut(
            [tokenIn, tokenOut],
            alice,
            wantedAmountOut,
            amountInMax
        );

        assertLe(swappedAmountIn, amountInMax);
        assertEq(MockERC20(tokenOut).balanceOf(alice), wantedAmountOut);
        assertEq(MockERC20(tokenIn).balanceOf(alice), amountInMax - swappedAmountIn);
        assertEq(MockERC20(tokenIn).balanceOf(defaultTarget), swappedAmountIn);
        assertEq(liquidationPair.maxAmountOut(), amountOfYield - wantedAmountOut);
        assertGe(liquidationPair.virtualReserveIn(), swappedAmountIn);
        assertGe(liquidationPair.virtualReserveOut(), amountOfYield);

        vm.stopPrank();
    }

    function testSwapPercentageOfYield(uint128 amountOfYield, uint8 percentage) public {
        vm.assume(amountOfYield < type(uint112).max);
        vm.assume(percentage > 0);
        vm.assume(percentage <= 100);

        factory.deletePair(tokenIn, tokenOut);

        // Note: swap multiplier of 0
        liquidationPair = factory.createPair(
            liquidationPairYieldSource,
            tokenIn,
            tokenOut,
            UFixed32x9.wrap(0),
            UFixed32x9.wrap(1e9),
            amountOfYield,
            amountOfYield
        );

        liquidationPairYieldSource.accrueYield(address(tokenOut), amountOfYield);

        uint256 amountOut = amountOfYield * percentage / 100;
        vm.assume(amountOut > 0);
        uint256 amountInMax = liquidationPair.computeExactAmountIn(amountOut);

        vm.startPrank(alice);

        MockERC20(tokenIn).mint(alice, amountInMax);
        MockERC20(tokenIn).approve(address(liquidationRouter), amountInMax);

        uint256 swappedAmountIn = liquidationRouter.swapExactAmountOut(
            [tokenIn, tokenOut],
            alice,
            amountOut,
            amountInMax
        );

        assertLe(swappedAmountIn, amountInMax);
        assertEq(MockERC20(tokenOut).balanceOf(alice), amountOut);
        assertEq(MockERC20(tokenIn).balanceOf(alice), amountInMax - swappedAmountIn);
        assertEq(MockERC20(tokenIn).balanceOf(defaultTarget), swappedAmountIn);
        assertEq(liquidationPair.maxAmountOut(), amountOfYield - amountOut);

        vm.stopPrank();
    }

    function testCannotSwapExactAmountIn() public {
        uint256 amountOfYield = 100;
        liquidationPairYieldSource.accrueYield(address(tokenOut), amountOfYield);

        uint256 amountOut = amountOfYield / 10;
        uint256 amountIn = liquidationPair.computeExactAmountIn(amountOut);

        vm.startPrank(alice);

        MockERC20(tokenIn).mint(alice, amountIn);
        MockERC20(tokenIn).approve(address(liquidationRouter), amountIn);

        vm.expectRevert(bytes("LiquidationPair/min-not-guaranteed"));
        liquidationRouter.swapExactAmountIn(
            [tokenIn, tokenOut],
            alice,
            amountIn,
            type(uint256).max
        );

        vm.stopPrank();
    }

    function testCannotSwapExactAmountOut() public {
        uint256 amountOfYield = 100;
        liquidationPairYieldSource.accrueYield(address(tokenOut), amountOfYield);

        uint256 amountOut = amountOfYield / 10;
        uint256 amountInMax = liquidationPair.computeExactAmountIn(amountOut);

        vm.startPrank(alice);

        MockERC20(tokenIn).mint(alice, amountInMax);
        MockERC20(tokenIn).approve(address(liquidationRouter), amountInMax);

        vm.expectRevert(bytes("LiquidationPair/max-not-guaranteed"));
        liquidationRouter.swapExactAmountOut(
            [tokenIn, tokenOut],
            alice,
            amountOut,
            0
        );

        vm.stopPrank();
    }

    function testSeriesOfSwaps(uint128 amountOfYield) public {
        vm.startPrank(alice);
        vm.assume(amountOfYield / 10 > 0);
        vm.assume(amountOfYield < type(uint112).max);
        liquidationPairYieldSource.accrueYield(address(tokenOut), amountOfYield);

        uint256 amountOut = amountOfYield / 10;
        uint256 amountIn = liquidationPair.computeExactAmountIn(amountOut);

        MockERC20(tokenIn).approve(address(liquidationRouter), type(uint256).max);
        MockERC20(tokenIn).mint(alice, 100);

        vm.expectEmit(true, false, false, true);
        emit Swapped(alice, amountIn, amountOut);

        uint256 swappedAmountIn = liquidationRouter.swapExactAmountOut(
            [tokenIn, tokenOut],
            alice,
            amountOut,
            type(uint256).max
        );

        assertGe(liquidationPair.virtualReserveIn(), amountIn);
        assertGe(liquidationPair.virtualReserveOut(), amountOfYield);

        assertEq(MockERC20(tokenOut).balanceOf(alice), amountOut);
        assertEq(MockERC20(tokenIn).balanceOf(alice), 100 - swappedAmountIn);
        assertEq(liquidationPair.maxAmountOut(), amountOfYield - amountOut);
        assertEq(MockERC20(tokenIn).balanceOf(defaultTarget), swappedAmountIn);

        uint256 swappedAmountOut = liquidationRouter.swapExactAmountIn(
            [tokenIn, tokenOut],
            alice,
            swappedAmountIn,
            0
        );

        assertEq(MockERC20(tokenOut).balanceOf(alice), amountOut + swappedAmountOut);
        assertEq(MockERC20(tokenIn).balanceOf(alice), 100 - swappedAmountIn - swappedAmountIn);
        assertEq(liquidationPair.maxAmountOut(), amountOfYield - amountOut - swappedAmountOut);
        assertEq(MockERC20(tokenIn).balanceOf(defaultTarget), swappedAmountIn + swappedAmountIn);

        assertGe(liquidationPair.virtualReserveIn(), amountIn);
        assertGe(liquidationPair.virtualReserveOut(), amountOfYield);
        vm.stopPrank();
    }

    function testSwapMultiplierProperties() public {
        liquidationPairYieldSource.accrueYield(address(tokenOut), 1000);

        vm.startPrank(alice);

        MockERC20(tokenIn).approve(address(liquidationRouter), type(uint256).max);
        MockERC20(tokenIn).mint(alice, 1000);

        uint256 amountOut = 10;

        factory.deletePair(tokenIn, tokenOut);

        LiquidationPair lp1 = factory.createPair(
            liquidationPairYieldSource,
            tokenIn,
            tokenOut,
            UFixed32x9.wrap(0),
            UFixed32x9.wrap(1),
            1000,
            1000
        );

        uint256 amountIn1 = liquidationRouter.swapExactAmountOut(
            [tokenIn, tokenOut],
            alice,
            amountOut,
            type(uint256).max
        );

        factory.deletePair(tokenIn, tokenOut);

        LiquidationPair lp2 = factory.createPair(
            liquidationPairYieldSource,
            tokenIn,
            tokenOut,
            UFixed32x9.wrap(5e5),
            UFixed32x9.wrap(1),
            1000,
            1000
        );

        uint256 amountIn2 = liquidationRouter.swapExactAmountOut(
            [tokenIn, tokenOut],
            alice,
            amountOut,
            type(uint256).max
        );

        factory.deletePair(tokenIn, tokenOut);

        LiquidationPair lp3 = factory.createPair(
            liquidationPairYieldSource,
            tokenIn,
            tokenOut,
            UFixed32x9.wrap(1e9),
            UFixed32x9.wrap(1),
            1000,
            1000
        );

        uint256 amountIn3 = liquidationRouter.swapExactAmountOut(
            [tokenIn, tokenOut],
            alice,
            amountOut,
            type(uint256).max
        );

        assertEq(amountIn1, amountIn2);
        assertEq(amountIn2, amountIn3);
        assertGe(lp2.virtualReserveIn(), lp1.virtualReserveIn());
        assertGe(lp3.virtualReserveIn(), lp2.virtualReserveIn());
        assertLe(lp2.virtualReserveOut(), lp1.virtualReserveOut());
        assertLe(lp3.virtualReserveOut(), lp2.virtualReserveOut());

        vm.stopPrank();
    }

    function testLiquidityFractionProperties() public {
        liquidationPairYieldSource.accrueYield(address(tokenOut), 1000);

        vm.startPrank(alice);

        MockERC20(tokenIn).approve(address(liquidationRouter), type(uint256).max);
        MockERC20(tokenIn).mint(alice, 1000);

        factory.deletePair(tokenIn, tokenOut);

        LiquidationPair lp1 = factory.createPair(
            liquidationPairYieldSource,
            tokenIn,
            tokenOut,
            UFixed32x9.wrap(0),
            UFixed32x9.wrap(1),
            1000,
            1000
        );

        uint256 amountIn1 = liquidationRouter.swapExactAmountOut(
            [tokenIn, tokenOut],
            alice,
            10,
            type(uint256).max
        );

        factory.deletePair(tokenIn, tokenOut);

        LiquidationPair lp2 = factory.createPair(
            liquidationPairYieldSource,
            tokenIn,
            tokenOut,
            UFixed32x9.wrap(0),
            UFixed32x9.wrap(1e7),
            1000,
            1000
        );

        uint256 amountIn2 = liquidationRouter.swapExactAmountOut(
            [tokenIn, tokenOut],
            alice,
            10,
            type(uint256).max
        );

        factory.deletePair(tokenIn, tokenOut);

        LiquidationPair lp3 = factory.createPair(
            liquidationPairYieldSource,
            tokenIn,
            tokenOut,
            UFixed32x9.wrap(0),
            UFixed32x9.wrap(1e9),
            1000,
            1000
        );

        uint256 amountIn3 = liquidationRouter.swapExactAmountOut(
            [tokenIn, tokenOut],
            alice,
            10,
            type(uint256).max
        );

        assertEq(amountIn1, amountIn2);
        assertEq(amountIn2, amountIn3);
        assertGe(lp1.virtualReserveIn(), lp2.virtualReserveIn());
        assertGe(lp2.virtualReserveIn(), lp3.virtualReserveIn());
        assertGe(lp1.virtualReserveOut(), lp2.virtualReserveOut());
        assertGe(lp2.virtualReserveOut(), lp3.virtualReserveOut());

        vm.stopPrank();
    }
}
