// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "openzeppelin/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import { LiquidationPair } from "./LiquidationPair.sol";
import { LiquidationPairFactory } from "./LiquidationPairFactory.sol";

contract LiquidationRouter {
  using SafeERC20 for IERC20;

  /* ============ Events ============ */
  event LiquidationRouterCreated(
    LiquidationPairFactory indexed liquidationPairFactory
  );

  /* ============ Variables ============ */
  LiquidationPairFactory internal immutable _liquidationPairFactory;

  /* ============ Constructor ============ */
  constructor(
    LiquidationPairFactory liquidationPairFactory_
  ) {
    require(address(liquidationPairFactory_) != address(0), "LR/LPF-not-address-zero");
    _liquidationPairFactory = liquidationPairFactory_;

    emit LiquidationRouterCreated(liquidationPairFactory_);
  }

  function swapExactAmountIn(
    address[2] calldata _pair,
    address _account,
    uint256 _amountIn,
    uint256 _amountOutMin
  ) external returns (uint256) {
    LiquidationPair _liquidationPair = _liquidationPairFactory.getPair(_pair[0], _pair[1]);

    IERC20(_pair[0]).safeTransferFrom(_account, _liquidationPair.target(), _amountIn);

    return _liquidationPair.swapExactAmountIn(_account, _amountIn, _amountOutMin);
  }

  function swapExactAmountOut(
    address[2] calldata _pair,
    address _account,
    uint256 _amountOut,
    uint256 _amountInMax
  ) external returns (uint256) {
    LiquidationPair _liquidationPair = _liquidationPairFactory.getPair(_pair[0], _pair[1]);

    IERC20(_pair[0]).safeTransferFrom(
      _account,
      _liquidationPair.target(),
      _liquidationPair.computeExactAmountIn(_amountOut)
    );

    return _liquidationPair.swapExactAmountOut(_account, _amountOut, _amountInMax);
  }
}
