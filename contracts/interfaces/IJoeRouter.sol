// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.10;
pragma experimental ABIEncoderV2;

interface IJoeRouter {
  function swapExactAVAXForTokens(
    uint256 minAmountOut,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external payable returns (uint256[] memory amounts);

  function swapExactTokensForAVAX(
    uint256 amountIn,
    uint256 minAmountOut,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external returns (uint256[] memory amounts);

  function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 minAmountOut,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external returns (uint256[] memory amounts);

  function swapTokensForExactTokens(
    uint256 amountOut,
    uint256 amountInMax,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external returns (uint256[] memory amounts);

  function swapTokensForExactAVAX(
    uint256 amountOut,
    uint256 amountInMax,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external returns (uint256[] memory amounts);

  function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);

  function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);

  function factory() external pure returns (address);

  // solhint-disable-next-line func-name-mixedcase
  function WAVAX() external pure returns (address);

  function removeLiquidityAVAX(
    address token,
    uint256 liquidity,
    uint256 amountTokenMin,
    uint256 amountAVAXMin,
    address to,
    uint256 deadline
  ) external returns (uint256 amountToken, uint256 amountAVAX);

  function removeLiquidity(
    address tokenA,
    address tokenB,
    uint256 liquidity,
    uint256 amountAMin,
    uint256 amountBMin,
    address to,
    uint256 deadline
  ) external returns (uint256 amountA, uint256 amountB);
}
