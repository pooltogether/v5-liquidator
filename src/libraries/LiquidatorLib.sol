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
    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint256 amountIn1, uint128 reserve1, uint128 reserve0)
        internal
        pure
        returns (uint256 amountOut0)
    {
        require(reserve0 > 0 && reserve1 > 0, "LiquidatorLib/insufficient-reserve-liquidity");
        uint256 numerator = amountIn1 * reserve0;
        uint256 denominator = amountIn1 + reserve1;
        amountOut0 = numerator / denominator;
        require(amountOut0 < reserve0, "LiquidatorLib/insufficient-reserve-liquidity");
        // require(amountOut0 > 0, "LiquidatorLib/insufficient-amount-out");
        return amountOut0;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint256 amountOut0, uint128 reserve1, uint128 reserve0)
        internal
        pure
        returns (uint256 amountIn1)
    {
        // require(amountOut0 > 0, "LiquidatorLib/insufficient-amount-out");
        require(amountOut0 < reserve0, "LiquidatorLib/insufficient-reserve-liquidity");
        require(reserve0 > 0 && reserve1 > 0, "LiquidatorLib/insufficient-reserve-liquidity");
        uint256 numerator = amountOut0 * reserve1;
        uint256 denominator = uint256(reserve0) - amountOut0;
        amountIn1 = (numerator / denominator);
    }

    function virtualBuyback(uint128 _reserve0, uint128 _reserve1, uint256 _amountIn1)
        internal
        pure
        returns (uint128 reserve0, uint128 reserve1)
    {
        // swap back yield
        uint256 amountOut0 = getAmountOut(_amountIn1, _reserve1, _reserve0);
        reserve0 = _reserve0 - uint128(amountOut0); // Note: Safe: amountOut0 < reserve0
        reserve1 = _reserve1 + uint128(_amountIn1); // Note: Potential overflow
    }

    function computeExactAmountIn(uint128 _reserve0, uint128 _reserve1, uint256 _amountIn1, uint256 _amountOut1)
        internal
        pure
        returns (uint256)
    {
        require(_amountOut1 <= _amountIn1, "LiquidatorLib/insufficient-balance-liquidity");
        (uint128 reserve0, uint128 reserve1) = virtualBuyback(_reserve0, _reserve1, _amountIn1);
        return getAmountIn(_amountOut1, reserve0, reserve1);
    }

    function computeExactAmountOut(uint128 _reserve0, uint128 _reserve1, uint256 _amountIn1, uint256 _amountIn0)
        internal
        pure
        returns (uint256)
    {
        (uint128 reserve0, uint128 reserve1) = virtualBuyback(_reserve0, _reserve1, _amountIn1);

        uint256 amountOut1 = getAmountOut(_amountIn0, reserve0, reserve1);
        require(amountOut1 <= _amountIn1, "LiquidatorLib/insufficient-balance-liquidity");
        return amountOut1;
    }

    function swapExactAmountIn(
        uint128 _reserve0,
        uint128 _reserve1,
        uint256 _amountIn1,
        uint256 _amountIn0,
        UFixed32x9 _swapMultiplier,
        UFixed32x9 _liquidityFraction
    ) internal pure returns (uint128 reserve0, uint128 reserve1, uint256 amountOut1) {
        (reserve0, reserve1) = virtualBuyback(_reserve0, _reserve1, _amountIn1);

        // do swap
        amountOut1 = getAmountOut(_amountIn0, reserve0, reserve1);
        require(amountOut1 <= _amountIn1, "LiquidatorLib/insufficient-balance-liquidity");
        reserve0 = reserve0 + uint128(_amountIn0); // Note: Potential overflow
        reserve1 = reserve1 - uint128(amountOut1); // Note: Safe: amountOut1 < reserve1

        (reserve0, reserve1) =
            _virtualSwap(reserve0, reserve1, _amountIn1, amountOut1, _swapMultiplier, _liquidityFraction);
    }

    function swapExactAmountOut(
        uint128 _reserve0,
        uint128 _reserve1,
        uint256 _amountIn1,
        uint256 _amountOut1,
        UFixed32x9 _swapMultiplier,
        UFixed32x9 _liquidityFraction
    ) internal pure returns (uint128 reserve0, uint128 reserve1, uint256 amountIn0) {

        require(_amountOut1 <= _amountIn1, "LiquidatorLib/insufficient-balance-liquidity");
        (reserve0, reserve1) = virtualBuyback(_reserve0, _reserve1, _amountIn1);


        // do swap
        amountIn0 = getAmountIn(_amountOut1, reserve0, reserve1);
        reserve0 = reserve0 + uint128(amountIn0); // Note: Potential overflow
        reserve1 = reserve1 - uint128(_amountOut1); // Note: Safe: _amountOut1 < reserve1

        (reserve0, reserve1) =
            _virtualSwap(reserve0, reserve1, _amountIn1, _amountOut1, _swapMultiplier, _liquidityFraction);
    }

    function _virtualSwap(
        uint128 _reserve0,
        uint128 _reserve1,
        uint256 _amountIn1,
        uint256 _amountOut1,
        UFixed32x9 _swapMultiplier,
        UFixed32x9 _liquidityFraction
    ) internal pure returns (uint128 reserve0, uint128 reserve1) {
        uint256 virtualAmountOut1 = FixedMathLib.mul(_amountOut1, _swapMultiplier);
        // NEED THIS TO BE GREATER THAN 0 for getAmountIn!
        // Effectively a minimum of 1e9 going out to the user?

        uint256 virtualAmountIn0 = getAmountIn(virtualAmountOut1, _reserve0, _reserve1);

        reserve0 = _reserve0 + uint128(virtualAmountIn0); // Note: Potential overflow
        reserve1 = _reserve1 - uint128(virtualAmountOut1); // Note: Potential underflow after sub


        // now, we want to ensure that the accrued yield is always a small fraction of virtual LP position.\
        uint256 reserveFraction = (_amountIn1 * 1e9) / reserve1;
        uint256 multiplier = FixedMathLib.div(reserveFraction, _liquidityFraction);
        reserve0 = uint128((uint256(reserve0) * multiplier) / 1e9); // Note: Safe cast
        reserve1 = uint128((uint256(reserve1) * multiplier) / 1e9); // Note: Safe cast
    }
}

// reserve1 of 2381976568565668072671905656
// rf of 2857142857
// multiplier of 142857142850
