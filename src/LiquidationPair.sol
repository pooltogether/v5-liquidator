// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "openzeppelin/token/ERC20/IERC20.sol";
import "owner-manager-contracts/Manageable.sol";

import "./libraries/LiquidatorLib.sol";
import "./interfaces/ILiquidationPairYieldSource.sol";

contract LiquidationPair is Manageable {
    // Config
    ILiquidationPairYieldSource public immutable liquidatorYieldSource; // Where to get tokenIn from
    address public immutable target; // Where to send tokenOut
    IERC20 public immutable tokenIn; // Token being sent into the Liquidator Pair by the user(ex. POOL)
    IERC20 public immutable tokenOut; // Token being sent out of the Liquidation Pair to the user(ex. USDC, WETH, etc.)
    uint32 public immutable swapMultiplier; // 9 decimals // TODO: strongly type this
    uint32 public immutable liquidityFraction; // 9 decimals // TODO: strongly type this

    uint256 public virtualReserveIn;
    uint256 public virtualReserveOut;

    event Swapped(
        ILiquidationPairYieldSource indexed prizePool,
        address target,
        IERC20 tokenIn,
        IERC20 indexed tokenOut,
        address indexed account,
        uint256 amountIn,
        uint256 amountOut
    );

    constructor(
        address _owner,
        ILiquidationPairYieldSource _liquidatorYieldSource,
        address _target,
        IERC20 _tokenIn,
        IERC20 _tokenOut,
        uint32 _swapMultiplier,
        uint32 _liquidityFraction,
        uint256 _virtualReserveIn,
        uint256 _virtualReserveOut
    ) Ownable(_owner) {
        require(_liquidityFraction > 0, "liquidityFraction must be greater than 0");
        liquidatorYieldSource = _liquidatorYieldSource;
        target = _target;
        tokenIn = _tokenIn;
        tokenOut = _tokenOut;
        swapMultiplier = _swapMultiplier;
        liquidityFraction = _liquidityFraction;
        virtualReserveIn = _virtualReserveIn;
        virtualReserveOut = _virtualReserveOut;
    }

    function maxAmountOut() external returns (uint256) {
        return _availableReserveOut();
    }

    function _availableReserveOut() internal returns (uint256) {
        return liquidatorYieldSource.availableBalanceOf(address(tokenOut));
    }

    function nextLiquidationState() external returns (uint256, uint256) {
        return LiquidatorLib.virtualBuyback(virtualReserveIn, virtualReserveOut, _availableReserveOut());
    }

    function computeExactAmountIn(uint256 _amountOut) external returns (uint256) {
        return
            LiquidatorLib.computeExactAmountIn(virtualReserveIn, virtualReserveOut, _availableReserveOut(), _amountOut);
    }

    function computeExactAmountOut(uint256 _amountIn) external returns (uint256) {
        return
            LiquidatorLib.computeExactAmountOut(virtualReserveIn, virtualReserveOut, _availableReserveOut(), _amountIn);
    }

    function swapExactAmountIn(uint256 _amountIn, uint256 _amountOutMin) external returns (uint256) {
        uint256 availableBalance = _availableReserveOut();
        (uint256 _virtualReserveIn, uint256 _virtualReserveOut, uint256 amountOut) = LiquidatorLib.swapExactAmountIn(
            virtualReserveIn, virtualReserveOut, availableBalance, _amountIn, swapMultiplier, liquidityFraction
        );
        virtualReserveIn = _virtualReserveIn;
        virtualReserveOut = _virtualReserveOut;
        require(amountOut >= _amountOutMin, "trade does not meet min");
        _swap(msg.sender, amountOut, _amountIn);

        emit Swapped(liquidatorYieldSource, target, tokenIn, tokenOut, msg.sender, _amountIn, amountOut);

        return amountOut;
    }

    function swapExactAmountOut(uint256 _amountOut, uint256 _amountInMax) external returns (uint256) {
        uint256 availableBalance = _availableReserveOut();
        (uint256 _virtualReserveIn, uint256 _virtualReserveOut, uint256 amountIn) = LiquidatorLib.swapExactAmountOut(
            virtualReserveIn, virtualReserveOut, availableBalance, _amountOut, swapMultiplier, liquidityFraction
        );
        virtualReserveIn = _virtualReserveIn;
        virtualReserveOut = _virtualReserveOut;
        require(amountIn <= _amountInMax, "trade does not meet max");
        _swap(msg.sender, _amountOut, amountIn);

        emit Swapped(liquidatorYieldSource, target, tokenIn, tokenOut, msg.sender, amountIn, _amountOut);

        return amountIn;
    }

    function _swap(address _account, uint256 _amountOut, uint256 _amountIn) internal {
        liquidatorYieldSource.transfer(address(tokenOut), _account, _amountOut);
        tokenIn.transferFrom(_account, target, _amountIn);
    }

    function getLiquidationConfig() external view returns (IERC20, IERC20, uint32, uint32) {
        return (tokenIn, tokenOut, swapMultiplier, liquidityFraction);
    }

    function getLiquidationState() external view returns (uint256, uint256) {
        return (virtualReserveIn, virtualReserveOut);
    }
}
