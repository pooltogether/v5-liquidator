// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "openzeppelin/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import { LiquidationPair } from "./LiquidationPair.sol";
import { LiquidationPairFactory } from "./LiquidationPairFactory.sol";

/**
 * @title PoolTogether Liquidation Router
 * @author PoolTogether Inc. Team
 * @notice A router to swap tokens via LiquidationPair contracts.
 */
contract LiquidationRouter {
  using SafeERC20 for IERC20;

  /* ============ Events ============ */

  /**
   * @notice Emitted when a LiquidationRouter is created.
   * @param liquidationPairFactory The address of the LiquidationPairFactory.
   */
  event LiquidationRouterCreated(LiquidationPairFactory indexed liquidationPairFactory);

  /* ============ Variables ============ */
  LiquidationPairFactory internal immutable _liquidationPairFactory;

  /* ============ Constructor ============ */

  /**
   * @notice Creates a new LiquidationRouter.
   * @param liquidationPairFactory_ The address of the LiquidationPairFactory.
   */
  constructor(LiquidationPairFactory liquidationPairFactory_) {
    require(address(liquidationPairFactory_) != address(0), "LR/LPF-not-address-zero");
    _liquidationPairFactory = liquidationPairFactory_;

    emit LiquidationRouterCreated(liquidationPairFactory_);
  }

  /* ============ Modifiers ============ */

  /**
   * @notice Checks if the LiquidationPair is deployed via the LiquidationPairFactory.
   * @param _liquidationPair The LiquidationPair to check.
   */
  modifier onlyTrustedLiquidationPair(LiquidationPair _liquidationPair) {
    require(_liquidationPairFactory.deployedPairs(_liquidationPair), "LR/LP-not-from-LPF");
    _;
  }

  /* ============ External Methods ============ */

  /**
   * @notice Swaps an exact amount of token in for a minimum amount of token out.
   * @dev The caller must approve the LiquidationPairRouter to transfer the token in.
   * @param _liquidationPair The LiquidationPair to use.
   * @param _receiver The address to receive the swapped tokens.
   * @param _amountIn The amount of token in to swap in.
   * @param _amountOutMin The minimum amount of token out to receive.
   * @return The amount of token out received.
   */
  function swapExactAmountIn(
    LiquidationPair _liquidationPair,
    address _receiver,
    uint256 _amountIn,
    uint256 _amountOutMin
  ) external onlyTrustedLiquidationPair(_liquidationPair) returns (uint256) {
    IERC20(_liquidationPair.tokenIn()).safeTransferFrom(
      msg.sender,
      _liquidationPair.target(),
      _amountIn
    );

    return _liquidationPair.swapExactAmountIn(_receiver, _amountIn, _amountOutMin);
  }

  /**
   * @notice Swaps a maximum amount of token in for an exact amount of token out.
   * @dev The caller must approve the LiquidationPairRouter to transfer the token in.
   * @param _liquidationPair The LiquidationPair to use.
   * @param _receiver The address to receive the swapped tokens.
   * @param _amountOut The amount of token out to receive.
   * @param _amountInMax  The maximum amount of token in to swap in.
   * @return The amount of token in swapped.
   */
  function swapExactAmountOut(
    LiquidationPair _liquidationPair,
    address _receiver,
    uint256 _amountOut,
    uint256 _amountInMax
  ) external onlyTrustedLiquidationPair(_liquidationPair) returns (uint256) {
    IERC20(_liquidationPair.tokenIn()).safeTransferFrom(
      msg.sender,
      _liquidationPair.target(),
      _liquidationPair.computeExactAmountIn(_amountOut)
    );

    return _liquidationPair.swapExactAmountOut(_receiver, _amountOut, _amountInMax);
  }
}
