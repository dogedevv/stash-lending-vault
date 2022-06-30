// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.10;

interface IWAVAX {
  function deposit() external payable;

  function withdraw(uint256) external;

  function totalSupply() external view returns (uint256);
}
