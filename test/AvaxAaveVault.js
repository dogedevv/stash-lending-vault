const chai = require('chai')
const { ethers, waffle } = require('hardhat')
const { solidity } = require('ethereum-waffle')
const { deployVault } = require('../scripts/vault')

const erc20Abi = require('../abis/erc20.abi.json')

const { expect } = chai
const { provider } = waffle

// deploy mock address provider
const deployMockAddressProvider = async () => {
  const AddressProvider = await hre.ethers.getContractFactory('LendingPoolAddressesProvider')
  const addressProvider = await AddressProvider.deploy()
  await addressProvider.deployed()

  const lendingPool = await addressProvider.getLendingPool()
  console.log('lendingPool address', lendingPool)
  console.log('AddressProvider was deployed at: ' + addressProvider.address)

  return addressProvider
}

const deployMockLendingPool = async () => {
  const LendingPoolMock = await hre.ethers.getContractFactory('LendingPoolMock')
  const lendingPoolMock = await LendingPoolMock.deploy()
  await lendingPoolMock.deployed()
  console.log('LendingPoolMock was deployed at: ' + lendingPoolMock.address)

  return lendingPoolMock
}

const deployMockAaveRewardController = async () => {
  const IncentivesControllerMock = await hre.ethers.getContractFactory('AaveIncentiveControllerMock')

  const incentivesControllerMock = await IncentivesControllerMock.deploy()
  await incentivesControllerMock.deployed()

  console.log('AAVE IncentivesControllerMock was deployed at: ', incentivesControllerMock.address)
  return incentivesControllerMock
}

describe('AvaxAaveVault', async () => {
  before(async () => {
    const [owner, user1] = await ethers.getSigners()

    this.owner = owner
    this.user1 = user1
    this.addressProvider = await deployMockAddressProvider()
    this.lendingPool = await deployMockLendingPool()
    this.avaxVault = await deployVault('AvaxAaveVault')

    await this.avaxVault.initialize(this.addressProvider.address)

    this.aaveIncentivesController = await deployMockAaveRewardController()

    const WAVAX = '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7'
    const WAVAX_WHALE = '0x6c1a5ef2acde1fd2fc68def440d2c1eb35bae24a'

    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [WAVAX_WHALE]
    })

    this.wavax = new ethers.Contract(WAVAX, erc20Abi, owner)
    this.wavaxWhale = await ethers.getSigner(WAVAX_WHALE)
  })

  describe('Test initialization', () => {
    it('avax whale should have some wavax', async () => {
      const bal = await this.wavax.balanceOf(this.wavaxWhale.address)
      expect(bal).to.gt(0)
    })

    it('should be return correct admin', async () => {
      const POOL_ADMIN = ethers.utils.formatBytes32String('POOL_ADMIN')
      await this.addressProvider.setAddress(POOL_ADMIN, this.owner.address)
      const poolAdmin = await this.addressProvider.getPoolAdmin()
      expect(poolAdmin).to.eq(this.owner.address)

      const LENDING_POOL = ethers.utils.formatBytes32String('LENDING_POOL')
      await this.addressProvider.setAddress(LENDING_POOL, this.lendingPool.address)
      const lendingPool = await this.addressProvider.getLendingPool()
      expect(lendingPool).to.eq(this.lendingPool.address)
    })

    describe('Test aave incentivesControllerMock', () => {
      before(async () => {
        // send 1000 wavax
        this.wavax
          .connect(this.wavaxWhale)
          .transfer(this.aaveIncentivesController.address, ethers.utils.parseEther('1000'))
      })

      it('should be able to set rewards', async () => {
        await this.aaveIncentivesController
          .connect(this.owner)
          .setAvailableRewards(this.user1.address, ethers.utils.parseEther('10'))
      })

      it('should be able to get rewards', async () => {
        const availableRewards = await this.aaveIncentivesController.getUserRewards(
          [this.wavax.address],
          this.user1.address,
          this.wavax.address
        )
        expect(availableRewards).to.eq(ethers.utils.parseEther('10'))
      })

      it('should be able to claim rewards', async () => {
        const rewardAmount = ethers.utils.parseEther('10')
        const balwavaxBefore = await this.wavax.balanceOf(this.user1.address)
        await this.aaveIncentivesController
          .connect(this.user1)
          .claimRewards([this.wavax.address], rewardAmount, this.user1.address, this.wavax.address)
        const balwavaxAfter = await this.wavax.balanceOf(this.user1.address)
        expect(balwavaxAfter).eq(balwavaxBefore.add(rewardAmount))
      })
    })
  })

  describe('AAVE strategy', () => {
    let aToken
    let bearingToken
    before(async () => {
      const bearingTokenAddr = await this.avaxVault.getBearingToken()
      bearingToken = new ethers.Contract(bearingTokenAddr, erc20Abi, this.owner)
      aToken = new ethers.Contract(this.lendingPool.address, erc20Abi, this.owner)
    })

    describe('depositCollateral', () => {
      it('should succeed to deposit WAVAX as collateral', async () => {
        const amountWAVAX = ethers.utils.parseEther('100')
        await this.wavax.connect(this.wavaxWhale).approve(this.avaxVault.address, ethers.constants.MaxUint256)

        await this.avaxVault.connect(this.wavaxWhale).depositCollateral(this.wavax.address, amountWAVAX)

        // const tx =
        const balBearingTokenOfPool = await bearingToken.balanceOf(this.lendingPool.address)
        expect(balBearingTokenOfPool).to.gte(amountWAVAX)

        const balAToken = await aToken.balanceOf(this.wavaxWhale.address)
        expect(balAToken).to.eq(amountWAVAX)
      })

      it('should succeed to depsot AVAX as collateral', async () => {
        const amountAVAX = ethers.utils.parseEther('100')
        const balBearingTokenOfPoolBefore = await bearingToken.balanceOf(this.lendingPool.address)
        const aTokenBalBefore = await aToken.balanceOf(this.user1.address)

        await this.avaxVault.connect(this.user1).depositCollateral(ethers.constants.AddressZero, amountAVAX, {
          value: amountAVAX
        })
        const balBearingTokenOfPoolAfter = await bearingToken.balanceOf(this.lendingPool.address)
        expect(balBearingTokenOfPoolAfter).to.gt(balBearingTokenOfPoolBefore.add(amountAVAX))
        const aTokenBalAfter = await aToken.balanceOf(this.user1.address)
        expect(aTokenBalAfter).eq(aTokenBalBefore.add(amountAVAX))
      })

      it('should harvest and reinvest on deposit', async () => {
        // transfer wavax to aave reward controller

        // get byte code of aaave incetives controller mock
        const code = await hre.network.provider.send('eth_getCode', [this.aaveIncentivesController.address])
        const AAVE_INCENTIVES_CONTROLLER_MAINNET_ADDR = '0x929EC64c34a17401F460460D4B9390518E5B473e'

        await hre.network.provider.send('hardhat_setCode', [AAVE_INCENTIVES_CONTROLLER_MAINNET_ADDR, code])

        // inject mock contract code to AAVE incentive controller mainnet address
        this.aaveIncentivesController = await ethers.getContractAt(
          'AaveIncentiveControllerMock',
          AAVE_INCENTIVES_CONTROLLER_MAINNET_ADDR,
          this.owner
        )

        // transfer WAVAX to incentive controller
        await this.wavax
          .connect(this.wavaxWhale)
          .transfer(this.aaveIncentivesController.address, ethers.utils.parseEther('100'))

        const rewardAmount = ethers.utils.parseEther('10')

        // set availableRewards for vault
        await this.aaveIncentivesController
          .connect(this.owner)
          .setAvailableRewards(this.avaxVault.address, rewardAmount)

        // deposit collateral to trigger harvest
        const amountWAVAX = ethers.utils.parseEther('100')
        await this.wavax.connect(this.wavaxWhale).approve(this.avaxVault.address, ethers.constants.MaxUint256)

        const balBearingTokenOfPoolBefore = await bearingToken.balanceOf(this.lendingPool.address)
        await this.avaxVault.connect(this.wavaxWhale).depositCollateral(this.wavax.address, amountWAVAX)
        const balBearingTokenOfPoolAfter = await bearingToken.balanceOf(this.lendingPool.address)

        expect(balBearingTokenOfPoolAfter).to.gte(balBearingTokenOfPoolBefore.add(amountWAVAX).add(rewardAmount))
      })
    })

    describe('Withdraw collateral', () => {
      it('should be able to withdraw WAVAX collateral', async () => {
        // deposit collateral
        const amountWAVAX = ethers.utils.parseEther('100')
        await this.wavax.connect(this.wavaxWhale).approve(this.avaxVault.address, ethers.constants.MaxUint256)

        await this.avaxVault.connect(this.wavaxWhale).depositCollateral(this.wavax.address, amountWAVAX)

        const slippage = ethers.constants.Zero
        const balBefore = await this.wavax.balanceOf(this.wavaxWhale.address)

        await this.avaxVault
          .connect(this.wavaxWhale)
          .withdrawCollateral(this.wavax.address, amountWAVAX, slippage, this.wavaxWhale.address)
        const balAfter = await this.wavax.balanceOf(this.wavaxWhale.address)
        const balBearingTokenOfVault = await bearingToken.balanceOf(this.avaxVault.address)

        expect(balAfter).to.eq(balBefore.add(amountWAVAX))
        expect(balBearingTokenOfVault).to.eq(0)
      })

      it('should be able to withdraw AVAX collateral', async () => {
        const amount = ethers.utils.parseEther('10')
        await this.avaxVault.connect(this.user1).depositCollateral(ethers.constants.AddressZero, amount, {
          value: amount
        })
        const avaxBal = await provider.getBalance(this.user1.address)
        console.log('avaxBal', ethers.utils.formatEther(avaxBal))
        const slippage = ethers.constants.Zero
        await this.avaxVault.withdrawCollateral(ethers.constants.AddressZero, amount, slippage, this.user1.address)
        const avaxBalAfter = await provider.getBalance(this.user1.address)
        console.log('avaxBalAfter', ethers.utils.formatEther(avaxBalAfter))
        expect(avaxBalAfter).to.eq(avaxBal.add(amount))
      })
    })

    describe('processYield', () => {
      const avWAVAXAddr = '0x6d80113e533a2C0fe82EaBD35f1875DcEA89Ea97'
      before(async () => {
        // transfer aToken to lendingpool
        const aTokenWhale = '0x2b6e061a8e0ca75eb26157efbfd077e3a23dc261'

        await hre.network.provider.request({
          method: 'hardhat_impersonateAccount',
          params: [aTokenWhale]
        })

        const whale = await ethers.getSigner(aTokenWhale)
        const avWAVAX = new ethers.Contract(avWAVAXAddr, erc20Abi, this.owner)

        await avWAVAX.connect(whale).approve(this.lendingPool.address, ethers.utils.parseEther('100'))

        await this.lendingPool.connect(whale).setTotalBalanceOfAssetPair(avWAVAXAddr, ethers.utils.parseEther('100'))
      })
      it('should setup correctly', async () => {
        const result = await this.lendingPool.getTotalBalanceOfAssetPair(avWAVAXAddr)
      })

      it('should be able to process yield successfully', async () => {
        const YIELD_MANAGER = ethers.utils.formatBytes32String('YIELD_MANAGER')
        await this.addressProvider.setAddress(YIELD_MANAGER, this.owner.address)

        const balBefore = await this.wavax.balanceOf(this.owner.address)
        const yieldAmount = await this.avaxVault.getYieldAmount()

        expect(yieldAmount).to.gt(0)
        await this.avaxVault.processYield()
        const balAfter = await this.wavax.balanceOf(this.owner.address)
        expect(balAfter).to.eq(balBefore.add(yieldAmount))
      })
    })

    it('pool with many deposits', () => {})
  })
})
