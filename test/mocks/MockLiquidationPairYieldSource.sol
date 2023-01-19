// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import "openzeppelin/token/ERC20/IERC20.sol";

import "../../src/interfaces/ILiquidationSource.sol";
import "./MockERC20.sol";

contract MockLiquidationPairYieldSource is ILiquidationSource {
    constructor() {}

    function availableBalanceOf(address token) external view returns (uint256) {
        return MockERC20(token).balanceOf(address(this));
    }

    function transfer(address token, address to, uint256 amount) external returns (bool) {
        return MockERC20(token).transfer(to, amount);
    }

    function accrueYield(address token, uint256 amount) external {
        MockERC20(token).mint(address(this), amount);
    }
}
