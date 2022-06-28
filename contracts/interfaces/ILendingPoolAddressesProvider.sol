// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.10;

/**
 * @title LendingPoolAddressesProvider contract
 * @dev Main registry of addresses part of or connected to the protocol, including permissioned roles
 * - Acting also as factory of proxies and admin of those, so with right to change its implementations
 * - Owned by the Sturdy Governance
 * @author Sturdy, inspiration from Aave
 **/
interface ILendingPoolAddressesProvider {
  function setAddress(bytes32 id, address newAddress) external payable;

  function getAddress(bytes32 id) external view returns (address);

  function getLendingPool() external view returns (address);

  function getPoolAdmin() external view returns (address);

  function setPoolAdmin(address admin) external payable;
}
