// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../../src/libraries/FixedMathLib.sol";

// Note: Need to store the results from the library in a variable to be picked up by forge coverage
// See: https://github.com/foundry-rs/foundry/pull/3128#issuecomment-1241245086

contract MockFixedMathLib {
  function mul(uint256 a, UFixed32x4 b) external pure returns (uint256) {
    uint256 result = FixedMathLib.mul(a, b);
    return result;
  }

  function div(uint256 a, UFixed32x4 b) external pure returns (uint256) {
    uint256 result = FixedMathLib.div(a, b);
    return result;
  }
}
