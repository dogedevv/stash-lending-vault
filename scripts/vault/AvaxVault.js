const deployVault = async (vaultContractName) => {
  const Vault = await hre.ethers.getContractFactory(vaultContractName)

  const vault = await Vault.deploy()
  await vault.deployed()

  console.log('AvaxVault is deployed at', vault.address)
  // await avaxVault.initialize(addressProvider)

  return vault
}

module.exports = {
  deployVault
}
