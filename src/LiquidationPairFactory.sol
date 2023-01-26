// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import "openzeppelin/token/ERC20/IERC20.sol";

import "./LiquidationPair.sol";

contract LiquidationPairFactory {
    event PairCreated(
        LiquidationPair indexed liquidator,
        ILiquidationSource indexed source,
        address target,
        IERC20 indexed tokenIn,
        IERC20 tokenOut,
        UFixed32x9 swapMultiplier,
        UFixed32x9 liquidityFraction,
        uint128 virtualReserveIn,
        uint128 virtualReserveOut
    );

    constructor() {}

    function createPair(
        address _owner,
        ILiquidationSource _source,
        address _target,
        IERC20 _tokenIn,
        IERC20 _tokenOut,
        UFixed32x9 _swapMultiplier,
        UFixed32x9 _liquidityFraction,
        uint128 _virtualReserveIn,
        uint128 _virtualReserveOut
    ) external returns (LiquidationPair) {
        LiquidationPair liquidator =
        new LiquidationPair(_owner, _source, _target,  _tokenIn, _tokenOut, _swapMultiplier, _liquidityFraction, _virtualReserveIn, _virtualReserveOut);
        emit PairCreated(
            liquidator,
            _source,
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
