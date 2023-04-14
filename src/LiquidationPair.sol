// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "./libraries/LiquidatorLib.sol";
import "./libraries/FixedMathLib.sol";
import "./interfaces/ILiquidationSource.sol";
import { Math } from "openzeppelin/utils/math/Math.sol";

/**
 * @title PoolTogether Liquidation Pair
 * @author PoolTogether Inc. Team
 * @notice The LiquidationPair is a UniswapV2-like pair that allows the liquidation of tokens
 *          from an ILiquidationSource. Users can swap tokens in exchange for the tokens available.
 *          The LiquidationPair implements a virtual reserve system that results in the value
 *          tokens available from the ILiquidationSource to decay over time relative to the value
 *          of the token swapped in.
 * @dev Each swap consists of four steps:
 *       1. A virtual buyback of the tokens available from the ILiquidationSource. This ensures
 *          that the value of the tokens available from the ILiquidationSource decays as
 *          tokens accrue.
 *      2. The main swap of tokens the user requested.
 *      3. A virtual swap that is a small multiplier applied to the users swap. This is to
 *          push the value of the tokens being swapped back up towards the market value.
 *      4. A scaling of the virtual reserves. This is to ensure that the virtual reserves
 *          are large enough such that the next swap will have a realistic impact on the virtual
 *          reserves.
 */
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

  /**
   * @notice Emitted when the pair is swapped.
   * @param account The account that swapped.
   * @param amountIn The amount of token in swapped.
   * @param amountOut The amount of token out swapped.
   * @param virtualReserveIn The updated virtual reserve of the token in.
   * @param virtualReserveOut The updated virtual reserve of the token out.
   */
  event Swapped(
    address indexed account,
    uint256 amountIn,
    uint256 amountOut,
    uint128 virtualReserveIn,
    uint128 virtualReserveOut
  );

  /* ============ Constructor ============ */

  /**
   * @notice Construct a new LiquidationPair.
   * @param _source The source of yield for the liquidation pair.
   * @param _tokenIn The token to be swapped in.
   * @param _tokenOut The token to be swapped out.
   * @param _swapMultiplier The multiplier for the users swaps.
   * @param _liquidityFraction The liquidity fraction to be applied after swapping.
   * @param _virtualReserveIn The initial virtual reserve of token in.
   * @param _virtualReserveOut The initial virtual reserve of token out.
   * @param _minK The minimum value of k.
   * @dev The swap multiplier and liquidity fraction are represented as UFixed32x4.
   */
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

  /**
   * @notice Computes the maximum amount of tokens that can be swapped in given the current state of the liquidation pair.
   * @return The maximum amount of tokens that can be swapped in.
   */
  function maxAmountIn() external returns (uint256) {
    return
      LiquidatorLib.computeExactAmountIn(
        virtualReserveIn,
        virtualReserveOut,
        _availableReserveOut(),
        _availableReserveOut()
      );
  }

  /**
   * @notice Gets the maximum amount of tokens that can be swapped out from the source.
   * @return The maximum amount of tokens that can be swapped out.
   */
  function maxAmountOut() external returns (uint256) {
    return _availableReserveOut();
  }

  /**
   * @notice Gets the available liquidity that has accrued that users can swap for.
   * @return The available liquidity that users can swap for.
   */
  function _availableReserveOut() internal returns (uint256) {
    return source.availableBalanceOf(tokenOut);
  }

  /**
   * @notice Computes the virtual reserves post virtual buyback of all available liquidity that has accrued.
   * @return The virtual reserve of the token in.
   * @return The virtual reserve of the token out.
   */
  function nextLiquidationState() external returns (uint128, uint128) {
    return
      LiquidatorLib._virtualBuyback(virtualReserveIn, virtualReserveOut, _availableReserveOut());
  }

  /**
   * @notice Computes the exact amount of tokens to send in for the given amount of tokens to receive out.
   * @param _amountOut The amount of tokens to receive out.
   * @return The amount of tokens to send in.
   */
  function computeExactAmountIn(uint256 _amountOut) external returns (uint256) {
    return
      LiquidatorLib.computeExactAmountIn(
        virtualReserveIn,
        virtualReserveOut,
        _availableReserveOut(),
        _amountOut
      );
  }

  /**
   * @notice Computes the exact amount of tokens to receive out for the given amount of tokens to send in.
   * @param _amountIn The amount of tokens to send in.
   * @return The amount of tokens to receive out.
   */
  function computeExactAmountOut(uint256 _amountIn) external returns (uint256) {
    return
      LiquidatorLib.computeExactAmountOut(
        virtualReserveIn,
        virtualReserveOut,
        _availableReserveOut(),
        _amountIn
      );
  }

  /**
   * @notice Swaps the given amount of tokens in and ensures a minimum amount of tokens are received out.
   * @dev The amount of tokens being swapped in must be sent to the target before calling this function.
   * @param _account The address to send the tokens to.
   * @param _amountIn The amount of tokens sent in.
   * @param _amountOutMin The minimum amount of tokens to receive out.
   * @return The amount of tokens received out.
   */
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

  /**
   * @notice Swaps the given amount of tokens out and ensures the amount of tokens in doesn't exceed the given maximum.
   * @dev The amount of tokens being swapped in must be sent to the target before calling this function.
   * @param _account The address to send the tokens to.
   * @param _amountOut The amount of tokens to receive out.
   * @param _amountInMax The maximum amount of tokens to send in.
   * @return The amount of tokens sent in.
   */
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
   * @return Address of the target
   */
  function target() external returns (address) {
    return source.targetOf(tokenIn);
  }

  /* ============ Internal Functions ============ */

  /**
   * @notice Sends the provided amounts of tokens to the address given.
   * @param _account The address to send the tokens to.
   * @param _amountOut The amount of tokens to receive out.
   * @param _amountIn The amount of tokens sent in.
   */
  function _swap(address _account, uint256 _amountOut, uint256 _amountIn) internal {
    source.liquidate(_account, tokenIn, _amountIn, tokenOut, _amountOut);
  }
}
