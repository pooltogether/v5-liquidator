// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import "./LiquidationPair.sol";

/**
 * @title PoolTogether Liquidation Pair Factory
 * @author PoolTogether Inc. Team
 * @notice A facotry to deploy LiquidationPair contracts.
 */
contract LiquidationPairFactory {
  /* ============ Events ============ */

  /**
   * @notice Emitted when a LiquidationPair is deployed.
   * @param liquidator The address of the LiquidationPair.
   * @param source The address of the ILiquidationSource.
   * @param tokenIn The address of the tokenIn.
   * @param tokenOut The address of the tokenOut.
   * @param swapMultiplier The swap multiplier.
   * @param liquidityFraction The liquidity fraction.
   * @param virtualReserveIn The initial virtual reserve in.
   * @param virtualReserveOut The initial virtual reserve out.
   * @param minK The minimum K value.
   */
  event PairCreated(
    LiquidationPair indexed liquidator,
    ILiquidationSource indexed source,
    address indexed tokenIn,
    address tokenOut,
    UFixed32x4 swapMultiplier,
    UFixed32x4 liquidityFraction,
    uint128 virtualReserveIn,
    uint128 virtualReserveOut,
    uint256 minK
  );

  /* ============ Variables ============ */
  LiquidationPair[] public allPairs;

  /* ============ Mappings ============ */

  /**
   * @notice Mapping to verify if a LiquidationPair has been deployed via this factory.
   * @dev LiquidationPair address => boolean
   */
  mapping(LiquidationPair => bool) public deployedPairs;

  /* ============ External Functions ============ */

  /**
   * @notice Deploys a new LiquidationPair contract.
   * @param _source The source of yield for hte liquidation pair
   * @param _tokenIn The token to be swapped in.
   * @param _tokenOut The token to be swapped out.
   * @param _swapMultiplier The swap multiplier.
   * @param _liquidityFraction The liquidity fraction to be applied after swapping.
   * @param _virtualReserveIn The initial virtual reserve of token in.
   * @param _virtualReserveOut The initial virtual reserve of token out.
   * @param _mink The minimum K value.
   */
  function createPair(
    ILiquidationSource _source,
    address _tokenIn,
    address _tokenOut,
    UFixed32x4 _swapMultiplier,
    UFixed32x4 _liquidityFraction,
    uint128 _virtualReserveIn,
    uint128 _virtualReserveOut,
    uint256 _mink
  ) external returns (LiquidationPair) {
    LiquidationPair _liquidationPair = new LiquidationPair(
      _source,
      _tokenIn,
      _tokenOut,
      _swapMultiplier,
      _liquidityFraction,
      _virtualReserveIn,
      _virtualReserveOut,
      _mink
    );

    allPairs.push(_liquidationPair);
    deployedPairs[_liquidationPair] = true;

    emit PairCreated(
      _liquidationPair,
      _source,
      _tokenIn,
      _tokenOut,
      _swapMultiplier,
      _liquidityFraction,
      _virtualReserveIn,
      _virtualReserveOut,
      _mink
    );

    return _liquidationPair;
  }

  /**
   * @notice Total number of LiquidationPair deployed by this factory.
   * @return Number of LiquidationPair deployed by this factory.
   */
  function totalPairs() external view returns (uint256) {
    return allPairs.length;
  }
}
