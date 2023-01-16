// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import "openzeppelin/token/ERC20/IERC20.sol";

/**
 * @title PoolTogether Liquidator Library
 * @author PoolTogether Inc. Team
 * @notice
 */
library LiquidatorLib {
    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint256 amountIn1, uint256 reserve1, uint256 reserve0)
        internal
        pure
        returns (uint256 amountOut0)
    {
        require(reserve0 > 0 && reserve1 > 0, "CpmmLib/INSUFF_PAIR_LIQ");
        uint256 numerator = amountIn1 * reserve0;
        uint256 denominator = reserve1 + amountIn1;
        amountOut0 = numerator / denominator;
        return amountOut0;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint256 amountOut0, uint256 reserve1, uint256 reserve0)
        internal
        pure
        returns (uint256 amountIn1)
    {
        require(amountOut0 < reserve0, "CpmmLib/INSUFF_LIQ");
        require(reserve0 > 0 && reserve1 > 0, "CpmmLib/INSUFF_PAIR_LIQ");
        uint256 numerator = reserve1 * amountOut0;
        uint256 denominator = reserve0 - amountOut0;
        amountIn1 = (numerator / denominator);
    }

    function virtualBuyback(uint256 _reserve0, uint256 _reserve1, uint256 _amountIn1)
        internal
        pure
        returns (uint256 reserve0, uint256 reserve1)
    {
        // swap back yield
        uint256 amountOut0 = getAmountOut(_amountIn1, _reserve1, _reserve0);
        reserve0 = _reserve0 - amountOut0;
        reserve1 = _reserve1 + _amountIn1;
    }

    function computeExactAmountIn(uint256 _reserve0, uint256 _reserve1, uint256 _amountIn1, uint256 _amountOut1)
        internal
        pure
        returns (uint256)
    {
        require(_amountOut1 <= _amountIn1, "insuff balance");
        (uint256 reserve0, uint256 reserve1) = virtualBuyback(_reserve0, _reserve1, _amountIn1);
        return getAmountIn(_amountOut1, reserve0, reserve1);
    }

    function computeExactAmountOut(uint256 _reserve0, uint256 _reserve1, uint256 _amountIn1, uint256 _amountIn0)
        internal
        pure
        returns (uint256)
    {
        (uint256 reserve0, uint256 reserve1) = virtualBuyback(_reserve0, _reserve1, _amountIn1);
        uint256 amountOut1 = getAmountOut(_amountIn0, reserve0, reserve1);
        require(amountOut1 <= _amountIn1, "insuff balance");
        return amountOut1;
    }

    function _virtualSwap(
        uint256 _reserve0,
        uint256 _reserve1,
        uint256 _availableReserve1,
        uint256 _reserve1Out,
        uint32 _swapMultiplier,
        uint32 _liquidityFraction
    ) internal pure returns (uint256 reserve0, uint256 reserve1) {
        // apply the additional swap
        uint256 extraVirtualReserveOut1 = (_reserve1Out * _swapMultiplier) / 1e9;
        uint256 extraVirtualReserveIn0 = getAmountIn(extraVirtualReserveOut1, _reserve0, _reserve1);
        reserve0 = _reserve0 + extraVirtualReserveIn0;
        reserve1 = _reserve1 - extraVirtualReserveOut1;

        // now, we want to ensure that the accrued yield is always a small fraction of virtual LP position.
        uint256 reserveFraction = (_availableReserve1 * 1e9) / reserve1;
        uint256 multiplier = (reserveFraction * 1e9) / uint256(_liquidityFraction);
        reserve0 = (reserve0 * multiplier) / 1e9;
        reserve1 = (reserve1 * multiplier) / 1e9;
    }

    function swapExactAmountIn(
        uint256 _reserve0,
        uint256 _reserve1,
        uint256 _availableReserve1,
        uint256 _amountIn0,
        uint32 _swapMultiplier,
        uint32 _liquidityFraction
    ) internal pure returns (uint256 reserve0, uint256 reserve1, uint256 amountOut1) {
        (reserve0, reserve1) = virtualBuyback(_reserve0, _reserve1, _availableReserve1);

        // do swap
        amountOut1 = getAmountOut(_amountIn0, reserve0, reserve1);
        require(amountOut1 <= _availableReserve1, "LiqLib/insuff-liq");
        reserve0 = reserve0 + _amountIn0;
        reserve1 = reserve1 - amountOut1;

        (reserve0, reserve1) =
            _virtualSwap(reserve0, reserve1, _availableReserve1, amountOut1, _swapMultiplier, _liquidityFraction);
    }

    function swapExactAmountOut(
        uint256 _reserve0,
        uint256 _reserve1,
        uint256 _availableReserve1,
        uint256 _amountOut1,
        uint32 _swapMultiplier,
        uint32 _liquidityFraction
    ) internal pure returns (uint256 reserve0, uint256 reserve1, uint256 amountIn0) {
        require(_amountOut1 <= _availableReserve1, "LiqLib/insuff-liq");
        (reserve0, reserve1) = virtualBuyback(_reserve0, _reserve1, _availableReserve1);

        // do swap
        amountIn0 = getAmountIn(_amountOut1, reserve0, reserve1);
        reserve0 = reserve0 + amountIn0;
        reserve1 = reserve1 - _amountOut1;

        (reserve0, reserve1) =
            _virtualSwap(reserve0, reserve1, _availableReserve1, _amountOut1, _swapMultiplier, _liquidityFraction);
    }
}
