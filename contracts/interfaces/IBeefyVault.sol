// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.10;

interface IBeefyVaultNative {
  function deposit() external payable;

  function withdraw(uint256 wad) external;
}

interface IBeefyVault {
  function deposit(uint256 _amount) external;

  function withdraw(uint256 _shares) external;

  function getPricePerFullShare() external view returns (uint256);
}
