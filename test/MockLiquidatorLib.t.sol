// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {BaseSetup} from "./utils/BaseSetup.sol";
import {MockLiquidatorLib} from "./mocks/MockLiquidatorLib.sol";

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
        vm.expectRevert(bytes("CpmmLib/INSUFF_PAIR_LIQ"));
        mockLiquidatorLib.getAmountOut(100, 0, 100);
        vm.expectRevert(bytes("CpmmLib/INSUFF_PAIR_LIQ"));
        mockLiquidatorLib.getAmountOut(100, 100, 0);
    }

    function testGetAmountOutFuzz(uint256 amountIn, uint256 reserve1, uint256 reserve0) public {
        getAmountOutAssumptions(amountIn, reserve1, reserve0);
        mockLiquidatorLib.getAmountOut(amountIn, reserve1, reserve0);
    }

    function testFailGetAmountOutOverflow() public {
        mockLiquidatorLib.getAmountOut(type(uint256).max, type(uint256).max, type(uint256).max);
    }

    function testGetAmountInHappyPath() public {
        uint256 amountOut = mockLiquidatorLib.getAmountIn(5, 10, 10);
        assertEq(amountOut, 10);
    }

    function testCannotGetAmountIn() public {
        vm.expectRevert(bytes("CpmmLib/INSUFF_LIQ"));
        mockLiquidatorLib.getAmountIn(1000, 10, 100);
        vm.expectRevert(bytes("CpmmLib/INSUFF_PAIR_LIQ"));
        mockLiquidatorLib.getAmountIn(10, 0, 100);
    }

    function testGetAmountInFuzz(uint256 amountOut, uint256 reserve1, uint256 reserve0) public view {
        getAmountInAssumptions(amountOut, reserve1, reserve0);
        mockLiquidatorLib.getAmountIn(amountOut, reserve1, reserve0);
    }

    function testFailGetAmountInOverflow() public {
        mockLiquidatorLib.getAmountIn(type(uint256).max - 1, type(uint256).max, type(uint256).max);
    }

    function testVirtualBuybackHappyPath() public {
        (uint256 reserveA, uint256 reserveB) = mockLiquidatorLib.virtualBuyback(10, 10, 10);
        assertEq(reserveA, 5);
        assertEq(reserveB, 20);
    }

    function testCannotVirtualBuybackRequire() public {
        vm.expectRevert(bytes("CpmmLib/INSUFF_PAIR_LIQ"));
        mockLiquidatorLib.virtualBuyback(10, 0, 10);
        vm.expectRevert(bytes("CpmmLib/INSUFF_PAIR_LIQ"));
        mockLiquidatorLib.virtualBuyback(0, 10, 10);
    }

    function testPerpareSwapFuzz(uint256 reserve0, uint256 reserve1, uint256 amountIn1) public {
        virtualBuybackAssumptions(reserve0, reserve1, amountIn1);
        mockLiquidatorLib.virtualBuyback(reserve0, reserve1, amountIn1);
    }

    function testComputeExactAmountInHappyPath() public {
        uint256 amountOut = mockLiquidatorLib.computeExactAmountIn(10, 10, 10, 10);
        uint256 expectedAmountOut = 5;
        assertEq(amountOut, expectedAmountOut);
    }

    function testCannotComputeExactAmountInRequire() public {
        vm.expectRevert(bytes("insuff balance"));
        mockLiquidatorLib.computeExactAmountIn(10, 10, 10, 100);
    }

    function testComputeExactAmountInFuzz(uint256 _reserve0, uint256 _reserve1, uint256 _amountIn1, uint256 _amountOut1)
        public
    {
        computeExactAmountInAssumptions(_reserve0, _reserve1, _amountIn1, _amountOut1);
        mockLiquidatorLib.computeExactAmountIn(_reserve0, _reserve1, _amountIn1, _amountOut1);
    }

    function testComputeExactAmountOutHappyPath() public {
        uint256 amountOut = mockLiquidatorLib.computeExactAmountOut(10, 10, 10, 5);
        uint256 expectedAmountOut = 10;
        assertEq(amountOut, expectedAmountOut);
    }

    function testCannotComputeExactAmountOut() public {
        vm.expectRevert(bytes("insuff balance"));
        mockLiquidatorLib.computeExactAmountOut(10, 10, 0, 100);
    }

    function testComputeExactAmountOutFuzz(uint256 _reserve0, uint256 _reserve1, uint256 _amountIn1, uint256 _amountIn0)
        public
    {
        computeExactAmountOutAssumptions(_reserve0, _reserve1, _amountIn1, _amountIn0);
        mockLiquidatorLib.computeExactAmountOut(_reserve0, _reserve1, _amountIn1, _amountIn0);
    }

    function testVirtualSwapHappyPath() public {
        (uint256 reserveA, uint256 reserveB) = mockLiquidatorLib.virtualSwap(10, 10, 10, 10, 0.1e9, 0.01e9);
        assertEq(reserveA, 1222);
        assertEq(reserveB, 999);
    }

    function testVirtualSwapFuzz(
        uint256 _reserve0,
        uint256 _reserve1,
        uint256 _availableReserve1,
        uint256 _reserve1Out,
        uint32 _swapMultiplier,
        uint32 _liquidityFraction
    ) public {
        vm.assume(_availableReserve1 < type(uint112).max);
        vm.assume(_reserve1Out < type(uint112).max);
        vm.assume(_reserve1Out > 0); // Asserts tokens are being given out - Should we allow 0 to be swapped out?
        vm.assume(_liquidityFraction > 0);

        uint256 extraVirtualReserveOut1 = (_reserve1Out * _swapMultiplier) / 1e9;
        vm.assume(extraVirtualReserveOut1 < type(uint256).max - _reserve1);
        getAmountInAssumptions(extraVirtualReserveOut1, _reserve0, _reserve1);
        uint256 extraVirtualReserveIn0 = mockLiquidatorLib.getAmountIn(extraVirtualReserveOut1, _reserve0, _reserve1);
        vm.assume(_reserve0 + extraVirtualReserveIn0 < type(uint256).max);
        uint256 reserve0 = _reserve0 + extraVirtualReserveIn0;
        uint256 reserve1 = _reserve1 - extraVirtualReserveOut1;

        vm.assume((_availableReserve1 * 1e9) < type(uint256).max);
        uint256 reserveFraction = (_availableReserve1 * 1e9) / reserve1;
        vm.assume((reserveFraction * 1e9) < type(uint256).max);
        uint256 multiplier = (reserveFraction * 1e9) / uint256(_liquidityFraction);
        vm.assume((reserve0 * multiplier) < type(uint256).max);
        vm.assume((reserve1 * multiplier) < type(uint256).max);

        mockLiquidatorLib.virtualSwap(
            _reserve0, _reserve1, _availableReserve1, _reserve1Out, _swapMultiplier, _liquidityFraction
        );
    }

    function testSwapExactAmountInHappyPath() public {
        (uint256 reserveA, uint256 reserveB, uint256 amountOut) =
            mockLiquidatorLib.swapExactAmountIn(10, 10, 100, 5, 0.1e9, 0.01e9);
        assertEq(reserveA, 11000);
        assertEq(reserveB, 10000);
        assertEq(amountOut, 91);
    }

    function testCannotSwapExactAmountInRequire() public {
        vm.expectRevert(bytes("LiqLib/insuff-liq"));
        mockLiquidatorLib.swapExactAmountIn(10, 10, 10, 10, 0.1e9, 0.01e9);
    }

    function testSwapExactAmountOutHappyPath() public {
        (uint256 reserveA, uint256 reserveB, uint256 amountIn) =
            mockLiquidatorLib.swapExactAmountOut(10, 10, 100, 91, 0.1e9, 0.01e9);
        assertEq(reserveA, 9000);
        assertEq(reserveB, 10000);
        assertEq(amountIn, 4);
    }

    function testCannotSwapExactAmountOutRequire() public {
        vm.expectRevert(bytes("LiqLib/insuff-liq"));
        mockLiquidatorLib.swapExactAmountOut(10, 10, 10, 100, 0.1e9, 0.01e9);
    }

    // Assumptions for restriction fuzz tests

    function getAmountOutAssumptions(uint256 amountIn, uint256 reserve1, uint256 reserve0) public pure {
        vm.assume(reserve0 > 0);
        vm.assume(reserve1 > 0);
        vm.assume(amountIn < type(uint128).max);
        vm.assume(reserve0 < type(uint128).max);
        vm.assume(reserve1 < type(uint128).max);
        vm.assume(amountIn * reserve0 < type(uint256).max);
        vm.assume(amountIn + reserve1 < type(uint256).max);
    }

    function getAmountInAssumptions(uint256 amountOut, uint256 reserve1, uint256 reserve0) public pure {
        uint256 maxSafeValue = type(uint128).max;
        vm.assume(reserve0 > 0);
        vm.assume(reserve1 > 0);
        vm.assume(amountOut < maxSafeValue);
        vm.assume(reserve0 < maxSafeValue);
        vm.assume(reserve1 < maxSafeValue);
        vm.assume(amountOut < reserve0);
        vm.assume(amountOut * reserve1 < type(uint256).max);
        vm.assume(reserve0 - amountOut > 0);
    }

    function virtualBuybackAssumptions(uint256 reserve0, uint256 reserve1, uint256 amountIn1) public view {
        getAmountOutAssumptions(amountIn1, reserve1, reserve0);
        uint256 amountOut0 = mockLiquidatorLib.getAmountOut(amountIn1, reserve1, reserve0);
        vm.assume(reserve0 - amountOut0 > 0);
        vm.assume(reserve1 + amountIn1 < type(uint256).max);
    }

    function computeExactAmountInAssumptions(
        uint256 _reserve0,
        uint256 _reserve1,
        uint256 _amountIn1,
        uint256 _amountOut1
    ) public view {
        vm.assume(_amountOut1 <= _amountIn1);
        virtualBuybackAssumptions(_reserve0, _reserve1, _amountIn1);
        (uint256 reserve0, uint256 reserve1) = mockLiquidatorLib.virtualBuyback(_reserve0, _reserve1, _amountIn1);
        getAmountInAssumptions(_amountIn1, reserve0, reserve1);
        mockLiquidatorLib.getAmountIn(_amountOut1, reserve0, reserve1);
    }

    function computeExactAmountOutAssumptions(
        uint256 _reserve0,
        uint256 _reserve1,
        uint256 _amountIn1,
        uint256 _amountIn0
    ) public view {
        virtualBuybackAssumptions(_reserve0, _reserve1, _amountIn1);
        (uint256 reserve0, uint256 reserve1) = mockLiquidatorLib.virtualBuyback(_reserve0, _reserve1, _amountIn1);
        getAmountOutAssumptions(_amountIn0, reserve0, reserve1);
        uint256 amountOut1 = mockLiquidatorLib.getAmountOut(_amountIn0, reserve0, reserve1);
        vm.assume(amountOut1 <= _amountIn1);
    }
}
