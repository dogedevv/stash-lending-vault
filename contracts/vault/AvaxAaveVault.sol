pragma solidity ^0.8.10;

import {GeneralVault} from "./GeneralVault.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Errors} from "../libraries/helpers/Errors.sol";
import {ILendingPoolAddressesProvider} from "../interfaces/ILendingPoolAddressesProvider.sol";
import {PercentageMath} from "../libraries/math/PercentageMath.sol";
import {IWAVAX} from "../interfaces/IWAVAX.sol";
import {AaveStrategy} from "./strategies/AaveStrategy.sol";
import {BenqiStrategy} from "./strategies/BenqiStrategy.sol";
import {ILendingPool} from "../interfaces/ILendingPool.sol";
import "hardhat/console.sol";

/**
 * @title AVAX Vault using Aave strategy
 * @author DeDe
 **/
contract AvaxAaveVault is GeneralVault {
  using SafeERC20 for IERC20;
  using PercentageMath for uint256;

  address public constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

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
    uint256 withdrawalAmount = _strategyWithdraw(yieldAmount, false, address(this));

    address yieldManager = provider.getAddress("YIELD_MANAGER");
    if (fee > 0) {
      uint256 treasuryAmount = withdrawalAmount.percentMul(fee);
      IERC20(WAVAX).safeTransfer(_treasuryAddress, treasuryAmount);
      withdrawalAmount -= treasuryAmount;
    }

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

  function _strategyDeposit(uint256 amount, bool isNativeDeposit) private returns (uint256 bearingTokenReceivedAmount) {
    if (isNativeDeposit) {
      // deposit AVAX
      AaveStrategy.depositAVAX(amount);
      return amount;
    } else {
      // deposit WAVAX
      AaveStrategy.deposit(WAVAX, amount);
      return amount;
    }
  }

  function _strategyHarvest() private returns (uint256 harvestedAmount) {
    return AaveStrategy.harvest(WAVAX, true);
  }

  function _strategyWithdraw(
    uint256 amount,
    bool isNativeWithdrawal,
    address receiver
  ) private returns (uint256) {
    if (isNativeWithdrawal) {
      return AaveStrategy.withdrawAVAX(amount, receiver);
    }

    return AaveStrategy.withdraw(WAVAX, amount, receiver);
  }

  function getBearingToken() public view returns (address) {
    return AaveStrategy.getBearingToken(WAVAX);
  }

  /**
   * @dev Deposit to yield pool based on strategy and receive stAsset
   */
  function _depositToYieldPool(address _asset, uint256 _amount) internal override returns (address, uint256) {
    ILendingPoolAddressesProvider provider = _addressesProvider;
    address lendingPool = provider.getLendingPool();
    require(lendingPool != address(0), Errors.VT_INVALID_CONFIGURATION);

    // Check if this is an AVAX deposit
    bool isNativeDeposit = (_asset == address(0));
    if (!isNativeDeposit) {
      // transfer WAVAX from the user to the vault
      require(_asset == WAVAX, Errors.VT_COLLATERAL_DEPOSIT_INVALID);
      IERC20(WAVAX).safeTransferFrom(msg.sender, address(this), _amount);
    }

    uint256 bearingTokenReceivedAmount = _strategyDeposit(_amount, isNativeDeposit);

    address bearingToken = getBearingToken();
    if (shouldHarvestOnDeposit) {
      uint256 harvestedAmount = _strategyHarvest();
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

    address bearingToken = getBearingToken();
    // return the same amount for AAVE strategy
    return (bearingToken, _amount);
  }

  /**
   * @dev Withdraw from yield pool based on strategy with stAsset and deliver asset
   */
  function _withdrawFromYieldPool(
    address _asset,
    uint256 _amount,
    address _to
  ) internal override returns (uint256) {
    ILendingPoolAddressesProvider provider = _addressesProvider;
    // address LIDO = provider.getAddress("LIDO");
    require(_to != address(0), Errors.VT_COLLATERAL_WITHDRAW_INVALID);
    // check if AVAX withdrawal
    bool isNativeWithdrawal = _asset == address(0);
    return _strategyWithdraw(_amount, isNativeWithdrawal, _to);
  }

  function _getYieldAmount(address _stAsset) internal view override returns (uint256) {
    (uint256 stAssetBalance, uint256 aTokenBalance) = ILendingPool(_addressesProvider.getLendingPool()).getTotalBalanceOfAssetPair(_stAsset);
    if (stAssetBalance > aTokenBalance) return stAssetBalance - aTokenBalance;
    return 0;
  }
}
