// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "src/libraries/LiquidatorLib.sol";
import { UFixed32x4, FixedMathLib } from "src/libraries/FixedMathLib.sol";

import { Math } from "openzeppelin/utils/math/Math.sol";

// Note: Need to store the results from the library in a variable to be picked up by forge coverage
// See: https://github.com/foundry-rs/foundry/pull/3128#issuecomment-1241245086

contract MockLiquidatorLib {
  function computeExactAmountIn(
    uint128 _reserveA,
    uint128 _reserveB,
    uint256 _amountInB,
    uint256 _amountOutB,
    UFixed32x4 _maxPriceImpact
  ) public pure returns (uint256) {
    uint256 amountIn = LiquidatorLib.computeExactAmountIn(
      _reserveA,
      _reserveB,
      _amountInB,
      _amountOutB,
      _maxPriceImpact
    );
    return amountIn;
  }

  function computeExactAmountOut(
    uint128 _reserveA,
    uint128 _reserveB,
    uint256 _amountInB,
    uint256 _amountInA,
    UFixed32x4 _maxPriceImpact
  ) public pure returns (uint256) {
    uint256 amountOut = LiquidatorLib.computeExactAmountOut(
      _reserveA,
      _reserveB,
      _amountInB,
      _amountInA,
      _maxPriceImpact
    );
    return amountOut;
  }

  function virtualBuyback(
    uint128 _reserveA,
    uint128 _reserveB,
    uint256 _amountInB,
    UFixed32x4 _maxPriceImpact
  ) public pure returns (uint128, uint128, uint256, uint256) {
    (uint128 reserveA, uint128 reserveB, uint256 amountInB, uint256 amountOutA) = LiquidatorLib
      ._virtualBuyback(_reserveA, _reserveB, _amountInB, _maxPriceImpact);
    return (reserveA, reserveB, amountInB, amountOutA);
  }

  function virtualSwap(
    uint128 _reserveA,
    uint128 _reserveB,
    uint256 _amountInB,
    uint256 _amountOutB,
    UFixed32x4 _swapMultiplier,
    UFixed32x4 _liquidityFraction,
    uint128 _minK
  ) public pure returns (uint128, uint128) {
    (uint128 reserveA, uint128 reserveB) = LiquidatorLib._virtualSwap(
      _reserveA,
      _reserveB,
      _amountInB,
      _amountOutB,
      _swapMultiplier,
      _liquidityFraction,
      _minK
    );
    return (reserveA, reserveB);
  }

  function applyLiquidityFraction(
    uint128 _reserveA,
    uint128 _reserveB,
    uint256 _amountInB,
    UFixed32x4 _liquidityFraction,
    uint256 _mink
  ) public pure returns (uint256, uint256) {
    (uint128 reserveA, uint128 reserveB) = LiquidatorLib._applyLiquidityFraction(
      _reserveA,
      _reserveB,
      _amountInB,
      _liquidityFraction,
      _mink
    );
    return (reserveA, reserveB);
  }

  function swapExactAmountIn(
    uint128 _reserveA,
    uint128 _reserveB,
    uint256 _amountInB,
    uint256 _amountInA,
    UFixed32x4 _swapMultiplier,
    UFixed32x4 _liquidityFraction,
    uint128 _minK,
    UFixed32x4 _maxPriceImpact
  ) public pure returns (uint256, uint256, uint256) {
    (uint256 reserveA, uint256 reserveB, uint256 amountOut) = LiquidatorLib.swapExactAmountIn(
      _reserveA,
      _reserveB,
      _amountInB,
      _amountInA,
      _swapMultiplier,
      _liquidityFraction,
      _minK,
      _maxPriceImpact
    );
    return (reserveA, reserveB, amountOut);
  }

  function swapExactAmountOut(
    uint128 _reserveA,
    uint128 _reserveB,
    uint256 _amountInB,
    uint256 _amountOutB,
    UFixed32x4 _swapMultiplier,
    UFixed32x4 _liquidityFraction,
    uint128 _minK,
    UFixed32x4 _maxPriceImpact
  ) public pure returns (uint256, uint256, uint256) {
    (uint256 reserveA, uint256 reserveB, uint256 amountIn) = LiquidatorLib.swapExactAmountOut(
      _reserveA,
      _reserveB,
      _amountInB,
      _amountOutB,
      _swapMultiplier,
      _liquidityFraction,
      _minK,
      _maxPriceImpact
    );
    return (reserveA, reserveB, amountIn);
  }

  function getAmountOut(
    uint256 amountInA,
    uint128 virtualReserveA,
    uint128 virtualReserveB
  ) public pure returns (uint256) {
    uint256 amountOut = LiquidatorLib.getAmountOut(amountInA, virtualReserveA, virtualReserveB);
    return amountOut;
  }

  function getAmountIn(
    uint256 amountOutB,
    uint128 virtualReserveA,
    uint128 virtualReserveB
  ) public pure returns (uint256) {
    uint256 amountIn = LiquidatorLib.getAmountIn(amountOutB, virtualReserveA, virtualReserveB);
    return amountIn;
  }

  function getVirtualBuybackAmounts(
    uint256 amountInA,
    uint128 virtualReserveA,
    uint128 virtualReserveB,
    UFixed32x4 maxPriceImpactA
  ) public pure returns (uint256, uint256) {
    (uint256 amountOut0, uint256 amountIn1) = LiquidatorLib.getVirtualBuybackAmounts(
      amountInA,
      virtualReserveA,
      virtualReserveB,
      maxPriceImpactA
    );
    return (amountOut0, amountIn1);
  }

  function calculateRestrictedAmounts(
    uint128 virtualReserveA,
    uint128 virtualReserveB,
    UFixed32x4 maxPriceImpactA
  ) public pure returns (uint256, uint256) {
    (uint256 amountIn1, uint256 amountOut0) = LiquidatorLib.calculateRestrictedAmounts(
      virtualReserveA,
      virtualReserveB,
      maxPriceImpactA
    );
    return (amountIn1, amountOut0);
  }

  function calculateRestrictedAmountsInverted(
    uint128 virtualReserveA,
    uint128 virtualReserveB,
    UFixed32x4 maxPriceImpactA
  ) public pure returns (uint256, uint256) {
    (uint256 amountIn1, uint256 amountOut0) = LiquidatorLib.calculateRestrictedAmountsInverted(
      virtualReserveA,
      virtualReserveB,
      maxPriceImpactA
    );
    return (amountIn1, amountOut0);
  }

  function calculateVirtualSwapPriceImpact(
    uint256 amountIn1,
    uint128 reserve1,
    uint128 reserve0
  ) public pure returns (UFixed32x4) {
    (UFixed32x4 priceImpact, ) = LiquidatorLib.calculateVirtualSwapPriceImpact(
      amountIn1,
      reserve1,
      reserve0
    );
    return priceImpact;
  }

  function calculateMaxAmountOut(
    uint256 amountIn1,
    uint128 reserve1,
    uint128 reserve0,
    UFixed32x4 maxPriceImpact1
  ) public pure returns (uint256) {
    (UFixed32x4 priceImpact1, ) = LiquidatorLib.calculateVirtualSwapPriceImpact(
      amountIn1,
      reserve1,
      reserve0
    );
    if (UFixed32x4.unwrap(priceImpact1) > UFixed32x4.unwrap(maxPriceImpact1)) {
      (uint256 maxAmountIn1, ) = LiquidatorLib.calculateRestrictedAmounts(
        reserve1,
        reserve0,
        maxPriceImpact1
      );
      return maxAmountIn1;
    }

    return amountIn1;
  }

  function calculateMaxAmountIn(
    uint256 _amountIn1,
    uint128 reserve1,
    uint128 reserve0,
    UFixed32x4 maxPriceImpact1
  ) public pure returns (uint256) {
    (, uint256 amountIn1) = LiquidatorLib.getVirtualBuybackAmounts(
      _amountIn1,
      reserve1,
      reserve0,
      maxPriceImpact1
    );

    return
      LiquidatorLib.computeExactAmountIn(reserve0, reserve1, amountIn1, amountIn1, maxPriceImpact1);
  }
}
