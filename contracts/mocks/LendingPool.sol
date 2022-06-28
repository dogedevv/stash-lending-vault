// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "hardhat/console.sol";

contract LendingPoolMock is ERC20 {
  uint256 totalBalanceOfAssetPair = 0;

  constructor() ERC20("mockAToken", "aToken") {}

  function deposit(
    address asset,
    uint256 amount,
    address onBehalfOf,
    uint16 referralCode
  ) external {
    IERC20(asset).transferFrom(msg.sender, address(this), amount);
    _mint(onBehalfOf, amount);
  }

  function depositYield(address asset, uint256 amount) external {
    IERC20(asset).transferFrom(msg.sender, address(this), amount);
  }

  function withdrawFrom(
    address asset,
    uint256 amount,
    address from,
    address to
  ) external returns (uint256) {
    IERC20(asset).transfer(to, amount);

    return amount;
  }

  function getTotalBalanceOfAssetPair(address asset) external returns (uint256, uint256) {
    return (totalBalanceOfAssetPair, 0);
  }

  function setTotalBalanceOfAssetPair(address asset, uint256 amount) external {
    IERC20(asset).transferFrom(msg.sender, address(this), amount);
    console.log("balance setTotalBalanceOfAssetPair", IERC20(asset).balanceOf(address(this)));
    console.log("assetttt setTotalBalanceOfAssetPair", asset);

    totalBalanceOfAssetPair = amount;
  }

  function getYield(address asset, uint256 amount) external {
    console.log("inside get yield");
    console.log("assetttt", asset);
    console.log("balance", IERC20(asset).balanceOf(address(this)));
    IERC20(asset).transfer(msg.sender, amount);
  }
}
