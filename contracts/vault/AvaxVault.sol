// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/math/PercentageMath.sol";
import "../interfaces/IWAVAX.sol";

import {BenqiStrategy} from "./strategies/BenqiStrategy.sol";
import {AaveStrategy} from "./strategies/AaveStrategy.sol";
import "hardhat/console.sol";

/**
 * @title GeneralVault
 * @notice Basic feature of vault
 * @author Dede
 **/

contract AvaxVault is Initializable, OwnableUpgradeable, ERC20Upgradeable, ERC20BurnableUpgradeable {
  using PercentageMath for uint256;
  using SafeERC20 for IERC20;

  event ProcessYield(address indexed asset, uint256 yieldAmount);
  event SetTreasuryInfo(address indexed treasuryAddress, uint256 fee);
  event Deposit(address indexed from, uint256 amount);
  event Withdraw(address indexed to, uint256 amount);
  event Harvest(address indexed asset, uint256 amount);
  event SetKeeper(address keeper, bool flag);
  event SetStrategy(Strategy strategy);

  enum Strategy {
    AAVE,
    BENQI
  }

  uint256 private constant VAULT_VERSION = 0x1;
  address public constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

  // vault fee 20%
  uint256 private _vaultFee;
  address private _treasuryAddress;
  Strategy private _currentStrategy;
  bool private _shouldHarvestOnDeposit;
  mapping(address => bool) private _whitelist;
  mapping(address => bool) private _isKeeper;

  modifier onlyWhitelisted() {
    require(_whitelist[msg.sender], "CALLER_ADDRESS_NOT_WHITELISTED");
    _;
  }

  /**
   * @dev Function is invoked by the proxy contract when the Vault contract is deployed.
   **/
  function initialize() external initializer {
    __ERC20_init(string(abi.encodePacked("Dede ", IERC20Metadata(WAVAX).name(), " Vault")), string(abi.encodePacked("v", IERC20Metadata(WAVAX).symbol())));
    __Ownable_init();

    _shouldHarvestOnDeposit = true;
  }

  function getVersion() internal pure returns (uint256) {
    return VAULT_VERSION;
  }

  function _strategyDeposit(uint256 amount) private {
    if (_currentStrategy == Strategy.AAVE) {
      AaveStrategy.deposit(WAVAX, amount);
      return;
    }

    IWAVAX(WAVAX).withdraw(amount);
    // deposit native AVAX
    BenqiStrategy.deposit(amount);
  }

  function _strategyWithdraw(uint256 amount) private {
    if (_currentStrategy == Strategy.AAVE) {
      AaveStrategy.withdraw(WAVAX, amount, msg.sender);
      return;
    }

    console.log("strategy withdraw benqi");
    // convert underlying asset amount to bearing token amount
    uint256 bearingTokenAmount = BenqiStrategy.estimateConversionToBearingTokenAmount(amount);
    uint256 amountAVAX = BenqiStrategy.redeem(bearingTokenAmount);
    console.log("amountAVAX", amountAVAX);
    IWAVAX(WAVAX).deposit{value: amountAVAX}();
    console.log("transfer");
    IERC20(WAVAX).transfer(msg.sender, amountAVAX);
  }

  function _strategyHarvest() private returns (uint256) {
    if (_currentStrategy == Strategy.AAVE) {
      return AaveStrategy.harvest(true);
    }

    return BenqiStrategy.harvest(true);
  }

  function getBearingToken() public view returns (address) {
    if (_currentStrategy == Strategy.AAVE) {
      return AaveStrategy.getBearingToken();
    }

    return BenqiStrategy.getBearingToken();
  }

  function deposit(uint256 amount) external onlyWhitelisted {
    IERC20(WAVAX).transferFrom(msg.sender, address(this), amount);
    _strategyDeposit(amount);

    if (_shouldHarvestOnDeposit) {
      address bearingToken = getBearingToken();
      uint256 harvestedAmount = _strategyHarvest();
      emit Harvest(bearingToken, harvestedAmount);
    }

    // mint the same underlying token amount to the depositor
    _mint(msg.sender, amount);
    emit Deposit(msg.sender, amount);
  }

  function withdraw(uint256 amount) external onlyWhitelisted {
    _burn(msg.sender, amount);
    _strategyWithdraw(amount);
    emit Withdraw(msg.sender, amount);
  }

  function getYieldAmount() public returns (uint256) {
    if (_currentStrategy == Strategy.AAVE) {
      address bearingToken = AaveStrategy.getBearingToken();
      uint256 bearingBal = IERC20(bearingToken).balanceOf(address(this));
      uint256 totalSupply = totalSupply();
      return bearingBal > totalSupply ? bearingBal - totalSupply : 0;
    } else {
      // benqi strategy
      uint256 bal = BenqiStrategy.balanceOfUnderlying(address(this));
      uint256 totalSupply = totalSupply();
      return bal > totalSupply ? bal - totalSupply : 0;
    }
  }

  function balanceOfUnderlying() public returns (uint256) {
    if (_currentStrategy == Strategy.AAVE) {
      return IERC20(AaveStrategy.getBearingToken()).balanceOf(address(this));
    }

    return BenqiStrategy.balanceOfUnderlying(address(this));
  }

  function _redeemYield(uint256 yieldAmount) internal returns (uint256) {
    if (_currentStrategy == Strategy.AAVE) {
      uint256 amountWAVAX = AaveStrategy.withdraw(WAVAX, yieldAmount, address(this));
      return amountWAVAX;
    }

    uint256 balBefore = address(this).balance;
    BenqiStrategy.redeemUnderlying(yieldAmount);
    uint256 amountAVAX = address(this).balance - balBefore;
    // convert AVAX in to WAVAX
    IWAVAX(WAVAX).deposit{value: amountAVAX}();
    return amountAVAX;
  }

  /**
   * @dev Grab excess stETH which was from rebasing on Lido
   *  And convert stETH -> ETH -> asset, deposit to pool
   */
  function claimYield() external {
    require(_isKeeper[msg.sender], "CALLER_IS_NOT_A_KEEPER");

    uint256 fee = _vaultFee;
    uint256 yieldAmount = getYieldAmount();

    uint256 redeemedAmount = _redeemYield(yieldAmount);
    if (fee > 0) {
      uint256 treasuryAmount = redeemedAmount.percentMul(fee);
      IERC20(WAVAX).safeTransfer(_treasuryAddress, treasuryAmount);
      redeemedAmount -= treasuryAmount;
    }

    IERC20(WAVAX).safeTransfer(msg.sender, redeemedAmount);
    emit ProcessYield(WAVAX, redeemedAmount);
  }

  /**
   * @dev Set treasury address and vault fee
   * @param _treasury The treasury address
   * @param _fee The vault fee which has more two decimals, ex: 100% = 100_00
   */
  function setTreasuryInfo(address _treasury, uint256 _fee) external onlyOwner {
    require(_treasury != address(0), "INVALID_TREASURY_ADDRESS");
    require(_fee <= 30_00, "FEE_TOO_BIG");
    _treasuryAddress = _treasury;
    _vaultFee = _fee;

    emit SetTreasuryInfo(_treasury, _fee);
  }

  function setHarvestOnDeposit(bool flag) external onlyOwner {
    _shouldHarvestOnDeposit = flag;
  }

  function checkShouldHarvestOnDeposit() external view returns (bool) {
    return _shouldHarvestOnDeposit;
  }

  function setKeeper(address addr, bool flag) external onlyOwner {
    _isKeeper[addr] = flag;
  }

  function isKeeper(address addr) external view returns (bool) {
    return _isKeeper[addr];
  }

  function setWhitelist(address addr, bool flag) external onlyOwner {
    _whitelist[addr] = flag;
  }

  function isWhitelisted(address addr) external view returns (bool) {
    return _whitelist[addr];
  }

  function switchStrategy(Strategy newStrategy) external onlyOwner {
    require(newStrategy != _currentStrategy, "MUST_BE_A_DIFFERENT_STRATEGY");

    uint256 underlyingBal = balanceOfUnderlying();
    if (underlyingBal == 0) {
      _currentStrategy = newStrategy;
      emit SetStrategy(newStrategy);
      return;
    }

    if (_currentStrategy == Strategy.AAVE && newStrategy == Strategy.BENQI) {
      // TODO: do not fail if there is no fund in AAV strategy
      // Withdraw all funds from Aave and deposit to Benqi
      uint256 withdrawalAmount = AaveStrategy.withdrawAll(WAVAX);
      // harvest remaining reward
      uint256 reward = AaveStrategy.harvest(false);

      uint256 totalAmount = withdrawalAmount + reward;
      IWAVAX(WAVAX).withdraw(totalAmount);
      BenqiStrategy.deposit(totalAmount);
    } else if (_currentStrategy == Strategy.BENQI && newStrategy == Strategy.AAVE) {
      uint256 withdrawalAmount = BenqiStrategy.redeemAll();
      // harvest remaining reward
      uint256 reward = BenqiStrategy.harvest(false);
      // totalAmount in AVAX
      uint256 totalAmount = withdrawalAmount + reward;
      AaveStrategy.depositAVAX(totalAmount);
    }

    _currentStrategy = newStrategy;
    emit SetStrategy(newStrategy);
  }

  function recoverToken(address token, uint256 amount) external onlyOwner {
    IERC20(token).safeTransfer(owner(), amount);
  }

  /**
   * @dev Receive AVAX
   */
  receive() external payable {}
}
