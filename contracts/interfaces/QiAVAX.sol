// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.10;

interface QiAVAX {
  function mint() external payable;

  function transfer(address, uint256) external returns (bool);
}
