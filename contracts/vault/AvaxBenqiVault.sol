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
import "hardhat/console.sol";

/**
 * @title GeneralVault
 * @notice Basic feature of vault
 * @author Dede
 **/

contract AvaxBenqiVault is Initializable, OwnableUpgradeable, ERC20Upgradeable, ERC20BurnableUpgradeable {
  using PercentageMath for uint256;
  using SafeERC20 for IERC20;

  event ProcessYield(address indexed collateralAsset, uint256 yieldAmount);
  event SetTreasuryInfo(address indexed treasuryAddress, uint256 fee);
  event Deposit(address indexed collateralAsset, address indexed from, uint256 amount);
  event Withdraw(address indexed collateralAsset, address indexed to, uint256 amount);
  event Harvest(address indexed collateralAsset, uint256 amount);
  event SetKeeper(address keeper, bool flag);

  address public constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
  // aAvaWAVAX - bearing token of AVAX on Aaave AVAX market
  address public constant bearingToken = 0x5C0401e81Bc07Ca70fAD469b451682c0d747Ef1c;

  uint256 private constant VAULT_VERSION = 0x1;
  // vault fee 20%
  uint256 internal _vaultFee;
  address internal _treasuryAddress;

  bool public shouldHarvestOnDeposit;
  mapping(address => bool) public _isKeeper;

  /**
   * @dev Function is invoked by the proxy contract when the Vault contract is deployed.
   **/
  function initialize() external initializer {
    __ERC20_init(string(abi.encodePacked("Dede ", IERC20Metadata(WAVAX).name(), " Vault")), string(abi.encodePacked("v", IERC20Metadata(WAVAX).symbol())));
    __Ownable_init();

    shouldHarvestOnDeposit = true;
  }

  function getVersion() internal pure returns (uint256) {
    return VAULT_VERSION;
  }

  function deposit(uint256 amount) external {
    IERC20(WAVAX).transferFrom(msg.sender, address(this), amount);

    console.log("step withdraw");
    IWAVAX(WAVAX).withdraw(amount);
    console.log("step deposit");
    BenqiStrategy.deposit(amount);

    if (shouldHarvestOnDeposit) {
      uint256 harvestedAmount = BenqiStrategy.harvest(true);
      // emit harvest
      emit Harvest(bearingToken, harvestedAmount);
    }

    // mint the same underlying token amount to the depositor
    _mint(msg.sender, amount);
  }

  function withdraw(uint256 amount) external {
    // Convert amount of vToken to bearing token's amount of Benqi strategy
    _burn(msg.sender, amount);
    uint256 bearingTokenAmount = _convertToBearingTokenAmount(amount);
    uint256 amountAVAX = BenqiStrategy.redeem(bearingTokenAmount);

    IWAVAX(WAVAX).deposit{value: amountAVAX}();
    IERC20(WAVAX).transfer(msg.sender, amountAVAX);
  }

  function _convertToBearingTokenAmount(uint256 underlyingAmount) internal returns (uint256) {
    return BenqiStrategy.estimateConversionToBearingTokenAmount(underlyingAmount);
  }

  function getYieldAmount() public returns (uint256) {
    uint256 balanceOfUnderlying = BenqiStrategy.balanceOfUnderlying(address(this));
    uint256 totalSupply = totalSupply();
    return balanceOfUnderlying > totalSupply ? balanceOfUnderlying - totalSupply : 0;
  }

  function balanceOfUnderlying() public returns (uint256) {
    return BenqiStrategy.balanceOfUnderlying(address(this));
  }

  /**
   * @dev Grab excess stETH which was from rebasing on Lido
   *  And convert stETH -> ETH -> asset, deposit to pool
   */
  function claimYield() external {
    require(_isKeeper[msg.sender], "CALLER_IS_NOT_A_KEEPER");

    uint256 fee = _vaultFee;
    uint256 yieldAmount = getYieldAmount();
    console.log("yieldAmount", yieldAmount);
    uint256 balBefore = address(this).balance;
    BenqiStrategy.redeemUnderlying(yieldAmount);
    uint256 amountAVAX = address(this).balance - balBefore;
    console.log("amountAVAX", yieldAmount);

    IWAVAX(WAVAX).deposit{value: yieldAmount}();

    if (fee > 0) {
      uint256 treasuryAmount = yieldAmount.percentMul(fee);
      IERC20(WAVAX).safeTransfer(_treasuryAddress, treasuryAmount);
      yieldAmount -= treasuryAmount;
    }

    IERC20(WAVAX).safeTransfer(msg.sender, yieldAmount);
    emit ProcessYield(WAVAX, yieldAmount);
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
    shouldHarvestOnDeposit = flag;
  }

  function setKeeper(address addr, bool flag) external onlyOwner {
    _isKeeper[addr] = flag;
  }

  /**
   * @dev Receive AVAX
   */
  receive() external payable {}
}

// switch strategy
// withdraw all tokens from the protocol, with draw all unclaimed yield
// deposit to the new protocol, withdraw all unclaimed yield
//
