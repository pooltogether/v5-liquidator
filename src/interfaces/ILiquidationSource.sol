// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

// NOTE: This should be erc4626 or an adapter to it
interface ILiquidationSource {
    function availableBalanceOf(address token) external returns (uint256);
    function transfer(address token, address target, uint256 amount) external returns (bool);
}
