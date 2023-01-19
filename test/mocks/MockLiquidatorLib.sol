// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import "../../src/libraries/LiquidatorLib.sol";

// NOTE: Need to store the results from the library in a variable to be picked up by forge coverage
// See: https://github.com/foundry-rs/foundry/pull/3128#issuecomment-1241245086

contract MockLiquidatorLib {
    function computeExactAmountIn(uint256 _reserveA, uint256 _reserveB, uint256 _availableReserveB, uint256 _amountOutB)
        public
        view
        returns (uint256)
    {
        uint256 amountIn = LiquidatorLib.computeExactAmountIn(_reserveA, _reserveB, _availableReserveB, _amountOutB);
        return amountIn;
    }

    function computeExactAmountOut(uint256 _reserveA, uint256 _reserveB, uint256 _availableReserveB, uint256 _amountInA)
        public
        view
        returns (uint256)
    {
        uint256 amountOut = LiquidatorLib.computeExactAmountOut(_reserveA, _reserveB, _availableReserveB, _amountInA);
        return amountOut;
    }

    function virtualBuyback(uint256 _reserveA, uint256 _reserveB, uint256 _availableReserveB)
        public
        view
        returns (uint256, uint256)
    {
        (uint256 reserveA, uint256 reserveB) = LiquidatorLib.virtualBuyback(_reserveA, _reserveB, _availableReserveB);
        return (reserveA, reserveB);
    }

    function virtualSwap(
        uint256 _reserveA,
        uint256 _reserveB,
        uint256 _availableReserveB,
        uint256 _reserveBOut,
        UFixed32x9 _swapMultiplier,
        UFixed32x9 _liquidityFraction
    ) public view returns (uint256, uint256) {
        (uint256 reserveA, uint256 reserveB) = LiquidatorLib._virtualSwap(
            _reserveA, _reserveB, _availableReserveB, _reserveBOut, _swapMultiplier, _liquidityFraction
        );
        return (reserveA, reserveB);
    }

    function swapExactAmountIn(
        uint256 _reserveA,
        uint256 _reserveB,
        uint256 _availableReserveB,
        uint256 _amountInA,
        UFixed32x9 _swapMultiplier,
        UFixed32x9 _liquidityFraction
    ) public view returns (uint256, uint256, uint256) {
        (uint256 reserveA, uint256 reserveB, uint256 amountOut) = LiquidatorLib.swapExactAmountIn(
            _reserveA, _reserveB, _availableReserveB, _amountInA, _swapMultiplier, _liquidityFraction
        );
        return (reserveA, reserveB, amountOut);
    }

    function swapExactAmountOut(
        uint256 _reserveA,
        uint256 _reserveB,
        uint256 _availableReserveB,
        uint256 _amountOutB,
        UFixed32x9 _swapMultiplier,
        UFixed32x9 _liquidityFraction
    ) public view returns (uint256, uint256, uint256) {
        (uint256 reserveA, uint256 reserveB, uint256 amountIn) = LiquidatorLib.swapExactAmountOut(
            _reserveA, _reserveB, _availableReserveB, _amountOutB, _swapMultiplier, _liquidityFraction
        );
        return (reserveA, reserveB, amountIn);
    }

    function getAmountOut(uint256 amountIn, uint256 virtualReserveIn, uint256 virtualReserveOut)
        public
        view
        returns (uint256)
    {
        uint256 amountOut = LiquidatorLib.getAmountOut(amountIn, virtualReserveIn, virtualReserveOut);
        return amountOut;
    }

    function getAmountIn(uint256 amountOut, uint256 virtualReserveIn, uint256 virtualReserveOut)
        public
        view
        returns (uint256)
    {
        uint256 amountIn = LiquidatorLib.getAmountIn(amountOut, virtualReserveIn, virtualReserveOut);
        return amountIn;
    }
}
