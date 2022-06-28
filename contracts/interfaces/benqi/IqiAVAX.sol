// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

interface IqiAVAX {
  function mint() external payable;

  function redeem(uint256 redeemTokens) external returns (uint256);

  function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

  function exchangeRateStored() external view returns (uint256);

  function balanceOfUnderlying(address owner) external view returns (uint256);

  function balanceOf(address owner) external view returns (uint256);
}
