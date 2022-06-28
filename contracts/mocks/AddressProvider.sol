// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";

import {ILendingPoolAddressesProvider} from "../interfaces/ILendingPoolAddressesProvider.sol";

/**
 * @title LendingPoolAddressesProvider contract
 * @dev Main registry of addresses part of or connected to the protocol, including permissioned roles
 * - Acting also as factory of proxies and admin of those, so with right to change its implementations
 * - Owned by the Sturdy Governance
 * @author Sturdy, inspiration from Aave
 **/
contract LendingPoolAddressesProvider is Ownable, ILendingPoolAddressesProvider {
  bytes32 private constant LENDING_POOL = "LENDING_POOL";
  bytes32 private constant POOL_ADMIN = "POOL_ADMIN";

  mapping(bytes32 => address) private _addresses;

  /**
   * @dev Sets an address for an id replacing the address saved in the addresses map
   * IMPORTANT Use this function carefully, as it will do a hard replacement
   * @param id The id
   * @param newAddress The address to set
   */
  function setAddress(bytes32 id, address newAddress) external payable override onlyOwner {
    _addresses[id] = newAddress;
  }

  /**
   * @dev Returns an address by id
   * @return The address
   */
  function getAddress(bytes32 id) public view override returns (address) {
    return _addresses[id];
  }

  /**
   * @dev Returns the address of the LendingPool proxy
   * @return The LendingPool proxy address
   **/
  function getLendingPool() external view override returns (address) {
    return getAddress(LENDING_POOL);
  }

  function getPoolAdmin() external view override returns (address) {
    return getAddress(POOL_ADMIN);
  }

  function setPoolAdmin(address admin) external payable override onlyOwner {
    _addresses[POOL_ADMIN] = admin;
  }
}
