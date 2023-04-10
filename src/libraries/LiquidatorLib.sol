// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import "openzeppelin/token/ERC20/IERC20.sol";

import "./FixedMathLib.sol";

/**
 * @title PoolTogether Liquidator Library
 * @author PoolTogether Inc. Team
 * @notice
 */
library LiquidatorLib {
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

  function _virtualBuyback(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1
  ) internal pure returns (uint128 reserve0, uint128 reserve1) {
    uint256 amountOut0 = getAmountOut(_amountIn1, _reserve1, _reserve0);
    reserve0 = _reserve0 - uint128(amountOut0);
    reserve1 = _reserve1 + uint128(_amountIn1);
  }

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

  function _applyLiquidityFraction(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    UFixed32x4 _liquidityFraction,
    uint256 _minK
  ) internal pure returns (uint128 reserve0, uint128 reserve1) {
    uint128 reserve0_1 = uint128(
      (uint256(_reserve0) * _amountIn1 * FixedMathLib.multiplier) /
        (uint256(_reserve1) * UFixed32x4.unwrap(_liquidityFraction))
    );
    uint128 reserve1_1 = uint128(FixedMathLib.div(_amountIn1, _liquidityFraction));

    if (uint256(reserve1_1) * reserve0_1 > _minK) {
      reserve0 = reserve0_1;
      reserve1 = reserve1_1;
    } else {
      reserve0 = _reserve0;
      reserve1 = _reserve1;
    }
  }

  function computeExactAmountIn(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    uint256 _amountOut1
  ) internal pure returns (uint256) {
    require(_amountOut1 <= _amountIn1, "LiquidatorLib/insufficient-balance-liquidity-a");
    (uint128 reserve0, uint128 reserve1) = _virtualBuyback(_reserve0, _reserve1, _amountIn1);
    return getAmountIn(_amountOut1, reserve0, reserve1);
  }

  function computeExactAmountOut(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    uint256 _amountIn0
  ) internal pure returns (uint256) {
    (uint128 reserve0, uint128 reserve1) = _virtualBuyback(_reserve0, _reserve1, _amountIn1);
    uint256 amountOut1 = getAmountOut(_amountIn0, reserve0, reserve1);
    require(amountOut1 <= _amountIn1, "LiquidatorLib/insufficient-balance-liquidity-b");
    return amountOut1;
  }

  function swapExactAmountIn(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    uint256 _amountIn0,
    UFixed32x4 _swapMultiplier,
    UFixed32x4 _liquidityFraction,
    uint256 _minK
  ) internal pure returns (uint128 reserve0, uint128 reserve1, uint256 amountOut1) {
    (reserve0, reserve1) = _virtualBuyback(_reserve0, _reserve1, _amountIn1);

    amountOut1 = getAmountOut(_amountIn0, reserve0, reserve1);
    require(amountOut1 <= _amountIn1, "LiquidatorLib/insufficient-balance-liquidity-c");
    reserve0 = reserve0 + uint128(_amountIn0);
    reserve1 = reserve1 - uint128(amountOut1);

    (reserve0, reserve1) = _virtualSwap(
      reserve0,
      reserve1,
      _amountIn1,
      amountOut1,
      _swapMultiplier,
      _liquidityFraction,
      _minK
    );
  }

  function swapExactAmountOut(
    uint128 _reserve0,
    uint128 _reserve1,
    uint256 _amountIn1,
    uint256 _amountOut1,
    UFixed32x4 _swapMultiplier,
    UFixed32x4 _liquidityFraction,
    uint256 _minK
  ) internal pure returns (uint128 reserve0, uint128 reserve1, uint256 amountIn0) {
    require(_amountOut1 <= _amountIn1, "LiquidatorLib/insufficient-balance-liquidity-d");
    (reserve0, reserve1) = _virtualBuyback(_reserve0, _reserve1, _amountIn1);

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
}
