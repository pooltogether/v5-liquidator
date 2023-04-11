// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "./libraries/LiquidatorLib.sol";
import "./libraries/FixedMathLib.sol";
import "./interfaces/ILiquidationSource.sol";
import { Math } from "openzeppelin/utils/math/Math.sol";

contract LiquidationPair {
  /* ============ Variables ============ */

  ILiquidationSource public immutable source;
  address public immutable tokenIn;
  address public immutable tokenOut;
  UFixed32x4 public immutable swapMultiplier;
  UFixed32x4 public immutable liquidityFraction;

  uint128 public virtualReserveIn;
  uint128 public virtualReserveOut;
  uint256 public immutable minK;

  /* ============ Events ============ */

  event Swapped(
    address indexed account,
    uint256 amountIn,
    uint256 amountOut,
    uint128 virtualReserveIn,
    uint128 virtualReserveOut
  );

  /* ============ Constructor ============ */

  constructor(
    ILiquidationSource _source,
    address _tokenIn,
    address _tokenOut,
    UFixed32x4 _swapMultiplier,
    UFixed32x4 _liquidityFraction,
    uint128 _virtualReserveIn,
    uint128 _virtualReserveOut,
    uint256 _minK
  ) {
    require(
      UFixed32x4.unwrap(_liquidityFraction) > 0,
      "LiquidationPair/liquidity-fraction-greater-than-zero"
    );
    require(
      UFixed32x4.unwrap(_liquidityFraction) > 0,
      "LiquidationPair/liquidity-fraction-greater-than-zero"
    );
    require(
      UFixed32x4.unwrap(_swapMultiplier) <= 1e4,
      "LiquidationPair/swap-multiplier-less-than-one"
    );
    require(
      UFixed32x4.unwrap(_liquidityFraction) <= 1e4,
      "LiquidationPair/liquidity-fraction-less-than-one"
    );
    require(
      uint256(_virtualReserveIn) * _virtualReserveOut >= _minK,
      "LiquidationPair/virtual-reserves-greater-than-min-k"
    );
    require(_minK > 0, "LiquidationPair/min-k-greater-than-zero");
    require(_virtualReserveIn <= type(uint112).max, "LiquidationPair/virtual-reserve-in-too-large");
    require(
      _virtualReserveOut <= type(uint112).max,
      "LiquidationPair/virtual-reserve-out-too-large"
    );

    source = _source;
    tokenIn = _tokenIn;
    tokenOut = _tokenOut;
    swapMultiplier = _swapMultiplier;
    liquidityFraction = _liquidityFraction;
    virtualReserveIn = _virtualReserveIn;
    virtualReserveOut = _virtualReserveOut;
    minK = _minK;
  }

  /* ============ External Function ============ */

  function maxAmountIn() external returns (uint256) {
    return
      LiquidatorLib.computeExactAmountIn(
        virtualReserveIn,
        virtualReserveOut,
        _availableReserveOut(),
        _availableReserveOut()
      );
  }

  function maxAmountOut() external returns (uint256) {
    return _availableReserveOut();
  }

  function _availableReserveOut() internal returns (uint256) {
    return source.availableBalanceOf(tokenOut);
  }

  function nextLiquidationState() external returns (uint128, uint128) {
    return
      LiquidatorLib._virtualBuyback(virtualReserveIn, virtualReserveOut, _availableReserveOut());
  }

  function computeExactAmountIn(uint256 _amountOut) external returns (uint256) {
    return
      LiquidatorLib.computeExactAmountIn(
        virtualReserveIn,
        virtualReserveOut,
        _availableReserveOut(),
        _amountOut
      );
  }

  function computeExactAmountOut(uint256 _amountIn) external returns (uint256) {
    return
      LiquidatorLib.computeExactAmountOut(
        virtualReserveIn,
        virtualReserveOut,
        _availableReserveOut(),
        _amountIn
      );
  }

  function swapExactAmountIn(
    address _account,
    uint256 _amountIn,
    uint256 _amountOutMin
  ) external returns (uint256) {
    uint256 availableBalance = _availableReserveOut();
    (uint128 _virtualReserveIn, uint128 _virtualReserveOut, uint256 amountOut) = LiquidatorLib
      .swapExactAmountIn(
        virtualReserveIn,
        virtualReserveOut,
        availableBalance,
        _amountIn,
        swapMultiplier,
        liquidityFraction,
        minK
      );

    virtualReserveIn = _virtualReserveIn;
    virtualReserveOut = _virtualReserveOut;

    require(amountOut >= _amountOutMin, "LiquidationPair/min-not-guaranteed");
    _swap(_account, amountOut, _amountIn);

    emit Swapped(_account, _amountIn, amountOut, _virtualReserveIn, _virtualReserveOut);

    return amountOut;
  }

  function swapExactAmountOut(
    address _account,
    uint256 _amountOut,
    uint256 _amountInMax
  ) external returns (uint256) {
    uint256 availableBalance = _availableReserveOut();
    (uint128 _virtualReserveIn, uint128 _virtualReserveOut, uint256 amountIn) = LiquidatorLib
      .swapExactAmountOut(
        virtualReserveIn,
        virtualReserveOut,
        availableBalance,
        _amountOut,
        swapMultiplier,
        liquidityFraction,
        minK
      );
    virtualReserveIn = _virtualReserveIn;
    virtualReserveOut = _virtualReserveOut;
    require(amountIn <= _amountInMax, "LiquidationPair/max-not-guaranteed");
    _swap(_account, _amountOut, amountIn);

    emit Swapped(_account, amountIn, _amountOut, _virtualReserveIn, _virtualReserveOut);

    return amountIn;
  }

  /**
   * @notice Get the address that will receive `tokenIn`.
   * @return address Address of the target
   */
  function target() external returns (address) {
    return source.targetOf(tokenIn);
  }

  /* ============ Internal Functions ============ */

  function _swap(address _account, uint256 _amountOut, uint256 _amountIn) internal {
    source.liquidate(_account, tokenIn, _amountIn, tokenOut, _amountOut);
  }
}
