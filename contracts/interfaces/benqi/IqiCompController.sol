// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

interface IqiCompController {
  /*
   * @param rewardType 0 means Qi, 1 means Avax
   * @param holder The addresses to claim reward for
   */
  function rewardAccrued(uint8 rewardType, address holder) external view returns (uint256);

  function claimReward(uint8 rewardType, address payable holder) external;

  function rewardSupplierIndex(
    uint8 rewardType,
    address qiContractAddress,
    address holder
  ) external view returns (uint256 supplierIndex);

  function rewardSupplyState(uint8 rewardType, address holder) external view returns (uint224 index, uint32 timestamp);

  function supplyRewardSpeeds(uint8 rewardType, address qiToken) external view returns (uint256);
}
