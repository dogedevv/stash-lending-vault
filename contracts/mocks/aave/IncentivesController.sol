// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.10;

// import {IAaveV3Incentives} from "../../interfaces/aave/IAaveV3Incentives.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";

contract AaveIncentiveControllerMock {
  mapping(address => uint256) availableRewards;
  address private _owner;

  address public n;

  function getAssetData(address)
    external
    pure
    returns (
      uint256,
      uint256,
      uint256
    )
  {
    return (0, 0, 0);
  }

  function assets(address)
    external
    pure
    returns (
      uint128,
      uint128,
      uint256
    )
  {
    return (0, 0, 0);
  }

  function setClaimer(address, address) external {}

  function getClaimer(address) external pure returns (address) {
    return address(1);
  }

  function configureAssets(address[] calldata, uint256[] calldata) external {}

  function handleAction(
    address,
    uint256,
    uint256
  ) external {}

  function getRewardsBalance(address[] calldata, address) external pure returns (uint256) {
    return 0;
  }

  function getUserRewards(
    address[] calldata assets,
    address user,
    address reward
  ) external view returns (uint256) {
    return availableRewards[user];
  }

  function claimRewards(
    address[] calldata assets,
    uint256 amount,
    address to,
    address reward
  ) external returns (uint256) {
    uint256 amountToWithdraw = amount;
    if (amount == type(uint256).max) {
      amountToWithdraw = availableRewards[to];
    }

    require(IERC20(reward).balanceOf(address(this)) >= amountToWithdraw, "Not enough reward");
    IERC20(reward).transfer(to, amountToWithdraw);
    availableRewards[to] -= amountToWithdraw;
  }

  function setAvailableRewards(address user, uint256 amount) external {
    availableRewards[user] = amount;
  }
}
