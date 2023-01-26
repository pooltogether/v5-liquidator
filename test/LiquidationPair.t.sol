// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {LiquidationPairFactory} from "../src/LiquidationPairFactory.sol";
import {LiquidationPair} from "../src/LiquidationPair.sol";
import {ILiquidationSource} from "../src/interfaces/ILiquidationSource.sol";
import {LiquidatorLib} from "../src/libraries/LiquidatorLib.sol";
import {UFixed32x9} from "../src/libraries/FixedMathLib.sol";
import {BaseSetup} from "./utils/BaseSetup.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockLiquidationPairYieldSource} from "./mocks/MockLiquidationPairYieldSource.sol";

abstract contract LiquidationPairBaseSetup is BaseSetup {
    address defaultTarget;
    UFixed32x9 defaultSwapMultiplier;
    UFixed32x9 defaultLiquidityFraction;
    uint128 defaultVirtualReserveIn;
    uint128 defaultVirtualReserveOut;
    LiquidationPair public liquidationPair;
    LiquidationPairFactory public factory;
    MockERC20 public tokenIn;
    MockERC20 public tokenOut;
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
        factory = new LiquidationPairFactory();
        tokenIn = new MockERC20("tokenIn", "IN", 18);
        tokenOut = new MockERC20("tokenOut", "OUT", 18);
        liquidationPairYieldSource = new MockLiquidationPairYieldSource();
        liquidationPair = factory.createPair(
            address(this),
            liquidationPairYieldSource,
            defaultTarget,
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
        tokenIn.mint(alice, exactAmountIn);
        tokenIn.approve(address(liquidationPair), exactAmountIn);
        vm.expectEmit(true, false, false, true);
        emit Swapped(alice, exactAmountIn, amountOutMin);
        uint256 swappedAmountOut = liquidationPair.swapExactAmountIn(exactAmountIn, amountOutMin);

        vm.stopPrank();

        assertGe(swappedAmountOut, amountOutMin);
        assertEq(tokenOut.balanceOf(alice), swappedAmountOut);
        assertEq(tokenIn.balanceOf(alice), 0);
        assertEq(tokenIn.balanceOf(defaultTarget), exactAmountIn);
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
        LiquidationPair lp = factory.createPair(
            alice,
            liquidationPairYieldSource,
            defaultTarget,
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
        tokenIn.mint(alice, exactAmountIn);
        tokenIn.approve(address(lp), exactAmountIn);
        vm.expectEmit(true, false, false, true);
        emit Swapped(alice, exactAmountIn, amountOutMin);
        uint256 swappedAmountOut = lp.swapExactAmountIn(exactAmountIn, amountOutMin);

        vm.stopPrank();

        assertGe(swappedAmountOut, amountOutMin);
        assertEq(tokenOut.balanceOf(alice), swappedAmountOut);
        assertEq(tokenIn.balanceOf(alice), 0);
        assertEq(tokenIn.balanceOf(defaultTarget), exactAmountIn);
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
        tokenIn.mint(alice, amountInMax);
        tokenIn.approve(address(liquidationPair), amountInMax);
        vm.expectEmit(true, false, false, true);
        emit Swapped(alice, amountInMax, amountOut);
        uint256 swappedAmountIn = liquidationPair.swapExactAmountOut(amountOut, amountInMax);
        vm.stopPrank();

        assertLe(swappedAmountIn, amountInMax);
        assertEq(tokenOut.balanceOf(alice), amountOut);
        assertEq(tokenIn.balanceOf(alice), amountInMax - swappedAmountIn);
        assertEq(tokenIn.balanceOf(defaultTarget), swappedAmountIn);
        assertEq(liquidationPair.maxAmountOut(), amountOfYield - amountOut);
        assertGe(liquidationPair.virtualReserveIn(), amountInMax);
        assertGe(liquidationPair.virtualReserveOut(), amountOfYield);
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
        LiquidationPair lp = factory.createPair(
            alice,
            liquidationPairYieldSource,
            defaultTarget,
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
        tokenIn.mint(alice, amountInMax);
        tokenIn.approve(address(lp), amountInMax);
        vm.expectEmit(true, true, true, true);
        emit Swapped(alice, amountInMax, wantedAmountOut);
        uint256 swappedAmountIn = lp.swapExactAmountOut(wantedAmountOut, amountInMax);

        vm.stopPrank();

        assertLe(swappedAmountIn, amountInMax);
        assertEq(tokenOut.balanceOf(alice), wantedAmountOut);
        assertEq(tokenIn.balanceOf(alice), amountInMax - swappedAmountIn);
        assertEq(tokenIn.balanceOf(defaultTarget), swappedAmountIn);
        assertEq(liquidationPair.maxAmountOut(), amountOfYield - wantedAmountOut);
        assertGe(liquidationPair.virtualReserveIn(), swappedAmountIn);
        assertGe(liquidationPair.virtualReserveOut(), amountOfYield);
    }

    function testSwapPercentageOfYield(uint128 amountOfYield, uint8 percentage) public {
        vm.assume(amountOfYield < type(uint112).max);
        vm.assume(percentage > 0);
        vm.assume(percentage <= 100);

        // Note: swap multiplier of 0
        liquidationPair = factory.createPair(
            alice,
            liquidationPairYieldSource,
            defaultTarget,
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
        tokenIn.mint(alice, amountInMax);
        tokenIn.approve(address(liquidationPair), amountInMax);
        uint256 swappedAmountIn = liquidationPair.swapExactAmountOut(amountOut, amountInMax);
        vm.stopPrank();

        assertLe(swappedAmountIn, amountInMax);
        assertEq(tokenOut.balanceOf(alice), amountOut);
        assertEq(tokenIn.balanceOf(alice), amountInMax - swappedAmountIn);
        assertEq(tokenIn.balanceOf(defaultTarget), swappedAmountIn);
        assertEq(liquidationPair.maxAmountOut(), amountOfYield - amountOut);
    }

    function testCannotSwapExactAmountIn() public {
        uint256 amountOfYield = 100;
        liquidationPairYieldSource.accrueYield(address(tokenOut), amountOfYield);

        uint256 amountOut = amountOfYield / 10;
        uint256 amountIn = liquidationPair.computeExactAmountIn(amountOut);

        vm.startPrank(alice);
        tokenOut.mint(alice, amountIn);
        tokenOut.approve(address(liquidationPair), amountIn);

        vm.expectRevert(bytes("LiquidationPair/min-not-guaranteed"));
        liquidationPair.swapExactAmountIn(amountIn, type(uint256).max);
        vm.stopPrank();
    }

    function testCannotSwapExactAmountOut() public {
        uint256 amountOfYield = 100;
        liquidationPairYieldSource.accrueYield(address(tokenOut), amountOfYield);

        uint256 amountOut = amountOfYield / 10;
        uint256 amountInMax = liquidationPair.computeExactAmountIn(amountOut);

        vm.startPrank(alice);
        tokenOut.mint(alice, amountInMax);
        tokenOut.approve(address(liquidationPair), amountInMax);

        vm.expectRevert(bytes("LiquidationPair/max-not-guaranteed"));
        liquidationPair.swapExactAmountOut(amountOut, 0);
        vm.stopPrank();
    }

    function testSeriesOfSwaps(uint128 amountOfYield) public {
        vm.startPrank(alice);
        vm.assume(amountOfYield / 10 > 0);
        vm.assume(amountOfYield < type(uint112).max);
        liquidationPairYieldSource.accrueYield(address(tokenOut), amountOfYield);

        uint256 amountOut = amountOfYield / 10;
        uint256 amountIn = liquidationPair.computeExactAmountIn(amountOut);

        tokenIn.approve(address(liquidationPair), type(uint256).max);
        tokenIn.mint(alice, 100);

        vm.expectEmit(true, false, false, true);
        emit Swapped(alice, amountIn, amountOut);

        uint256 swappedAmountIn = liquidationPair.swapExactAmountOut(amountOut, type(uint256).max);

        assertGe(liquidationPair.virtualReserveIn(), amountIn);
        assertGe(liquidationPair.virtualReserveOut(), amountOfYield);

        assertEq(tokenOut.balanceOf(alice), amountOut);
        assertEq(tokenIn.balanceOf(alice), 100 - swappedAmountIn);
        assertEq(liquidationPair.maxAmountOut(), amountOfYield - amountOut);
        assertEq(tokenIn.balanceOf(defaultTarget), swappedAmountIn);

        uint256 swappedAmountOut = liquidationPair.swapExactAmountIn(swappedAmountIn, 0);

        assertEq(tokenOut.balanceOf(alice), amountOut + swappedAmountOut);
        assertEq(tokenIn.balanceOf(alice), 100 - swappedAmountIn - swappedAmountIn);
        assertEq(liquidationPair.maxAmountOut(), amountOfYield - amountOut - swappedAmountOut);
        assertEq(tokenIn.balanceOf(defaultTarget), swappedAmountIn + swappedAmountIn);

        assertGe(liquidationPair.virtualReserveIn(), amountIn);
        assertGe(liquidationPair.virtualReserveOut(), amountOfYield);
        vm.stopPrank();
    }

    function testSwapMultiplierProperties() public {
        LiquidationPair lp1 = factory.createPair(
            alice,
            liquidationPairYieldSource,
            defaultTarget,
            tokenIn,
            tokenOut,
            UFixed32x9.wrap(0),
            UFixed32x9.wrap(1),
            1000,
            1000
        );
        LiquidationPair lp2 = factory.createPair(
            alice,
            liquidationPairYieldSource,
            defaultTarget,
            tokenIn,
            tokenOut,
            UFixed32x9.wrap(5e5),
            UFixed32x9.wrap(1),
            1000,
            1000
        );
        LiquidationPair lp3 = factory.createPair(
            alice,
            liquidationPairYieldSource,
            defaultTarget,
            tokenIn,
            tokenOut,
            UFixed32x9.wrap(1e9),
            UFixed32x9.wrap(1),
            1000,
            1000
        );

        liquidationPairYieldSource.accrueYield(address(tokenOut), 1000);

        vm.startPrank(alice);
        tokenIn.approve(address(lp1), type(uint256).max);
        tokenIn.approve(address(lp2), type(uint256).max);
        tokenIn.approve(address(lp3), type(uint256).max);
        tokenIn.mint(alice, 1000);

        uint256 amountOut = 10;
        uint256 amountIn1 = lp1.swapExactAmountOut(amountOut, type(uint256).max);
        uint256 amountIn2 = lp2.swapExactAmountOut(amountOut, type(uint256).max);
        uint256 amountIn3 = lp3.swapExactAmountOut(amountOut, type(uint256).max);

        assertEq(amountIn1, amountIn2);
        assertEq(amountIn2, amountIn3);
        assertGe(lp2.virtualReserveIn(), lp1.virtualReserveIn());
        assertGe(lp3.virtualReserveIn(), lp2.virtualReserveIn());
        assertLe(lp2.virtualReserveOut(), lp1.virtualReserveOut());
        assertLe(lp3.virtualReserveOut(), lp2.virtualReserveOut());

        vm.stopPrank();
    }

    function testLiquidityFractionProperties() public {
        LiquidationPair lp1 = factory.createPair(
            alice,
            liquidationPairYieldSource,
            defaultTarget,
            tokenIn,
            tokenOut,
            UFixed32x9.wrap(0),
            UFixed32x9.wrap(1),
            1000,
            1000
        );
        LiquidationPair lp2 = factory.createPair(
            alice,
            liquidationPairYieldSource,
            defaultTarget,
            tokenIn,
            tokenOut,
            UFixed32x9.wrap(0),
            UFixed32x9.wrap(1e7),
            1000,
            1000
        );
        LiquidationPair lp3 = factory.createPair(
            alice,
            liquidationPairYieldSource,
            defaultTarget,
            tokenIn,
            tokenOut,
            UFixed32x9.wrap(0),
            UFixed32x9.wrap(1e9),
            1000,
            1000
        );

        liquidationPairYieldSource.accrueYield(address(tokenOut), 1000);

        vm.startPrank(alice);
        tokenIn.approve(address(lp1), type(uint256).max);
        tokenIn.approve(address(lp2), type(uint256).max);
        tokenIn.approve(address(lp3), type(uint256).max);
        tokenIn.mint(alice, 1000);

        uint256 amountIn1 = lp1.swapExactAmountOut(10, type(uint256).max);
        uint256 amountIn2 = lp2.swapExactAmountOut(10, type(uint256).max);
        uint256 amountIn3 = lp3.swapExactAmountOut(10, type(uint256).max);

        assertEq(amountIn1, amountIn2);
        assertEq(amountIn2, amountIn3);
        assertGe(lp1.virtualReserveIn(), lp2.virtualReserveIn());
        assertGe(lp2.virtualReserveIn(), lp3.virtualReserveIn());
        assertGe(lp1.virtualReserveOut(), lp2.virtualReserveOut());
        assertGe(lp2.virtualReserveOut(), lp3.virtualReserveOut());

        vm.stopPrank();
    }
}
