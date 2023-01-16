// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {LiquidationPairFactory} from "../src/LiquidationPairFactory.sol";
import {LiquidationPair} from "../src/LiquidationPair.sol";
import {ILiquidationPairYieldSource} from "../src/interfaces/ILiquidationPairYieldSource.sol";
import {LiquidatorLib} from "../src/libraries/LiquidatorLib.sol";
import {BaseSetup} from "./utils/BaseSetup.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockLiquidationPairYieldSource} from "./mocks/MockLiquidationPairYieldSource.sol";

abstract contract LiquidationPairBaseSetup is BaseSetup {
    address defaultTarget;
    uint32 defaultSwapMultiplier;
    uint32 defaultLiquidityFraction;
    uint256 defaultVirtualReserveIn;
    uint256 defaultVirtualReserveOut;
    LiquidationPair public liquidationPair;
    LiquidationPairFactory public factory;
    MockERC20 public tokenIn;
    MockERC20 public tokenOut;
    MockLiquidationPairYieldSource public liquidationPairYieldSource;

    event Swapped(
        ILiquidationPairYieldSource indexed prizePool,
        address target,
        IERC20 tokenIn,
        IERC20 indexed tokenOut,
        address indexed account,
        uint256 amountIn,
        uint256 amountOut
    );

    function initializeContracts(
        address _target,
        uint32 _swapMultiplier,
        uint32 _liquidityFraction,
        uint256 _virtualReserveIn,
        uint256 _virtualReserveOut
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
        initializeContracts(0x27fcf06DcFFdDB6Ec5F62D466987e863ec6aE6A0, 0.3e9, 0.02e9, 100, 50);
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

    function testGetLiquidationConfig() public {
        (IERC20 _tokenIn, IERC20 _tokenOut, uint32 _swapMultiplier, uint32 _liquidityFraction) =
            liquidationPair.getLiquidationConfig();
        assertEq(address(_tokenOut), address(tokenOut));
        assertEq(address(_tokenIn), address(tokenIn));
        assertEq(_swapMultiplier, defaultSwapMultiplier);
        assertEq(_liquidityFraction, defaultLiquidityFraction);
    }

    function testGetLiquidationState() public {
        (uint256 virtualReserveIn, uint256 virtualReserveOut) = liquidationPair.getLiquidationState();
        assertEq(virtualReserveIn, defaultVirtualReserveIn);
        assertEq(virtualReserveOut, defaultVirtualReserveOut);
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
        vm.expectEmit(true, true, true, true);
        emit Swapped(liquidationPairYieldSource, defaultTarget, tokenIn, tokenOut, alice, exactAmountIn, amountOutMin);
        uint256 swappedAmountOut = liquidationPair.swapExactAmountIn(exactAmountIn, amountOutMin);

        vm.stopPrank();

        assertGe(swappedAmountOut, amountOutMin);
        assertEq(tokenOut.balanceOf(alice), swappedAmountOut);
        assertEq(tokenIn.balanceOf(alice), 0);
        assertEq(tokenIn.balanceOf(defaultTarget), exactAmountIn);
        assertEq(liquidationPair.maxAmountOut(), amountOfYield - amountOutMin);
        (uint256 virtualReserveIn, uint256 virtualReserveOut) = liquidationPair.getLiquidationState();
        assertGe(virtualReserveIn, exactAmountIn);
        assertGe(virtualReserveOut, amountOfYield);
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

        console.log(exactAmountsIn[0], exactAmountsIn[1], exactAmountsIn[2]);
        assertGt(exactAmountsIn[0], exactAmountsIn[1]);
        assertGt(exactAmountsIn[1], exactAmountsIn[2]);
    }

    function testSwapExactAmountInMinimumValues() public {
        LiquidationPair lp =
            factory.createPair(alice, liquidationPairYieldSource, defaultTarget, tokenIn, tokenOut, 0, 1, 1, 1);
        uint256 amountOfYield = 1;
        liquidationPairYieldSource.accrueYield(address(tokenOut), amountOfYield);

        uint256 wantedAmountOut = 1;
        uint256 exactAmountIn = lp.computeExactAmountIn(wantedAmountOut);
        uint256 amountOutMin = lp.computeExactAmountOut(exactAmountIn);

        vm.startPrank(alice);
        tokenIn.mint(alice, exactAmountIn);
        tokenIn.approve(address(lp), exactAmountIn);
        vm.expectEmit(true, true, true, true);
        emit Swapped(liquidationPairYieldSource, defaultTarget, tokenIn, tokenOut, alice, exactAmountIn, amountOutMin);
        uint256 swappedAmountOut = lp.swapExactAmountIn(exactAmountIn, amountOutMin);

        vm.stopPrank();

        assertGe(swappedAmountOut, amountOutMin);
        assertEq(tokenOut.balanceOf(alice), swappedAmountOut);
        assertEq(tokenIn.balanceOf(alice), 0);
        assertEq(tokenIn.balanceOf(defaultTarget), exactAmountIn);
        assertEq(lp.maxAmountOut(), amountOfYield - amountOutMin);
        (uint256 virtualReserveIn, uint256 virtualReserveOut) = liquidationPair.getLiquidationState();
        assertGe(virtualReserveIn, exactAmountIn);
        assertGe(virtualReserveOut, amountOfYield);
    }

    function testSwapExactAmountOut(uint256 amountOut) public {
        vm.assume(amountOut > 0);
        vm.assume(amountOut <= type(uint128).max); // NOTE: Hardcoded boundary
        uint256 amountOfYield = amountOut * 2;
        liquidationPairYieldSource.accrueYield(address(tokenOut), amountOfYield);

        uint256 amountInMax = liquidationPair.computeExactAmountIn(amountOut);

        vm.startPrank(alice);
        tokenIn.mint(alice, amountInMax);
        tokenIn.approve(address(liquidationPair), amountInMax);
        emit Swapped(liquidationPairYieldSource, defaultTarget, tokenIn, tokenOut, alice, amountInMax, amountOut);
        uint256 swappedAmountIn = liquidationPair.swapExactAmountOut(amountOut, amountInMax);
        vm.stopPrank();

        assertLe(swappedAmountIn, amountInMax);
        assertEq(tokenOut.balanceOf(alice), amountOut);
        assertEq(tokenIn.balanceOf(alice), amountInMax - swappedAmountIn);
        assertEq(tokenIn.balanceOf(defaultTarget), swappedAmountIn);
        assertEq(liquidationPair.maxAmountOut(), amountOfYield - amountOut);
        (uint256 virtualReserveIn, uint256 virtualReserveOut) = liquidationPair.getLiquidationState();
        assertGe(virtualReserveIn, amountInMax);
        assertGe(virtualReserveOut, amountOfYield);
    }

    function testSwapExactAmountOutProperties() public {
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

    function testSwapExactAmountOutMinimumValues() public {
        LiquidationPair lp =
            factory.createPair(alice, liquidationPairYieldSource, defaultTarget, tokenIn, tokenOut, 0, 1, 1, 1);
        uint256 amountOfYield = 10;
        liquidationPairYieldSource.accrueYield(address(tokenOut), amountOfYield);

        uint256 wantedAmountOut = 1;
        uint256 amountInMax = lp.computeExactAmountIn(wantedAmountOut);

        vm.startPrank(alice);
        tokenIn.mint(alice, amountInMax);
        tokenIn.approve(address(lp), amountInMax);
        vm.expectEmit(true, true, true, true);
        emit Swapped(liquidationPairYieldSource, defaultTarget, tokenIn, tokenOut, alice, amountInMax, wantedAmountOut);
        uint256 swappedAmountIn = lp.swapExactAmountOut(wantedAmountOut, amountInMax);

        vm.stopPrank();

        assertLe(swappedAmountIn, amountInMax);
        assertEq(tokenOut.balanceOf(alice), wantedAmountOut);
        assertEq(tokenIn.balanceOf(alice), amountInMax - swappedAmountIn);
        assertEq(tokenIn.balanceOf(defaultTarget), swappedAmountIn);
        assertEq(liquidationPair.maxAmountOut(), amountOfYield - wantedAmountOut);
        (uint256 virtualReserveIn, uint256 virtualReserveOut) = liquidationPair.getLiquidationState();
        assertGe(virtualReserveIn, swappedAmountIn);
        assertGe(virtualReserveOut, amountOfYield);
    }

    function testSwapPercentageOfYield(uint256 amountOfYield, uint8 percentage) public {
        vm.assume(amountOfYield > 0);
        vm.assume(amountOfYield <= type(uint128).max); // NOTE: Hardcoded boundary
        vm.assume(percentage > 0);
        vm.assume(percentage <= 100);

        // NOTE: swap multiplier of 0
        liquidationPair = factory.createPair(
            alice,
            liquidationPairYieldSource,
            defaultTarget,
            tokenIn,
            tokenOut,
            0,
            type(uint32).max,
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

        vm.expectRevert(bytes("trade does not meet min"));
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

        vm.expectRevert(bytes("trade does not meet max"));
        liquidationPair.swapExactAmountOut(amountOut, 0);
        vm.stopPrank();
    }

    function testSeriesOfSwaps(uint256 amountOfYield) public {
        vm.startPrank(alice);
        vm.assume(amountOfYield / 10 > 0);
        vm.assume(amountOfYield < type(uint112).max);
        liquidationPairYieldSource.accrueYield(address(tokenOut), amountOfYield);

        uint256 amountOut = amountOfYield / 10;
        uint256 amountIn = liquidationPair.computeExactAmountIn(amountOut);

        tokenIn.approve(address(liquidationPair), type(uint256).max);
        tokenIn.mint(alice, 100);

        vm.expectEmit(true, true, true, true);
        emit Swapped(liquidationPairYieldSource, defaultTarget, tokenIn, tokenOut, alice, amountIn, amountOut);

        uint256 swappedAmountIn = liquidationPair.swapExactAmountOut(amountOut, type(uint256).max);

        (uint256 virtualReserveIn, uint256 virtualReserveOut) = liquidationPair.getLiquidationState();
        assertGe(virtualReserveIn, amountIn);
        assertGe(virtualReserveOut, amountOfYield);

        assertEq(tokenOut.balanceOf(alice), amountOut);
        assertEq(tokenIn.balanceOf(alice), 100 - swappedAmountIn);
        assertEq(liquidationPair.maxAmountOut(), amountOfYield - amountOut);
        assertEq(tokenIn.balanceOf(defaultTarget), swappedAmountIn);

        uint256 swappedAmountOut = liquidationPair.swapExactAmountIn(swappedAmountIn, 0);

        assertEq(tokenOut.balanceOf(alice), amountOut + swappedAmountOut);
        assertEq(tokenIn.balanceOf(alice), 100 - swappedAmountIn - swappedAmountIn);
        assertEq(liquidationPair.maxAmountOut(), amountOfYield - amountOut - swappedAmountOut);
        assertEq(tokenIn.balanceOf(defaultTarget), swappedAmountIn + swappedAmountIn);

        (virtualReserveIn, virtualReserveOut) = liquidationPair.getLiquidationState();
        assertGe(virtualReserveIn, amountIn);
        assertGe(virtualReserveOut, amountOfYield);
        vm.stopPrank();
    }

    function testSwapMultiplierProperties() public {
        LiquidationPair lp1 =
            factory.createPair(alice, liquidationPairYieldSource, defaultTarget, tokenIn, tokenOut, 0, 1, 1000, 1000);
        LiquidationPair lp2 =
            factory.createPair(alice, liquidationPairYieldSource, defaultTarget, tokenIn, tokenOut, 1e9, 1, 1000, 1000);
        LiquidationPair lp3 = factory.createPair(
            alice, liquidationPairYieldSource, defaultTarget, tokenIn, tokenOut, type(uint32).max, 1, 1000, 1000
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

        (uint256 virtualReserveIn1, uint256 virtualReserveOut1) = lp1.getLiquidationState();
        (uint256 virtualReserveIn2, uint256 virtualReserveOut2) = lp2.getLiquidationState();
        (uint256 virtualReserveIn3, uint256 virtualReserveOut3) = lp3.getLiquidationState();

        assertEq(amountIn1, amountIn2);
        assertEq(amountIn2, amountIn3);
        assertGe(virtualReserveIn2, virtualReserveIn1);
        assertGe(virtualReserveIn3, virtualReserveIn2);
        assertLe(virtualReserveOut2, virtualReserveOut1);
        assertLe(virtualReserveOut3, virtualReserveOut2);

        vm.stopPrank();
    }

    function testLiquidityFractionProperties() public {
        LiquidationPair lp1 =
            factory.createPair(alice, liquidationPairYieldSource, defaultTarget, tokenIn, tokenOut, 0, 1, 1000, 1000);
        LiquidationPair lp2 =
            factory.createPair(alice, liquidationPairYieldSource, defaultTarget, tokenIn, tokenOut, 0, 1e9, 1000, 1000);
        LiquidationPair lp3 = factory.createPair(
            alice, liquidationPairYieldSource, defaultTarget, tokenIn, tokenOut, 0, type(uint32).max, 1000, 1000
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

        (uint256 virtualReserveIn1, uint256 virtualReserveOut1) = lp1.getLiquidationState();
        (uint256 virtualReserveIn2, uint256 virtualReserveOut2) = lp2.getLiquidationState();
        (uint256 virtualReserveIn3, uint256 virtualReserveOut3) = lp3.getLiquidationState();

        assertEq(amountIn1, amountIn2);
        assertEq(amountIn2, amountIn3);
        assertGe(virtualReserveIn1, virtualReserveIn2);
        assertGe(virtualReserveIn2, virtualReserveIn3);
        assertGe(virtualReserveOut1, virtualReserveOut2);
        assertGe(virtualReserveOut2, virtualReserveOut3);

        vm.stopPrank();
    }
}
