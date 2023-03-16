// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "./libraries/LiquidatorLib.sol";
import "./libraries/FixedMathLib.sol";
import "./interfaces/ILiquidationSource.sol";
import { Math } from "openzeppelin/utils/math/Math.sol";

contract LiquidationPair {
  /* ============ Variables ============ */

  ILiquidationSource public immutable source; // Where to get tokenIn from
  address public immutable tokenIn; // Token being sent into the Liquidator Pair by the user(ex. POOL)
  address public immutable tokenOut; // Token being sent out of the Liquidation Pair to the user(ex. USDC, WETH, etc.)
  UFixed32x9 public immutable swapMultiplier; // 9 decimals
  UFixed32x9 public immutable liquidityFraction; // 9 decimals

  uint128 public virtualReserveIn;
  uint128 public virtualReserveOut;
  uint256 public immutable minK;

  /* ============ Events ============ */

  event Swapped(address indexed account, uint256 amountIn, uint256 amountOut);

  /* ============ Constructor ============ */

  constructor(
    ILiquidationSource _source,
    address _tokenIn,
    address _tokenOut,
    UFixed32x9 _swapMultiplier,
    UFixed32x9 _liquidityFraction,
    uint128 _virtualReserveIn,
    uint128 _virtualReserveOut,
    uint256 _minK
  ) {
    require(
      UFixed32x9.unwrap(_liquidityFraction) > 0,
      "LiquidationPair/liquidity-fraction-greater-than-zero"
    );
    require(
      UFixed32x9.unwrap(_liquidityFraction) > 0,
      "LiquidationPair/liquidity-fraction-greater-than-zero"
    );
    // NOTE: Liquidity Fraction is applied to a uint112, we need to ensure it's  large enough such that the result doesn't overflow a uint128.
    // Solutions:
    // 1. Require liquidityFraction > 0.0001
    // require(
    //   UFixed32x9.unwrap(_liquidityFraction) > 100000,
    //   "LiquidationPair/liquidity-fraction-greater-than-uint16"
    // );
    require(
      UFixed32x9.unwrap(_swapMultiplier) <= 1e9,
      "LiquidationPair/swap-multiplier-less-than-one"
    );
    require(
      UFixed32x9.unwrap(_liquidityFraction) <= 1e9,
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
    // take amount in, apply the multiplier and liquidity fraction calculations, ensure the final virtual amounts don't result in overflow
  }

  function maxAmountOut() external returns (uint256) {
    // If available amount outsizes reserves, need to cap it to the reserves

    // TODO: This is what was in the linear ticket, I don't think this is accurate though..
    // return Math.min(_availableReserveOut(), virtualReserveOut);

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

    emit Swapped(_account, _amountIn, amountOut);

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

    emit Swapped(_account, amountIn, _amountOut);

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

  // Note: Uniswap has restrictions on _account, but we don't
  // Note: Uniswap requires _amountOut to be > 0, but we don't
  function _swap(address _account, uint256 _amountOut, uint256 _amountIn) internal {
    source.liquidate(_account, tokenIn, _amountIn, tokenOut, _amountOut);
  }
}
