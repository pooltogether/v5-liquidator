// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import { LiquidationPair } from  "src/LiquidationPair.sol";
import { LiquidationPairFactory } from  "src/LiquidationPairFactory.sol";
import "src/libraries/LiquidatorLib.sol";

import { console } from "forge-std/Test.sol";

contract MockLiquidationPairFactory is LiquidationPairFactory {
    function deletePair(address _tokenIn, address _tokenOut) external {
        delete getPair[_tokenIn][_tokenOut];
    }
}
