pragma solidity ^0.8.10;

import {GeneralVault} from "./GeneralVault.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Errors} from "../libraries/helpers/Errors.sol";
import {ILendingPoolAddressesProvider} from "../interfaces/ILendingPoolAddressesProvider.sol";
import {PercentageMath} from "../libraries/math/PercentageMath.sol";
import {IWAVAX} from "../interfaces/IWAVAX.sol";
import {BenqiStrategy} from "./strategies/BenqiStrategy.sol";
import {ILendingPool} from "../interfaces/ILendingPool.sol";
import "hardhat/console.sol";

/**
 * @title AVAX Vault
 * @author DeDe
 **/
contract AvaxBenqiVault is GeneralVault {
  using SafeERC20 for IERC20;
  using PercentageMath for uint256;

  address public constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

  mapping(address => uint256) private _principal;

  /**
   * @dev Receive AVAX
   */
  receive() external payable {}

  /**
   * @dev Grab excess stETH which was from rebasing on Lido
   *  And convert stETH -> ETH -> asset, deposit to pool
   */
  function processYield() external override {
    ILendingPoolAddressesProvider provider = _addressesProvider;
    address bearingToken = getBearingToken();
    uint256 yieldAmount = _getYield(bearingToken);
    uint256 fee = _vaultFee;

    uint256 withdrawalAmount = BenqiStrategy.redeemAVAX(yieldAmount);
    IWAVAX(WAVAX).deposit{value: withdrawalAmount}();

    if (fee > 0) {
      uint256 treasuryAmount = withdrawalAmount.percentMul(fee);
      IERC20(WAVAX).safeTransfer(_treasuryAddress, treasuryAmount);
      withdrawalAmount -= treasuryAmount;
    }

    address yieldManager = provider.getAddress("YIELD_MANAGER");
    IERC20(WAVAX).safeTransfer(yieldManager, withdrawalAmount);
    emit ProcessYield(WAVAX, withdrawalAmount);
  }

  /**
   * @dev Get yield amount based on strategy
   */
  function getYieldAmount() external view returns (uint256) {
    return _getYieldAmount(getBearingToken());
  }

  /**
   * @dev Get price per share based on yield strategy
   */
  function pricePerShare() external pure override returns (uint256) {
    return 1e18;
  }

  function getBearingToken() public view returns (address) {
    // return benqi
    return BenqiStrategy.getBearingToken();
  }

  /**
   * @dev Deposit to yield pool based on strategy and receive stAsset
   */
  function _depositToYieldPool(address _asset, uint256 _amount) internal override returns (address, uint256) {
    ILendingPoolAddressesProvider provider = _addressesProvider;
    address lendingPool = provider.getLendingPool();
    require(lendingPool != address(0), Errors.VT_INVALID_CONFIGURATION);

    // Check if this is an AVAX deposit
    // if (!isNativeDeposit) {
    //   // transfer WAVAX from the user to the vault
    //   require(_asset == WAVAX, Errors.VT_COLLATERAL_DEPOSIT_INVALID);
    //   IERC20(WAVAX).safeTransferFrom(msg.sender, address(this), _amount);
    // }

    _principal[msg.sender] += _amount;
    address bearingToken = getBearingToken();
    uint256 bearingTokenReceivedAmount = BenqiStrategy.depositAVAX(_amount);

    if (shouldHarvestOnDeposit) {
      uint256 harvestedAmount = BenqiStrategy.harvest(true);
      if (harvestedAmount > 0) {
        // depoist harvested bearing token to the lending pool
        IERC20(bearingToken).approve(lendingPool, 0);
        IERC20(bearingToken).approve(lendingPool, bearingTokenReceivedAmount + harvestedAmount);

        _depositYield(bearingToken, harvestedAmount);
        return (bearingToken, bearingTokenReceivedAmount);
      }
    }

    IERC20(bearingToken).approve(lendingPool, 0);
    IERC20(bearingToken).approve(lendingPool, bearingTokenReceivedAmount);
    return (bearingToken, bearingTokenReceivedAmount);
  }

  /**
   * @dev Get Withdrawal amount of stAsset based on strategy
   */
  function _getWithdrawalAmount(address _asset, uint256 _amount) internal view override returns (address, uint256) {
    // address LIDO = _addressesProvider.getAddress("LIDO");
    require(_asset == WAVAX || _asset == address(0), Errors.VT_COLLATERAL_WITHDRAW_INVALID);
    // // In this vault, return same amount of asset

    // case benqi strategy, convert underlying asset (AVAX) amount to bearing token amount
    return (getBearingToken(), BenqiStrategy.estimateConversionToBearingTokenAmount(_amount));
  }

  /**
   * @dev Withdraw from yield pool based on strategy with stAsset and deliver asset
   */
  function _withdrawFromYieldPool(
    address _asset,
    uint256 _bearingTokenAmount,
    address _to
  ) internal override returns (uint256) {
    ILendingPoolAddressesProvider provider = _addressesProvider;
    // address LIDO = provider.getAddress("LIDO");
    require(_to != address(0), Errors.VT_COLLATERAL_WITHDRAW_INVALID);
    // check if AVAX withdrawal
    uint256 redeemedAmount = BenqiStrategy.redeemAVAX(_bearingTokenAmount);
    uint256 principal = _principal[msg.sender];
    uint256 receivableAmount = redeemedAmount > principal ? principal : redeemedAmount;
    _principal[msg.sender] -= receivableAmount;
    payable(_to).transfer(receivableAmount);
    return receivableAmount;
  }

  function _getYieldAmount(address _stAsset) internal view override returns (uint256) {
    (uint256 stAssetBalance, uint256 aTokenBalance) = ILendingPool(_addressesProvider.getLendingPool()).getTotalBalanceOfAssetPair(_stAsset);
    if (stAssetBalance > aTokenBalance) return stAssetBalance - aTokenBalance;

    return 0;
  }

  function _safeTransferAVAX(address to, uint256 value) internal {
    (bool success, ) = to.call{value: value}(new bytes(0));
    require(success, "TransferHelper::safeTransferAVAX: AVAX transfer failed");
  }
}
