// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/benqi/IqiAVAX.sol";
import "../../interfaces/benqi/IqiCompController.sol";
import "../../interfaces/benqi/IqiERC20Delegator.sol";
import "./libs/BenqiLibrary.sol";
import "../../libraries/DexLibrary.sol";
import "../../interfaces/dex/IPair.sol";
import "../../interfaces/dex/IWAVAX.sol";
import "hardhat/console.sol";
import "../../libraries/math/Exponential.sol";

library BenqiStrategy {
  IqiCompController constant COMP_CONTROLLER = IqiCompController(0x486Af39519B4Dc9a7fCcd318217352830E8AD9b4);
  // Qi Token
  address constant QI = 0x8729438EB15e2C8B576fCc6AeCdA6A148776C0F5;
  address constant QI_AVAX = 0x5C0401e81Bc07Ca70fAD469b451682c0d747Ef1c;
  address constant TOKEN_DELEGATOR = 0x76145e99d3F4165A313E8219141ae0D26900B710;
  address constant WAVAX = 0xE530dC2095Ef5653205CF5ea79F8979a7028065c;

  // pangoli qi wavax LP
  address constant QI_WAVAX_LP = 0xE530dC2095Ef5653205CF5ea79F8979a7028065c;

  uint8 constant QI_MARKET_INDEX = 0;
  uint8 constant AVAX_MARKET_INDEX = 1;

  event StratHarvest(address indexed harvester, address underlyingAssetHarvested, uint256 amount);

  function depositAVAX(uint256 amount) internal returns (uint256) {
    uint256 balBefore = IqiAVAX(QI_AVAX).balanceOf(address(this));
    IqiAVAX(QI_AVAX).mint{value: msg.value}();

    uint256 balAfter = IqiAVAX(QI_AVAX).balanceOf(address(this));
    uint256 amountQiAVAX = balAfter - balBefore;
    return amountQiAVAX;
  }

  // redeem qiToken for underlying AVAX
  function redeemAVAX(uint256 qiTokenAmount) internal returns (uint256) {
    uint256 balBefore = address(this).balance;
    require(IqiAVAX(QI_AVAX).redeem(qiTokenAmount) == 0, "BenqiStrategy::failed to redeem");
    uint256 redeemableAmount = address(this).balance - balBefore;
    // console.log("redeemedAvaxAmount", redeemedAvaxAmount);
    // payable(receiver).transfer(redeemedAvaxAmount);
    return redeemableAmount;
  }

  // harvest incentive reward
  function harvest(bool shouldReinvest) internal returns (uint256 harvestedAmount) {
    uint256 rewards = availableIncetiveRewards();
    if (rewards == 0) {
      return 0;
    }

    uint256 avaxBalBefore = address(this).balance;
    uint256 qiBalBefore = IERC20(QI).balanceOf(address(this));

    COMP_CONTROLLER.claimReward(QI_MARKET_INDEX, payable(address(this)));
    COMP_CONTROLLER.claimReward(AVAX_MARKET_INDEX, payable(address(this)));

    uint256 qiReward = IERC20(QI).balanceOf(address(this)) - qiBalBefore;
    uint256 avaxReward = address(this).balance - avaxBalBefore;

    uint256 wavaxBalBefore = IERC20(WAVAX).balanceOf(address(this));

    if (qiReward > 0) {
      // swap QI to WAVAX
      DexLibrary.swap(qiReward, QI, WAVAX, IPair(QI_WAVAX_LP));
    }

    uint256 wavaxGot = IERC20(WAVAX).balanceOf(address(this)) - wavaxBalBefore;
    if (wavaxGot > 0) {
      // withdraw the same amount of WAVAX for underlying AVAX
      IWAVAX(WAVAX).withdraw(wavaxGot);
    }

    uint256 totalWavax = wavaxGot + avaxReward;
    if (shouldReinvest && totalWavax > 0) {
      uint256 balBefore = IqiAVAX(QI_AVAX).balanceOf(address(this));
      depositAVAX(harvestedAmount);
      uint256 balAfter = IqiAVAX(QI_AVAX).balanceOf(address(this));
      uint256 qiAvaxAmount = balAfter - balBefore;
      return qiAvaxAmount;
    }
  }

  function availableIncetiveRewards() internal returns (uint256) {
    uint256 qiIncentivesAmount = COMP_CONTROLLER.rewardAccrued(QI_MARKET_INDEX, address(this));
    uint256 avaxIncentivesAmount = COMP_CONTROLLER.rewardAccrued(AVAX_MARKET_INDEX, address(this));
    // estimate conversion from qi to wavax
    uint256 qiAsWavax = DexLibrary.estimateConversionThroughPair(qiIncentivesAmount, QI, WAVAX, IPair(QI_WAVAX_LP));
    return avaxIncentivesAmount + qiAsWavax;
  }

  // accured rewards for supplying AVAX to the market
  function availableAccuredRewards() internal view returns (uint256) {
    return BenqiLibrary.supplyAccrued(COMP_CONTROLLER, IqiERC20Delegator(QI_AVAX), AVAX_MARKET_INDEX, address(this));
  }

  // estimate neededed amount of bearing token amount to redeem an expected amount of undelrying asset
  function estimateConversionToBearingTokenAmount(uint256 amountUnderlying) internal view returns (uint256 amountBearingToken) {
    Exponential.Exp memory exchangeRate = Exponential.Exp({mantissa: IqiAVAX(QI_AVAX).exchangeRateStored()});
    return Exponential.div_(amountUnderlying, exchangeRate);
  }

  function getBearingToken() internal view returns (address) {
    return QI_AVAX;
  }
}
