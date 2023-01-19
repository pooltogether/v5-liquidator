// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

type UFixed32x9 is uint32;

/// A minimal library to do fixed point operations on UFixed32x9.
library FixedMathLib {
    uint256 constant multiplier = 1e9;

    function mul(uint256 a, UFixed32x9 b) internal pure returns (uint256) {
        require(a <= type(uint224).max, "FixedMathLib/a-less-than-224-bits");
        return a * UFixed32x9.unwrap(b) / multiplier;
    }

    function div(uint256 a, UFixed32x9 b) internal pure returns (uint256) {
        require(UFixed32x9.unwrap(b) > 0, "FixedMathLib/b-greater-than-zero");
        require(a <= type(uint224).max, "FixedMathLib/a-less-than-224-bits");
        return a * multiplier / UFixed32x9.unwrap(b);
    }
}
