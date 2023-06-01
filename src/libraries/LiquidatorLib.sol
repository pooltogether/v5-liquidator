// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import { Math } from "openzeppelin/utils/math/Math.sol";

import { UFixed32x4, FixedMathLib } from "./FixedMathLib.sol";

/**
 * @title PoolTogether Liquidator Library
 * @author PoolTogether Inc. Team
 * @notice A library to perform swaps on a UniswapV2-like pair of tokens. Implements logic that
 *          manipulates the token reserve amounts on swap.
 * @dev Each swap consists of four steps:
 *       1. A virtual buyback of the tokens available from the ILiquidationSource. This ensures
 *          that the value of the tokens available from the ILiquidationSource decays as
 *          tokens accrue.
 *      2. The main swap of tokens the user requested.
 *      3. A virtual swap that is a small multiplier applied to the users swap. This is to
 *          push the value of the tokens being swapped back up towards the market value.
 *      4. A scaling of the virtual reserves. This is to ensure that the virtual reserves
 *          are large enough such that the next swap will have a tailored impact on the virtual
 *          reserves.
 * @dev Numbered suffixes are used to identify the underlying token used for the parameter.
 *      For example, `amountIn1` and `reserve1` are the same token where `amountIn0` is different.
 */
library LiquidatorLib {
  /**
   * @notice Computes the amount of tokens that will be received for a given amount of tokens sent.
   * @param amountIn1 The amount of token 1 being sent in
   * @param reserve1 The amount of token 1 in the reserves
   * @param reserve0 The amount of token 0 in the reserves
   * @return amountOut0 The amount of token 0 that will be received given the amount in of token 1
   */
  function getAmountOut(
    uint256 amountIn1,
    uint128 reserve1,
    uint128 reserve0
  ) internal pure returns (uint256 amountOut0) {
    require(reserve0 > 0 && reserve1 > 0, "LiquidatorLib/insufficient-reserve-liquidity-a");
    uint256 numerator = amountIn1 * reserve0;
    uint256 denominator = amountIn1 + reserve1;
    amountOut0 = numerator / denominator;
    return amountOut0;
  }

  /**
   * @notice Computes the amount of tokens that will be received for a given amount of tokens sent.
   * @param _amountIn1 The amount of token 1 being sent in
   * @param _reserve1 The amount of token 1 in the reserves
   * @param _reserve0 The amount of token 0 in the reserves
   * @param _maxPriceImpact1 The maximum price impact that the amount of token 1 coming in should incur on the reserves
   * @return amountOut0 The amount of token 0 that will be received given the amount in of token 1
   * @return amountIn1 The amount of token 1 that will be sent given the max price impact
   */
  function getVirtualBuybackAmounts(
    uint256 _amountIn1,
    uint128 _reserve1,
    uint128 _reserve0,
    UFixed32x4 _maxPriceImpact1
  ) internal pure returns (uint256 amountOut0, uint256 amountIn1) {
    require(_reserve0 > 0 && _reserve1 > 0, "LiquidatorLib/insufficient-reserve-liquidity-a");

    UFixed32x4 priceImpact1;
    (priceImpact1, amountOut0) = calculateVirtualSwapPriceImpact(_amountIn1, _reserve1, _reserve0);

    if (UFixed32x4.unwrap(priceImpact1) > UFixed32x4.unwrap(_maxPriceImpact1)) {
      (amountIn1, amountOut0) = calculateRestrictedAmounts(_reserve1, _reserve0, _maxPriceImpact1);
    } else {
      amountIn1 = _amountIn1;
    }
  }

  /**
   * @notice Computes the amount of tokens required to be sent in to receive a given amount of
   *          tokens.
   * @param amountOut0 The amount of token 0 to receive
   * @param reserve1 The amount of token 1 in the reserves
   * @param reserve0 The amount of token 0 in the reserves
   * @return amountIn1 The amount of token 1 needed to receive the given amount out of token 0
   */
  function getAmountIn(
    uint256 amountOut0,
    uint128 reserve1,
    uint128 reserve0
  ) internal pure returns (uint256 amountIn1) {
    require(amountOut0 < reserve0, "LiquidatorLib/insufficient-reserve-liquidity-c");
    require(reserve0 > 0 && reserve1 > 0, "LiquidatorLib/insufficient-reserve-liquidity-d");
    uint256 numerator = amountOut0 * reserve1;
    uint256 denominator = uint256(reserve0) - amountOut0;
    amountIn1 = (numerator / denominator) + 1;
  }

  /**
   * @notice Performs a swap of all of the available tokens from the ILiquidationSource which
   *          impacts the virtual reserves resulting in price decay as tokens accrue.
   * @param _reserve0 The amount of token 0 in the reserve
   * @param _reserve1 The amount of token 1 in the reserve
   * @param _amountIn1 The amount of token 1 to buy back
   * @return reserve0 The new amount of token 0 in the reserves
   * @return reserve1 The new amount of token 1 in the reserves
   */
  function _virtualBuyback(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    UFixed32x4 _maxPriceImpact1
  )
    internal
    pure
    returns (uint128 reserve0, uint128 reserve1, uint256 amountIn1, uint256 amountOut0)
  {
    (amountOut0, amountIn1) = getVirtualBuybackAmounts(
      _amountIn1,
      _reserve1,
      _reserve0,
      _maxPriceImpact1
    );
    reserve0 = _reserve0 - uint128(amountOut0);
    reserve1 = _reserve1 + uint128(amountIn1);
  }

  /**
   * @notice Amplifies the users swap by a multiplier and then scales reserves to a configured ratio.
   * @param _reserve0 The amount of token 0 in the reserves
   * @param _reserve1 The amount of token 1 in the reserves
   * @param _amountIn1 The amount of token 1 to swap in
   * @param _amountOut1 The amount of token 1 to swap out
   * @param _swapMultiplier The multiplier to apply to the swap
   * @param _liquidityFraction The fraction relative to the amount of token 1 to scale the reserves to
   * @param _minK The minimum value of K to ensure that the reserves are not scaled too small
   * @return reserve0 The new amount of token 0 in the reserves
   * @return reserve1 The new amount of token 1 in the reserves
   */
  function _virtualSwap(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    uint256 _amountOut1,
    UFixed32x4 _swapMultiplier,
    UFixed32x4 _liquidityFraction,
    uint256 _minK
  ) internal pure returns (uint128 reserve0, uint128 reserve1) {
    uint256 virtualAmountOut1 = FixedMathLib.mul(_amountOut1, _swapMultiplier);

    uint256 virtualAmountIn0 = 0;
    if (virtualAmountOut1 < _reserve1) {
      // Sufficient reserves to handle the multiplier on the swap
      virtualAmountIn0 = getAmountIn(virtualAmountOut1, _reserve0, _reserve1);
    } else if (virtualAmountOut1 > 0 && _reserve1 > 1) {
      // Insuffucuent reserves in so cap it to max amount
      virtualAmountOut1 = _reserve1 - 1;
      virtualAmountIn0 = getAmountIn(virtualAmountOut1, _reserve0, _reserve1);
    } else {
      // Insufficient reserves
      // _reserve1 is 1, virtualAmountOut1 is 0
      virtualAmountOut1 = 0;
    }

    reserve0 = _reserve0 + uint128(virtualAmountIn0);
    reserve1 = _reserve1 - uint128(virtualAmountOut1);

    (reserve0, reserve1) = _applyLiquidityFraction(
      reserve0,
      reserve1,
      _amountIn1,
      _liquidityFraction,
      _minK
    );
  }

  /**
   * @notice Scales the reserves to a configured ratio.
   * @dev This is to ensure that the virtual reserves are large enough such that the next swap will
   *      have a tailored impact on the virtual reserves.
   * @param _reserve0 The amount of token 0 in the reserves
   * @param _reserve1 The amount of token 1 in the reserves
   * @param _amountIn1 The amount of token 1 swapped in
   * @param _liquidityFraction The fraction relative to the amount in of token 1 to scale the
   *                            reserves to
   * @param _minK The minimum value of K to validate the scaled reserves against
   * @return reserve0 The new amount of token 0 in the reserves
   * @return reserve1 The new amount of token 1 in the reserves
   */
  function _applyLiquidityFraction(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    UFixed32x4 _liquidityFraction,
    uint256 _minK
  ) internal pure returns (uint128 reserve0, uint128 reserve1) {
    uint256 reserve0_1 = (uint256(_reserve0) * _amountIn1 * FixedMathLib.multiplier) /
      (uint256(_reserve1) * UFixed32x4.unwrap(_liquidityFraction));
    uint256 reserve1_1 = FixedMathLib.div(_amountIn1, _liquidityFraction);

    // Ensure we can fit K into a uint256
    // Ensure new virtual reserves fit into uint112
    if (
      reserve0_1 <= type(uint112).max &&
      reserve1_1 <= type(uint112).max &&
      uint256(reserve1_1) * reserve0_1 > _minK
    ) {
      reserve0 = uint128(reserve0_1);
      reserve1 = uint128(reserve1_1);
    } else {
      reserve0 = _reserve0;
      reserve1 = _reserve1;
    }
  }

  /**
   * @notice Computes the amount of token 1 to swap in to get the provided amount of token 1 out.
   * @param _reserve0 The amount of token 0 in the reserves
   * @param _reserve1 The amount of token 1 in the reserves
   * @param _amountIn1 The amount of token 1 coming in to decrease prices
   * @param _amountOut1 The target amount of token 1 to swap out
   * @return The amount of token 0 to swap in to receive the given amount out of token 1
   */
  function computeExactAmountIn(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    uint256 _amountOut1,
    UFixed32x4 _maxPriceImpact1
  ) internal pure returns (uint256) {
    require(_amountOut1 <= _amountIn1, "LiquidatorLib/insufficient-balance-liquidity-a");
    (uint128 reserve0, uint128 reserve1, , ) = _virtualBuyback(
      _reserve0,
      _reserve1,
      _amountIn1,
      _maxPriceImpact1
    );
    return getAmountIn(_amountOut1, reserve0, reserve1);
  }

  /**
   * @notice Computes the amount of token 1 to swap out to get the procided amount of token 1 in.
   * @param _reserve0 The amount of token 0 in the reserves
   * @param _reserve1 The amount of token 1 in the reserves
   * @param _amountIn1 The amount of token 1 coming in to decrease prices
   * @param _amountIn0 The amount of token 0 to swap in
   * @return The amount of token 1 to swap out to receive the given amount in of token 0
   */
  function computeExactAmountOut(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    uint256 _amountIn0,
    UFixed32x4 _maxPriceImpact1
  ) internal pure returns (uint256) {
    (uint128 reserve0, uint128 reserve1, uint256 amountIn1, ) = _virtualBuyback(
      _reserve0,
      _reserve1,
      _amountIn1,
      _maxPriceImpact1
    );
    uint256 amountOut1 = getAmountOut(_amountIn0, reserve0, reserve1);
    require(amountOut1 <= amountIn1, "LiquidatorLib/insufficient-balance-liquidity-b");
    return amountOut1;
  }

  /**
   * @notice Adjusts the provided reserves based on the amount of token 1 coming in and performs
   *          a swap with the provided amount of token 0 in for token 1 out. Finally, scales the
   *          reserves using the provided liquidity fraction, token 1 coming in and minimum k.
   * @param _reserve0 The amount of token 0 in the reserves
   * @param _reserve1 The amount of token 1 in the reserves
   * @param _amountIn1 The amount of token 1 coming in
   * @param _amountIn0 The amount of token 0 to swap in to receive token 1 out
   * @param _swapMultiplier The multiplier to apply to the swap
   * @param _liquidityFraction The fraction relative to the amount in of token 1 to scale the
   *                           reserves to
   * @param _minK The minimum value of K to validate the scaled reserves against
   * @param _maxPriceImpact1 That maximum impact of token 1 the virtual buyback of yield can have on the price
   * @return reserve0 The new amount of token 0 in the reserves
   * @return reserve1 The new amount of token 1 in the reserves
   * @return amountOut1 The amount of token 1 swapped out
   */
  function swapExactAmountIn(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    uint256 _amountIn0,
    UFixed32x4 _swapMultiplier,
    UFixed32x4 _liquidityFraction,
    uint256 _minK,
    UFixed32x4 _maxPriceImpact1
  ) internal pure returns (uint128 reserve0, uint128 reserve1, uint256 amountOut1) {
    uint256 amountIn1;
    (reserve0, reserve1, amountIn1, ) = _virtualBuyback(
      _reserve0,
      _reserve1,
      _amountIn1,
      _maxPriceImpact1
    );

    amountOut1 = getAmountOut(_amountIn0, reserve0, reserve1);
    require(amountOut1 <= amountIn1, "LiquidatorLib/insufficient-balance-liquidity-c");
    reserve0 = reserve0 + uint128(_amountIn0);
    reserve1 = reserve1 - uint128(amountOut1);

    (reserve0, reserve1) = _virtualSwap(
      reserve0,
      reserve1,
      amountIn1,
      amountOut1,
      _swapMultiplier,
      _liquidityFraction,
      _minK
    );
  }

  /**
   * @notice Adjusts the provided reserves based on the amount of token 1 coming in and performs
   *         a swap with the provided amount of token 1 out for token 0 in. Finally, scales the
   *        reserves using the provided liquidity fraction, token 1 coming in and minimum k.
   * @param _reserve0 The amount of token 0 in the reserves
   * @param _reserve1 The amount of token 1 in the reserves
   * @param _amountIn1 The amount of token 1 coming in
   * @param _amountOut1 The amount of token 1 to swap out to receive token 0 in
   * @param _swapMultiplier The multiplier to apply to the swap
   * @param _liquidityFraction The fraction relative to the amount in of token 1 to scale the
   *                          reserves to
   * @param _minK The minimum value of K to validate the scaled reserves against
   * @param _maxPriceImpact1 That maximum impact of token 1 the virtual buyback of yield can have on the price
   * @return reserve0 The new amount of token 0 in the reserves
   * @return reserve1 The new amount of token 1 in the reserves
   * @return amountIn0 The amount of token 0 swapped in
   */
  function swapExactAmountOut(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    uint256 _amountOut1,
    UFixed32x4 _swapMultiplier,
    UFixed32x4 _liquidityFraction,
    uint256 _minK,
    UFixed32x4 _maxPriceImpact1
  ) internal pure returns (uint128 reserve0, uint128 reserve1, uint256 amountIn0) {
    require(_amountOut1 <= _amountIn1, "LiquidatorLib/insufficient-balance-liquidity-d");
    (reserve0, reserve1, , ) = _virtualBuyback(_reserve0, _reserve1, _amountIn1, _maxPriceImpact1);

    // do swap
    amountIn0 = getAmountIn(_amountOut1, reserve0, reserve1);
    reserve0 = reserve0 + uint128(amountIn0);
    reserve1 = reserve1 - uint128(_amountOut1);

    (reserve0, reserve1) = _virtualSwap(
      reserve0,
      reserve1,
      _amountIn1,
      _amountOut1,
      _swapMultiplier,
      _liquidityFraction,
      _minK
    );
  }

  /**
   * @notice Calculates the maximum amount of tokens in that results in the desired price impact.
   * @param reserve1 The current reserve of token 1
   * @param reserve0 The curernt reserve of token 0
   * @param priceImpact1 The price impact to allow after swapping in the resulting amount
   * @return amountIn1 The amount of token 1 to swap in to achieve the desired maximum price impact
   */
  function calculateRestrictedAmounts(
    uint128 reserve1,
    uint128 reserve0,
    UFixed32x4 priceImpact1
  ) internal pure returns (uint256 amountIn1, uint256 amountOut0) {
    // If the price of token 1 is really small, do a different calculation to avoid rounding errors.
    if (reserve1 > reserve0) {
      return calculateRestrictedAmountsInverted(reserve1, reserve0, priceImpact1);
    }

    uint256 scalar = reserve0 - reserve1 >= type(uint88).max ? 1 : 1e8;

    // "Price" isn't a very clear name. It's the amount of token 0 per token 1.
    // Calculate p1
    // p1 = r0 / r1
    uint256 price1 = (uint256(reserve0) * scalar) / reserve1;

    // Calculate p1'
    // p1' = p1 - (p1 * priceImpact1)
    uint256 price1_1 = price1 - FixedMathLib.mul(price1, priceImpact1);

    // Calculate r0'
    // p1' = r0' / r1'
    // r1' = r0' / p1'

    // r0' * r1' = r0 * r1
    // r0' * (r0' / p1') = r0 * r1
    // r0'^2 / p1' = r0 * r1
    // r0'^2 = r0 * r1 * p1'
    // r0' = sqrt(r0 * r1 * p1')
    uint256 reserve0_1 = Math.sqrt(((uint256(reserve0) * reserve1 * price1_1) / scalar));

    // Calculate r1'
    // r0' * r1' = r0 * r1
    // r1' = (r0 * r1) / r0'
    uint256 reserve1_1 = ((uint256(reserve0) * reserve1) / reserve0_1);

    // Calculate ao0
    // ao0 = r0 - r0'
    amountOut0 = reserve0 - reserve0_1;

    // Calculate ai1
    // ai1 = r1' - r1
    amountIn1 = reserve1_1 - reserve1;
  }

  /**
   * @notice Calculates the price impact on token 0 when the given price impact on token 1 occurs
   * @param reserve0 The current reserve of token 0
   * @param reserve1 The current reserve of token 1
   * @param priceImpact1 The price impact on token 1
   * @return priceImpact0 The price impact on token 0 when the given price impact on token 1 occurs
   */
  function calculateInversePriceImpact(
    uint128 reserve0,
    uint128 reserve1,
    UFixed32x4 priceImpact1
  ) internal pure returns (UFixed32x4 priceImpact0) {
    uint256 scalar = 1e33;

    // Calculate p1
    // p1 = r0 / r1
    uint256 p1 = (uint256(reserve0) * scalar) / reserve1; // +1e33

    // Calculate p1'
    // p1' = p1 - (p1 * priceImpact1)
    uint256 p1_1 = p1 * FixedMathLib.multiplier - p1 * UFixed32x4.unwrap(priceImpact1); // +1e37

    // Calculate pi0
    // pi0 = (p0' - p0) / p0
    // pi0 = (1/p1' - 1/p1) / 1/p1
    // pi0 = (1/p1' - 1/p1) * p1
    // pi0 = p1/p1' - 1
    priceImpact0 = UFixed32x4.wrap(
      uint32(
        (p1 * FixedMathLib.multiplier * FixedMathLib.multiplier) / p1_1 - FixedMathLib.multiplier
      )
    ); // +1e8 (1e4 to counter pYield_1, 1e4 to convert back to priceImpact)

    return priceImpact0;
  }

  /**
   * @notice Calculates the maximum amount of tokens in that results in the desired price impact.
   * @param reserve1 The current reserve of token 1
   * @param reserve0 The curernt reserve of token 0
   * @param priceImpact1 The price impact of token 1 to allow after swapping in the resulting amount
   * @return amountIn1 The amount of token 1 to swap in to achieve the desired maximum price impact
   */
  function calculateRestrictedAmountsInverted(
    uint128 reserve1,
    uint128 reserve0,
    UFixed32x4 priceImpact1
  ) internal pure returns (uint256 amountIn1, uint256 amountOut0) {
    // Calculate pi0
    UFixed32x4 priceImpact0 = calculateInversePriceImpact(reserve0, reserve1, priceImpact1);

    uint256 scalar = reserve1 - reserve0 >= type(uint88).max ? 1 : 1e8;

    // "Price" isn't a very clear name. It's the amount of token 1 per token 0.
    // Calculate p0
    // p0 = r1 / r0
    uint256 price0 = (uint256(reserve1) * scalar) / reserve0;

    // Calculate p0'
    // p0' = p0 - (p0 * priceImpact0)
    uint256 price0_1 = (price0 * FixedMathLib.multiplier) +
      (uint256(UFixed32x4.unwrap(priceImpact0)) * price0);

    // Calculate r1'
    // p0' = r1' / r0'
    // r0' = r1' / p0'

    // r0' * r1' = r0 * r1
    // r1' * (r1' / p0') = r0 * r1
    // r1'^2 / p0' = r0 * r1
    // r1'^2 = r0 * r1 * p0'
    // r1' = sqrt(r0 * r1 * p0')
    uint256 reserve1_1 = Math.sqrt(
      (uint256(reserve0) * reserve1 * price0_1) / (FixedMathLib.multiplier * scalar)
    );

    // Calculate r0'
    // r0' * r1' = r0 * r1
    // r0' = (r0 * r1) / r1'
    uint256 reserve0_1 = ((uint256(reserve0) * reserve1) / reserve1_1);

    // Calculate ao0
    // ao0 = r0 - r0'
    amountOut0 = reserve0 - reserve0_1;

    // Calculate ai1
    // ai1 = r1' - r1
    amountIn1 = reserve1_1 - reserve1;
  }

  /**
   * @notice Calculates the price impact of a swap in
   * @param _amountIn1 The amount of token 1 to swap in
   * @param _reserve1 The amount of token 1 in the reserves
   * @param _reserve0 The amount of token 0 in the reserves
   * @return priceImpact1 The price impact to token 1
   */
  function calculateVirtualSwapPriceImpact(
    uint256 _amountIn1,
    uint128 _reserve1,
    uint128 _reserve0
  ) internal pure returns (UFixed32x4 priceImpact1, uint256 amountOut0) {
    uint256 numerator = _amountIn1 * _reserve0;
    uint256 denominator = _amountIn1 + _reserve1;
    amountOut0 = numerator / denominator;

    uint128 reserve0_1 = _reserve0 - uint128(amountOut0);
    uint128 reserve1_1 = _reserve1 + uint128(_amountIn1);

    uint256 price1 = (uint256(_reserve1) * 1e38) / _reserve0;
    uint256 price1_1 = (uint256(reserve1_1) * 1e38) / reserve0_1;

    priceImpact1 = UFixed32x4.wrap(uint32(((price1_1 - price1)) / price1));
  }
}
