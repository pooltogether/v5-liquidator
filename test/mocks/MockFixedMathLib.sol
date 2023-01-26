// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import "../../src/libraries/FixedMathLib.sol";

contract MockFixedMathLib {
    function mul(uint256 a, UFixed32x9 b) external view returns (uint256) {
        return FixedMathLib.mul(a, b);
    }

    function div(uint256 a, UFixed32x9 b) external view returns (uint256) {
        return FixedMathLib.div(a, b);
    }
}
