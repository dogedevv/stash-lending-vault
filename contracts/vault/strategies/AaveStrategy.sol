// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/aave/IAaveV3Incentives.sol";
import "../../interfaces/aave/IDataProvider.sol";
import "../../interfaces/aave/ILendingPool.sol";
import "../../interfaces/aave/IAToken.sol";
import "../../interfaces/aave/IWETHGateway.sol";

library AaveStrategy {
  // Aaave contracts
  address constant DATA_PROVIDER = 0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654;
  address constant LENDING_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
  address constant INCENTIVES_CONTROLLER = 0x929EC64c34a17401F460460D4B9390518E5B473e;
  address constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
  address constant WETH_GATEWAY = 0xa938d8536aEed1Bd48f548380394Ab30Aa11B00E;

  event StratHarvest(address indexed harvester, address underlyingAssetHarvested, uint256 amount);

  function deposit(address asset, uint256 amount) internal {
    IERC20(asset).approve(LENDING_POOL, 0);
    IERC20(asset).approve(LENDING_POOL, amount);

    ILendingPool(LENDING_POOL).deposit(asset, amount, address(this), 0);
  }

  function depositAVAX(uint256 amount) internal {
    IWETHGateway(WETH_GATEWAY).depositETH{value: amount}(LENDING_POOL, address(this), 0);
  }

  // withraw an amount of underlying asset
  function withdraw(
    address asset,
    uint256 amount,
    address receiver
  ) internal returns (uint256) {
    return ILendingPool(LENDING_POOL).withdraw(asset, amount, receiver);
  }

  function withdrawAVAX(uint256 amount, address receiver) internal returns (uint256) {
    address bearingToken = getBearingToken();
    IERC20(bearingToken).approve(WETH_GATEWAY, 0);
    IERC20(bearingToken).approve(WETH_GATEWAY, amount);

    IWETHGateway(WETH_GATEWAY).withdrawETH(LENDING_POOL, amount, receiver);
    return amount;
  }

  function withdrawAll(address asset) internal returns (uint256) {
    uint256 assetBalBefore = IERC20(asset).balanceOf(address(this));
    ILendingPool(LENDING_POOL).withdraw(asset, type(uint256).max, address(this));
    uint256 withdrawAmount = IERC20(asset).balanceOf(address(this)) - assetBalBefore;
    return withdrawAmount;
  }

  function harvest(bool shouldReinvest) internal returns (uint256 harvestedAmount) {
    address bearingToken = getBearingToken();
    uint256 rewards = availableRewards(bearingToken, address(this));

    if (rewards == 0) {
      return 0;
    }

    uint256 beforeBal = IERC20(WAVAX).balanceOf(address(this));
    address[] memory assets = new address[](1);
    assets[0] = bearingToken;

    // claim WAVAX reward
    IAaveV3Incentives(INCENTIVES_CONTROLLER).claimRewards(assets, type(uint256).max, address(this), WAVAX);
    uint256 afterBal = IERC20(WAVAX).balanceOf(address(this));
    uint256 rewardHarvestedAmount = afterBal - beforeBal;

    if (rewardHarvestedAmount > 0) {
      if (shouldReinvest) {
        // redeposit and get bearing tokens
        deposit(WAVAX, rewardHarvestedAmount);
      }

      emit StratHarvest(msg.sender, WAVAX, rewardHarvestedAmount);
    }

    return rewardHarvestedAmount;
  }

  function availableRewards(address aToken, address ofAddress) internal view returns (uint256) {
    address[] memory assets = new address[](1);
    assets[0] = aToken;
    // get WAVAX reward amount
    return IAaveV3Incentives(INCENTIVES_CONTROLLER).getUserRewards(assets, ofAddress, WAVAX);
  }

  function getBearingToken() internal view returns (address) {
    (address aToken, , ) = IDataProvider(DATA_PROVIDER).getReserveTokensAddresses(WAVAX);
    return aToken;
  }
}
