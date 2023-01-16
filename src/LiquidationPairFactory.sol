// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import "openzeppelin/token/ERC20/IERC20.sol";

import "./LiquidationPair.sol";

contract LiquidationPairFactory {
    event PairCreated(
        LiquidationPair indexed liquidator,
        ILiquidationPairYieldSource indexed LiquidationPairYieldSource,
        address target,
        IERC20 indexed tokenIn,
        IERC20 tokenOut,
        uint32 swapMultiplier,
        uint32 liquidityFraction,
        uint256 virtualReserveIn,
        uint256 virtualReserveOut
    );

    constructor() {}

    function createPair(
        address _owner,
        ILiquidationPairYieldSource _liquidatorYieldSource,
        address _target,
        IERC20 _tokenIn,
        IERC20 _tokenOut,
        uint32 _swapMultiplier,
        uint32 _liquidityFraction,
        uint256 _virtualReserveIn,
        uint256 _virtualReserveOut
    ) external returns (LiquidationPair) {
        LiquidationPair liquidator =
        new LiquidationPair(_owner, _liquidatorYieldSource, _target,  _tokenIn, _tokenOut, _swapMultiplier, _liquidityFraction, _virtualReserveIn, _virtualReserveOut);
        emit PairCreated(
            liquidator,
            _liquidatorYieldSource,
            _target,
            _tokenIn,
            _tokenOut,
            _swapMultiplier,
            _liquidityFraction,
            _virtualReserveIn,
            _virtualReserveOut
            );
        return liquidator;
    }
}
