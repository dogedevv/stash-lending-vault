const chai = require('chai')
const { ethers, waffle } = require('hardhat')
const { solidity } = require('ethereum-waffle')
const { deployVault } = require('../scripts/vault')

const erc20Abi = require('../abis/erc20.abi.json')

const { expect } = chai
const { provider } = waffle

const deployMockAaveRewardController = async () => {
  const IncentivesControllerMock = await hre.ethers.getContractFactory('AaveIncentiveControllerMock')

  const incentivesControllerMock = await IncentivesControllerMock.deploy()
  await incentivesControllerMock.deployed()

  console.log('AAVE IncentivesControllerMock was deployed at: ', incentivesControllerMock.address)
  return incentivesControllerMock
}

describe('AvaxVault', async () => {
  before(async () => {
    const [owner, user1] = await ethers.getSigners()

    this.owner = owner
    this.user1 = user1
    this.avaxVault = await deployVault('AvaxVault')

    await this.avaxVault.initialize()

    this.aaveIncentivesController = await deployMockAaveRewardController()

    const WAVAX = '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7'
    const WAVAX_WHALE = '0x6c1a5ef2acde1fd2fc68def440d2c1eb35bae24a'

    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [WAVAX_WHALE]
    })

    this.wavax = new ethers.Contract(WAVAX, erc20Abi, owner)
    this.wavaxWhale = await ethers.getSigner(WAVAX_WHALE)
    await this.avaxVault.connect(this.owner).setWhitelist(this.wavaxWhale.address, true)
    await this.avaxVault.connect(this.owner).setWhitelist(this.user1.address, true)
  })

  describe('Test initialization', () => {
    it('avax whale should have some wavax', async () => {
      const bal = await this.wavax.balanceOf(this.wavaxWhale.address)
      expect(bal).to.gt(0)
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
    let bearingToken
    before(async () => {
      const bearingTokenAddr = await this.avaxVault.getBearingToken()
      bearingToken = new ethers.Contract(bearingTokenAddr, erc20Abi, this.owner)
    })

    describe('deposit', () => {
      it('should succeed to deposit WAVAX as collateral', async () => {
        const amountWAVAX = ethers.utils.parseEther('100')
        await this.wavax.connect(this.wavaxWhale).approve(this.avaxVault.address, ethers.constants.MaxUint256)

        await this.avaxVault.connect(this.wavaxWhale).deposit(amountWAVAX)

        // const tx =
        const balBearingTokenOfPool = await bearingToken.balanceOf(this.avaxVault.address)
        expect(balBearingTokenOfPool).to.eq(amountWAVAX)

        const balVToken = await this.avaxVault.balanceOf(this.wavaxWhale.address)
        expect(balVToken).to.eq(amountWAVAX)
      })

      // it('should succeed to depsot AVAX as collateral', async () => {
      //   const amountAVAX = ethers.utils.parseEther('100')
      //   const balBearingTokenOfPoolBefore = await bearingToken.balanceOf(this.lendingPool.address)
      //   const aTokenBalBefore = await aToken.balanceOf(this.user1.address)

      //   await this.avaxVault.connect(this.user1).depositCollateral(ethers.constants.AddressZero, amountAVAX, {
      //     value: amountAVAX
      //   })
      //   const balBearingTokenOfPoolAfter = await bearingToken.balanceOf(this.lendingPool.address)
      //   expect(balBearingTokenOfPoolAfter).to.gt(balBearingTokenOfPoolBefore.add(amountAVAX))
      //   const aTokenBalAfter = await aToken.balanceOf(this.user1.address)
      //   expect(aTokenBalAfter).eq(aTokenBalBefore.add(amountAVAX))
      // })

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

        const balBearingTokenOfPoolBefore = await bearingToken.balanceOf(this.avaxVault.address)
        const balVTokenBefore = await this.avaxVault.balanceOf(this.wavaxWhale.address)

        await this.avaxVault.connect(this.wavaxWhale).deposit(amountWAVAX)
        const balBearingTokenOfPoolAfter = await bearingToken.balanceOf(this.avaxVault.address)
        expect(balBearingTokenOfPoolAfter).to.gte(balBearingTokenOfPoolBefore.add(amountWAVAX).add(rewardAmount))

        const balVToken = await this.avaxVault.balanceOf(this.wavaxWhale.address)
        expect(balVToken).to.eq(balVTokenBefore.add(amountWAVAX))
      })
    })

    describe('Withdraw collateral', () => {
      it('shold not be able to withdraw exceeds balance', async () => {
        const amountWAVAX = ethers.utils.parseEther('100')
        const bal = await this.avaxVault.balanceOf(this.wavaxWhale.address)
        const balBeforeBefore = await this.wavax.balanceOf(this.wavaxWhale.address)
        await this.wavax.connect(this.wavaxWhale).approve(this.avaxVault.address, ethers.constants.MaxUint256)
        await expect(this.avaxVault.connect(this.wavaxWhale).withdraw(bal.add(1))).to.be.revertedWith(
          'ERC20: burn amount exceeds balance'
        )
      })

      it('should be able to withdraw WAVAX collateral', async () => {
        // deposit collateral
        const amountWAVAX = ethers.utils.parseEther('100')
        const balBeforeBefore = await this.wavax.balanceOf(this.wavaxWhale.address)
        await this.wavax.connect(this.wavaxWhale).approve(this.avaxVault.address, ethers.constants.MaxUint256)
        await this.avaxVault.connect(this.wavaxWhale).deposit(amountWAVAX)

        const balBefore = await this.wavax.balanceOf(this.wavaxWhale.address)
        const balTokenVBefore = await this.avaxVault.balanceOf(this.wavaxWhale.address)
        const balBearingTokenOfVaultBefore = await bearingToken.balanceOf(this.avaxVault.address)

        const tx = await this.avaxVault.connect(this.wavaxWhale).withdraw(amountWAVAX)
        const receipt = await tx.wait()

        const balAfter = await this.wavax.balanceOf(this.wavaxWhale.address)
        const balTokenVAfter = await this.avaxVault.balanceOf(this.wavaxWhale.address)
        const balBearingTokenOfVaultAfter = await bearingToken.balanceOf(this.avaxVault.address)

        // 0.01 - reserve for gas used
        expect(balAfter).to.gt(balBefore.add(amountWAVAX).sub(ethers.utils.parseEther('0.01')))
      })
    })

    describe('processYield', () => {
      const avWAVAXAddr = '0x6d80113e533a2C0fe82EaBD35f1875DcEA89Ea97'
      let avWAVAX
      before(async () => {
        // transfer aToken to lendingpool
        const aTokenWhale = '0x2b6e061a8e0ca75eb26157efbfd077e3a23dc261'

        await hre.network.provider.request({
          method: 'hardhat_impersonateAccount',
          params: [aTokenWhale]
        })

        const whale = await ethers.getSigner(aTokenWhale)
        avWAVAX = new ethers.Contract(avWAVAXAddr, erc20Abi, this.owner)

        await avWAVAX.connect(whale).transfer(this.avaxVault.address, ethers.utils.parseEther('100'))
      })

      it('should be able to process yield successfully', async () => {
        const balBefore = await this.wavax.balanceOf(this.owner.address)
        const balvAvaxBefore = await avWAVAX.balanceOf(this.avaxVault.address)
        const yieldAmount = await this.avaxVault.callStatic.getYieldAmount()

        expect(yieldAmount).to.gt(0)
        await this.avaxVault.connect(this.owner).setKeeper(this.owner.address, true)
        await this.avaxVault.connect(this.owner).claimYield()
        const balAfter = await this.wavax.balanceOf(this.owner.address)
        const tolerance = ethers.utils.parseEther('0.01')

        const balvAvaxAfter = await avWAVAX.balanceOf(this.avaxVault.address)
        expect(balAfter).to.gt(balBefore.add(ethers.utils.parseEther('100')))
      })
    })
  })

  describe('Switching strategy', async () => {
    before(async () => {
      const bal = await this.avaxVault.balanceOf(this.wavaxWhale.address)
    })

    it('should be able to switch strategy successfully', async () => {
      const bearingTokenBefore = new ethers.Contract(await this.avaxVault.getBearingToken(), erc20Abi, this.owner)
      const balBearingTokenBefore = await bearingTokenBefore.balanceOf(this.avaxVault.address)
      expect(balBearingTokenBefore).to.gt(0)
      const underlyingBalanceBefore = await this.avaxVault.callStatic.balanceOfUnderlying()

      const benqiStrategy = 1
      await this.avaxVault.connect(this.owner).switchStrategy(benqiStrategy)
      const bearingTokenAfter = new ethers.Contract(await this.avaxVault.getBearingToken(), erc20Abi, this.owner)
      const balBearingTokenAfter = await bearingTokenAfter.balanceOf(this.avaxVault.address)
      expect(balBearingTokenAfter).to.gt(0)
      const underlyingBalanceAfter = await this.avaxVault.callStatic.balanceOfUnderlying()

      const newBalBearingTokenBefore = await bearingTokenBefore.balanceOf(this.avaxVault.address)
      expect(newBalBearingTokenBefore).to.eq(0)
      expect(underlyingBalanceAfter).to.gt(underlyingBalanceBefore)
    })

    it('should be able to withdraw after switching strategy', async () => {
      const wavaxBalBefore = await this.wavax.balanceOf(this.wavaxWhale.address)
      const vTokenBalBefore = await this.avaxVault.balanceOf(this.wavaxWhale.address)

      const amount = vTokenBalBefore
      await this.avaxVault.connect(this.wavaxWhale).withdraw(amount)
      const wavaxBalAfter = await this.wavax.balanceOf(this.wavaxWhale.address)
      const vTokenBalAfter = await this.avaxVault.balanceOf(this.wavaxWhale.address)
      expect(vTokenBalAfter).to.eq(vTokenBalBefore.sub(amount))
      const tolerance = ethers.utils.parseEther('0.0001')
      expect(wavaxBalAfter).to.closeTo(wavaxBalBefore.add(amount), tolerance)
    })
  })

  describe('Benqi strategy', () => {
    let bearingToken

    before(async () => {
      // switch to benqi strategy
      const bearingTokenAddr = await this.avaxVault.getBearingToken()
      bearingToken = await ethers.getContractAt('IqiAVAX', bearingTokenAddr, this.owner)
    })
    describe('depositCollateral', () => {
      it('should be able to deposit WAVAX as collateral successfully', async () => {
        const amountAVAX = ethers.utils.parseEther('100')
        // const balBearingTokenOfPoolBefore = await bearingToken.balanceOf(this.lendingPool.address)
        await this.wavax.connect(this.wavaxWhale).approve(this.avaxVault.address, ethers.constants.MaxUint256)
        //
        const vTokenBalBefore = await this.avaxVault.balanceOf(this.wavaxWhale.address)
        await this.avaxVault.connect(this.wavaxWhale).deposit(amountAVAX)

        const balBearingTokenOfVault = await bearingToken.balanceOf(this.avaxVault.address)
        // expect(balBearingTokenOfPoolAfter).to.gt(balBearingTokenOfPoolBefore.add(amountAVAX))
        const vTokenBalAfter = await this.avaxVault.balanceOf(this.wavaxWhale.address)
        expect(vTokenBalAfter).eq(vTokenBalBefore.add(amountAVAX))
        expect(balBearingTokenOfVault).to.gt(0)
      })
    })

    describe('withdrawCollateral', () => {
      it('should not be able to withdraw if exceeds balance', async () => {
        const vTokenBal = await this.avaxVault.balanceOf(this.user1.address)
        // try to withdraw exceeds balance
        await expect(this.avaxVault.connect(this.user1).withdraw(vTokenBal.add(1))).to.be.revertedWith(
          'ERC20: burn amount exceeds balance'
        )
      })
    })
    describe('Process yield', () => {
      it('deposit more', async () => {
        const amountAVAX = ethers.utils.parseEther('1000')
        // const balBearingTokenOfPoolBefore = await bearingToken.balanceOf(this.lendingPool.address)
        await this.wavax.connect(this.wavaxWhale).approve(this.avaxVault.address, ethers.constants.MaxUint256) //
        await this.avaxVault.connect(this.wavaxWhale).deposit(amountAVAX)
      })

      it('claim yield', async () => {
        await this.avaxVault.connect(this.owner).setKeeper(this.owner.address, true)
        const wavaxBalBefore = await this.wavax.balanceOf(this.owner.address)
        await this.avaxVault.connect(this.owner).claimYield()
        const wavaxBalAfter = await this.wavax.balanceOf(this.owner.address)
        expect(wavaxBalAfter).to.gt(wavaxBalBefore)
      })
    })
  })
})
