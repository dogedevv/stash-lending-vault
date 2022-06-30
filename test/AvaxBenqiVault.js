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

describe('BenqiVault', async () => {
  before(async () => {
    const [owner, user1] = await ethers.getSigners()

    this.owner = owner
    this.user1 = user1
    this.addressProvider = await deployMockAddressProvider()
    // this.lendingPool = await deployMockLendingPool()
    this.avaxVault = await deployVault('AvaxBenqiVault')
    await this.avaxVault.initialize()
    // this.aaveIncentivesController = await deployMockAaveRewardController()

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

    describe('BENQI Strategy', () => {
      let aToken
      let bearingToken
      before(async () => {
        // switch to benqi strategy
        const bearingTokenAddr = await this.avaxVault.bearingToken()
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
        // it('should be able to withdraw', async () => {
        //   const amountAVAX = ethers.utils.parseEther('100')
        //   await this.wavax.connect(this.wavaxWhale).transfer(this.user1.address, amountAVAX)

        //   await this.wavax.connect(this.user1).approve(this.avaxVault.address, ethers.constants.MaxUint256)
        //   await this.avaxVault.connect(this.user1).deposit(amountAVAX)

        //   const balBearingTokenOfVault1 = await bearingToken.balanceOf(this.avaxVault.address)
        //   const vTokenBalBefore = await this.avaxVault.balanceOf(this.user1.address)
        //   console.log('vTokenBalBefore')
        //   const balUnderlyingBefore = await this.avaxVault.callStatic.balanceOfUnderlying()
        //   console.log('balUnderlyingBefore')
        //   const balBefore = await this.wavax.balanceOf(this.user1.address)

        //   const balBearingTokenOfVault2 = await bearingToken.balanceOf(this.avaxVault.address)

        //   await this.avaxVault.connect(this.user1).withdraw(amountAVAX)
        //   const vTokenAfter = await this.avaxVault.balanceOf(this.user1.address)

        //   const balBearingTokenAfter = await bearingToken.balanceOf(this.avaxVault.address)
        //   expect(balBearingTokenAfter).to.lt(balBearingTokenOfVault1)

        //   const balAfter = await this.wavax.balanceOf(this.user1.address)
        //   const balUnderlying = await this.avaxVault.callStatic.balanceOfUnderlying()
        //   expect(balAfter).to.gt(balBefore)
        //   expect(vTokenAfter).to.eq(0)
        // })

        it('should not be able to withdraw if exceeds balance', async () => {
          const vTokenBal = await this.avaxVault.balanceOf(this.user1.address)
          // try to withdraw exceeds balance
          await expect(this.avaxVault.connect(this.user1).withdraw(vTokenBal.add(1))).to.be.revertedWith(
            'ERC20: burn amount exceeds balance'
          )
        })
        // it('should be able to withdraw AVAX as collateral successfully', async () => {
        //   const amountAVAX = ethers.utils.parseEther('100')
        //   const slippage = ethers.constants.Zero
        //   const balAVAXBefore = await provider.getBalance(this.user1.address)
        //   const balBearingTokenOfPoolBefore = await bearingToken.balanceOf(this.lendingPool.address)
        //   console.log('balBearingTokenOfPoolBefore', balBearingTokenOfPoolBefore)
        //   await this.avaxVault.connect(this.user1).depositCollateral(ethers.constants.AddressZero, amountAVAX, {
        //     value: amountAVAX
        //   })
        //   const tx = await this.avaxVault
        //     .connect(this.user1)
        //     .withdrawCollateral(ethers.constants.AddressZero, amountAVAX, slippage, this.user1.address)
        //   const receipt = await tx.wait()
        //   // expect(balBearingTokenOfPoolAfter).to.gt(balBearingTokenOfPoolBefore.add(amountAVAX))
        //   const balBearingTokenOfPool = await bearingToken.balanceOf(this.lendingPool.address)
        //   expect(balBearingTokenOfPool).to.eq(0)
        //   const balAVAXAfter = await provider.getBalance(this.user1.address)
        //   console.log(
        //     'balAVAXBefore',
        //     ethers.utils.formatEther(balAVAXBefore.add(amountAVAX).sub(receipt.cumulativeGasUsed))
        //   )
        //   // balBefore - gasUsed + amountAVAX
        //   console.log('balAVAXAfter', ethers.utils.formatEther(balAVAXAfter))
        //   // expect(balAVAXAfter).to.gt(balAVAXBefore.add(amountAVAX).sub(receipt.cumulativeGasUsed))
        // })
      })
    })

    describe('Process yield', () => {
      it('deposit more', async () => {
        const amountAVAX = ethers.utils.parseEther('1000')
        // const balBearingTokenOfPoolBefore = await bearingToken.balanceOf(this.lendingPool.address)
        await this.wavax.connect(this.wavaxWhale).approve(this.avaxVault.address, ethers.constants.MaxUint256) //
        await this.avaxVault.connect(this.wavaxWhale).deposit(amountAVAX)

        const totalSupply = await this.avaxVault.totalSupply()
      })

      it('claim yield', async () => {
        await this.avaxVault.connect(this.owner).setKeeper(this.owner.address, true)
        const balUnderlying = await this.avaxVault.callStatic.balanceOfUnderlying()
        console.log('balUnderlyingBefore', balUnderlying)
        await this.avaxVault.connect(this.owner).claimYield()
        const balUnderlyingAfter = await this.avaxVault.callStatic.balanceOfUnderlying()
        console.log('balUnderlyingAfter', balUnderlyingAfter)
      })
    })
  })
})
