// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

type UFixed32x4 is uint32;

/// @notice Emitted when variable `a` is greater than the max uint224
/// @param a Variable `a`
error FixedMathLib_A_GT_MaxUint224(uint256 a);

/// @notice Emitted when variable `b` is equal to zero
error FixedMathLib_B_Zero();

/**
 * @title FixedMathLib
 * @author PoolTogether Inc. Team
 * @notice A minimal library to do fixed point operations with 4 decimals of precision.
 */
library FixedMathLib {
  uint256 public constant multiplier = 1e4;

  /**
   * @notice Multiply a uint256 by a UFixed32x4.
   * @param a The uint256 to multiply.
   * @param b The UFixed32x4 to multiply.
   * @return The product of a and b.
   */
  function mul(uint256 a, UFixed32x4 b) internal pure returns (uint256) {
    if (a > type(uint224).max) revert FixedMathLib_A_GT_MaxUint224(a);
    return (a * UFixed32x4.unwrap(b)) / multiplier;
  }

  /**
   * @notice Divide a uint256 by a UFixed32x4.
   * @param a The uint256 to divide.
   * @param b The UFixed32x4 to divide.
   * @return The quotient of a and b.
   */
  function div(uint256 a, UFixed32x4 b) internal pure returns (uint256) {
    if (UFixed32x4.unwrap(b) == 0) revert FixedMathLib_B_Zero();
    if (a > type(uint224).max) revert FixedMathLib_A_GT_MaxUint224(a);
    return (a * multiplier) / UFixed32x4.unwrap(b);
  }
}
