// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../../../libraries/math/Exponential.sol";
import "../../../interfaces/benqi/IqiCompController.sol";
import "../../../interfaces/benqi/IqiERC20Delegator.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// https://github.com/yieldyak/smart-contracts/blob/master/contracts/strategies/benqi/lib/BenqiLibrary.sol

library BenqiLibrary {
  using SafeMath for uint256;

  function calculateReward(
    IqiCompController rewardController,
    IqiERC20Delegator tokenDelegator,
    uint8 tokenIndex,
    address account
  ) internal view returns (uint256) {
    uint256 rewardAccrued = rewardController.rewardAccrued(tokenIndex, account);
    return rewardAccrued.add(supplyAccrued(rewardController, tokenDelegator, tokenIndex, account));
  }

  function supplyAccrued(
    IqiCompController rewardController,
    IqiERC20Delegator tokenDelegator,
    uint8 tokenIndex,
    address account
  ) internal view returns (uint256) {
    Exponential.Double memory supplyIndex = Exponential.Double({mantissa: _supplyIndex(rewardController, tokenDelegator, tokenIndex)});
    Exponential.Double memory supplierIndex = Exponential.Double({mantissa: rewardController.rewardSupplierIndex(tokenIndex, address(tokenDelegator), account)});

    if (supplierIndex.mantissa == 0 && supplyIndex.mantissa > 0) {
      supplierIndex.mantissa = 1e36;
    }
    Exponential.Double memory deltaIndex = supplyIndex.mantissa > 0 ? Exponential.sub_(supplyIndex, supplierIndex) : Exponential.Double({mantissa: 0});
    return Exponential.mul_(tokenDelegator.balanceOf(account), deltaIndex);
  }

  function _supplyIndex(
    IqiCompController rewardController,
    IqiERC20Delegator tokenDelegator,
    uint8 rewardType
  ) private view returns (uint224) {
    (uint224 supplyStateIndex, uint256 supplyStateTimestamp) = rewardController.rewardSupplyState(rewardType, address(tokenDelegator));

    uint256 supplySpeed = rewardController.supplyRewardSpeeds(rewardType, address(tokenDelegator));
    uint256 deltaTimestamps = Exponential.sub_(block.timestamp, uint256(supplyStateTimestamp));
    if (deltaTimestamps > 0 && supplySpeed > 0) {
      uint256 supplyTokens = IERC20(tokenDelegator).totalSupply();
      uint256 qiAccrued = Exponential.mul_(deltaTimestamps, supplySpeed);
      Exponential.Double memory ratio = supplyTokens > 0 ? Exponential.fraction(qiAccrued, supplyTokens) : Exponential.Double({mantissa: 0});
      Exponential.Double memory index = Exponential.add_(Exponential.Double({mantissa: supplyStateIndex}), ratio);
      return Exponential.safe224(index.mantissa, "new index exceeds 224 bits");
    }

    return 0;
  }
}
