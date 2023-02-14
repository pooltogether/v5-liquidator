// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import "openzeppelin/token/ERC20/IERC20.sol";

import "src/interfaces/ILiquidationSource.sol";

import "./MockERC20.sol";

contract MockLiquidationPairYieldSource is ILiquidationSource {
    address internal _target;

    constructor(address target_) {
        _target = target_;
    }

    function accrueYield(address token, uint256 amount) external {
        MockERC20(token).mint(address(this), amount);
    }

    function availableBalanceOf(address token) external view returns (uint256) {
        return MockERC20(token).balanceOf(address(this));
    }

    function liquidate(
        address account,
        address /* tokenIn */,
        uint256 /* amountIn */,
        address tokenOut,
        uint256 amountOut
    ) external returns (bool) {
        MockERC20(tokenOut).transfer(account, amountOut);
        return true;
    }

    function targetOf(address /* token */) external view returns(address) {
        return _target;
    }
}
