// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "./libraries/LiquidatorLib.sol";
import "./libraries/FixedMathLib.sol";
import "./interfaces/ILiquidationSource.sol";
import { Math } from "openzeppelin/utils/math/Math.sol";

/// @notice Emitted when the liquidity fraction is set to zero
error LiquidationPair_LiquidityFraction_Zero();

/// @notice Emitted when the liquidity fraction is greater than one
/// @param liquidityFraction The unwrapped liquidity fraction being set
error LiquidationPair_LiquidityFraction_GT_One(uint32 liquidityFraction);

/// @notice Emitted when the swap multiplier is greater than one
/// @param swapMultiplier The unwrapped swap multiplier
error LiquidationPair_SwapMultiplier_GT_One(uint32 swapMultiplier);

/// @notice Emitted when the virtual reserve in multiplied by the virtual reserve out is less than the min `K` value
/// @param virtualReserveIn The virtual reserve in
/// @param virtualReserveOut The virtual reserve out
/// @param minK The min `K` value
error LiquidationPair_VirtualReserves_LT_MinK(uint128 virtualReserveIn, uint128 virtualReserveOut, uint256 minK);

/// @notice Emitted when the max price impact out is greater than or equal to the limit
/// @param maxPriceImpactOut The unwrapped max price impact out
/// @param maxImpact The unwrapped max impact limit
error LiquidationPair_MaxPriceImpactOut_GTE_Max(uint32 maxPriceImpactOut, uint32 maxImpact);

/// @notice Emitted when the max price impact out is less than the minimum allowed
/// @param maxPriceImpactOut The unwrapped max price impact out
/// @param minImpact The unwrapped minimum impact limit
error LiquidationPair_MaxPriceImpactOut_LT_Min(uint32 maxPriceImpactOut, uint32 minImpact);

/// @notice Emitted when the min `K` value is set to zero
error LiquidationPair_MinK_Zero();

/// @notice Emitted when the virtual reserve in is too large
/// @param virtualReserveIn The virtual reserve in
/// @param maxVirtualReserveIn The max virtual reserve in
error LiquidationPair_VirtualReserveIn_GT_Max(uint128 virtualReserveIn, uint128 maxVirtualReserveIn);

/// @notice Emitted when the virtual reserve out is too large
/// @param virtualReserveOut The virtual reserve out
/// @param maxVirtualReserveOut The max virtual reserve out
error LiquidationPair_VirtualReserveOut_GT_Max(uint128 virtualReserveOut, uint128 maxVirtualReserveOut);

/// @notice Emitted when the caller's min out threshold cannot be met with a swapExactAmountIn call
/// @param minOut The caller's minimum requested out
/// @param amountOut The amount that would be swapped out
error LiquidationPair_MinOutNotMet(uint256 minOut, uint256 amountOut);

/// @notice Emitted when the caller's max in limit cannot be met with a swapExactAmountOut call
/// @param maxIn The caller's max in limit
/// @param amountIn The amount that would be swapped in
error LiquidationPair_MaxInNotMet(uint256 maxIn, uint256 amountIn);

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
  UFixed32x4 public immutable maxPriceImpactOut;

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
   * @param _maxPriceImpactOut The maximum price impact on token out for a virtual buyback.
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
    uint256 _minK,
    UFixed32x4 _maxPriceImpactOut
  ) {
    if (UFixed32x4.unwrap(_liquidityFraction) == 0) {
      revert LiquidationPair_LiquidityFraction_Zero();
    }
    if (UFixed32x4.unwrap(_swapMultiplier) > 1e4) {
      revert LiquidationPair_SwapMultiplier_GT_One(UFixed32x4.unwrap(_swapMultiplier));
    }
    if (UFixed32x4.unwrap(_liquidityFraction) > 1e4) {
      revert LiquidationPair_LiquidityFraction_GT_One(UFixed32x4.unwrap(_liquidityFraction));
    }
    if (uint256(_virtualReserveIn) * _virtualReserveOut < _minK) {
      revert LiquidationPair_VirtualReserves_LT_MinK(_virtualReserveIn, _virtualReserveOut, _minK);
    }
    if (UFixed32x4.unwrap(_maxPriceImpactOut) >= 1e4) {
      revert LiquidationPair_MaxPriceImpactOut_GTE_Max(UFixed32x4.unwrap(_maxPriceImpactOut), 1e4);
    }
    if (UFixed32x4.unwrap(_maxPriceImpactOut) < 10) {
      revert LiquidationPair_MaxPriceImpactOut_LT_Min(UFixed32x4.unwrap(_maxPriceImpactOut), 10);
    }
    if (_minK == 0) {
      revert LiquidationPair_MinK_Zero();
    }
    if (_virtualReserveIn > type(uint112).max) {
      revert LiquidationPair_VirtualReserveIn_GT_Max(_virtualReserveIn, type(uint112).max);
    }
    if (_virtualReserveOut > type(uint112).max) {
      revert LiquidationPair_VirtualReserveOut_GT_Max(_virtualReserveOut, type(uint112).max);
    }

    source = _source;
    tokenIn = _tokenIn;
    tokenOut = _tokenOut;
    swapMultiplier = _swapMultiplier;
    liquidityFraction = _liquidityFraction;
    virtualReserveIn = _virtualReserveIn;
    virtualReserveOut = _virtualReserveOut;
    minK = _minK;
    maxPriceImpactOut = _maxPriceImpactOut;
  }

  /* ============ External Methods ============ */
  /* ============ Read Methods ============ */

  /**
   * @notice Get the address that will receive `tokenIn`.
   * @return Address of the target
   */
  function target() external view returns (address) {
    return source.targetOf(tokenIn);
  }

  /**
   * @notice Computes the maximum amount of tokens that can be swapped in given the current state of the liquidation pair.
   * @return The maximum amount of tokens that can be swapped in.
   */
  function maxAmountIn() external view returns (uint256) {
    // Calculate the maximum amount of token out available to be swapped out.
    (, uint256 amountIn1) = LiquidatorLib.getVirtualBuybackAmounts(
      _availableReserveOut(),
      virtualReserveOut,
      virtualReserveIn,
      maxPriceImpactOut
    );

    // Calculate how much token in is required to receive that amount of token out.
    return
      LiquidatorLib.computeExactAmountIn(
        virtualReserveIn,
        virtualReserveOut,
        amountIn1,
        amountIn1,
        maxPriceImpactOut
      );
  }

  /**
   * @notice Gets the maximum amount of tokens that can be swapped out from the source.
   * @return The maximum amount of tokens that can be swapped out.
   */
  function maxAmountOut() external view returns (uint256) {
    uint256 availableReserveOut = _availableReserveOut();
    // Calculate the price impact of a virtual buyback of all available tokens.
    (UFixed32x4 priceImpact, ) = LiquidatorLib.calculateVirtualSwapPriceImpact(
      availableReserveOut,
      virtualReserveOut,
      virtualReserveIn
    );

    if (UFixed32x4.unwrap(priceImpact) > UFixed32x4.unwrap(maxPriceImpactOut)) {
      // If the price impact exceeds the maximum, return a restricted amount.
      (uint256 maxAmountOfOut, ) = LiquidatorLib.calculateRestrictedAmounts(
        virtualReserveOut,
        virtualReserveIn,
        maxPriceImpactOut
      );
      return maxAmountOfOut;
    }

    // If the price imact is below the maximum, return the full amount.
    return availableReserveOut;
  }

  /**
   * @notice Computes the virtual reserves post virtual buyback of all available liquidity that has accrued.
   * @return The virtual reserve of the token in.
   * @return The virtual reserve of the token out.
   */
  function nextLiquidationState() external view returns (uint128, uint128, uint256, uint256) {
    return
      LiquidatorLib._virtualBuyback(
        virtualReserveIn,
        virtualReserveOut,
        _availableReserveOut(),
        maxPriceImpactOut
      );
  }

  /**
   * @notice Computes the exact amount of tokens to send in for the given amount of tokens to receive out.
   * @param _amountOut The amount of tokens to receive out.
   * @return The amount of tokens to send in.
   */
  function computeExactAmountIn(uint256 _amountOut) external view returns (uint256) {
    return
      LiquidatorLib.computeExactAmountIn(
        virtualReserveIn,
        virtualReserveOut,
        _availableReserveOut(),
        _amountOut,
        maxPriceImpactOut
      );
  }

  /**
   * @notice Computes the exact amount of tokens to receive out for the given amount of tokens to send in.
   * @param _amountIn The amount of tokens to send in.
   * @return The amount of tokens to receive out.
   */
  function computeExactAmountOut(uint256 _amountIn) external view returns (uint256) {
    return
      LiquidatorLib.computeExactAmountOut(
        virtualReserveIn,
        virtualReserveOut,
        _availableReserveOut(),
        _amountIn,
        maxPriceImpactOut
      );
  }

  /* ============ Write Methods ============ */

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
        minK,
        maxPriceImpactOut
      );

    virtualReserveIn = _virtualReserveIn;
    virtualReserveOut = _virtualReserveOut;

    if (amountOut < _amountOutMin) {
      revert LiquidationPair_MinOutNotMet(_amountOutMin, amountOut);
    }
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
        minK,
        maxPriceImpactOut
      );
    virtualReserveIn = _virtualReserveIn;
    virtualReserveOut = _virtualReserveOut;
    if (amountIn > _amountInMax) {
      revert LiquidationPair_MaxInNotMet(_amountInMax, amountIn);
    }
    _swap(_account, _amountOut, amountIn);

    emit Swapped(_account, amountIn, _amountOut, _virtualReserveIn, _virtualReserveOut);

    return amountIn;
  }

  /* ============ Internal Functions ============ */

  /**
   * @notice Gets the available liquidity that has accrued that users can swap for.
   * @return The available liquidity that users can swap for.
   */
  function _availableReserveOut() internal view returns (uint256) {
    return source.liquidatableBalanceOf(tokenOut);
  }

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
