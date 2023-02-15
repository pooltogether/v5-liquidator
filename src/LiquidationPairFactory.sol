// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import "./LiquidationPair.sol";

contract LiquidationPairFactory {

    /* ============ Events ============ */
    event PairCreated(
        LiquidationPair indexed liquidator,
        ILiquidationSource indexed source,
        address indexed tokenIn,
        address tokenOut,
        UFixed32x9 swapMultiplier,
        UFixed32x9 liquidityFraction,
        uint128 virtualReserveIn,
        uint128 virtualReserveOut
    );

    /* ============ Variables ============ */
    LiquidationPair[] public allPairs;

    /* ============ External Functions ============ */
    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(
        ILiquidationSource _source,
        address _tokenIn,
        address _tokenOut,
        UFixed32x9 _swapMultiplier,
        UFixed32x9 _liquidityFraction,
        uint128 _virtualReserveIn,
        uint128 _virtualReserveOut
    ) external returns (LiquidationPair) {
        LiquidationPair _liquidationPair = new LiquidationPair(
            _source,
            _tokenIn,
            _tokenOut,
            _swapMultiplier,
            _liquidityFraction,
            _virtualReserveIn,
            _virtualReserveOut
        );

        allPairs.push(_liquidationPair);

        emit PairCreated(
            _liquidationPair,
            _source,
            _tokenIn,
            _tokenOut,
            _swapMultiplier,
            _liquidityFraction,
            _virtualReserveIn,
            _virtualReserveOut
            );

        return _liquidationPair;
    }
}
