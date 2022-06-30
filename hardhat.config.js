require('dotenv').config()

require('@nomiclabs/hardhat-etherscan')
require('@nomiclabs/hardhat-waffle')
require('hardhat-gas-reporter')
require('solidity-coverage')

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task('accounts', 'Prints the list of accounts', async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners()

  for (const account of accounts) {
    console.log(account.address)
  }
})

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  defaultNetwork: 'hardhat',
  solidity: {
    compilers: [
      {
        version: '0.8.10',
        settings: {
          evmVersion: 'istanbul',
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      {
        version: '0.6.6',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      {
        version: '0.5.16',
        settings: {}
      }
    ]
  },
  networks: {
    hardhat: {
      forking: {
        enabled: true,
        url: 'https://api.avax.network/ext/bc/C/rpc',
        blockNumber: 16600000
      }
    },
    mainnet: {
      url: `${process.env.MAINNET_URL}`,
      chainId: 1,
      accounts: [process.env.PRIVATE_KEY]
    },
    bsctestnet: {
      url: `${process.env.BSCTESTNET_URL}`,
      chainId: 97,
      accounts: [process.env.PRIVATE_KEY]
    },
    framesh: {
      url: 'http://127.0.0.1:1248',
      gas: 'auto',
      timeout: 10 * 60 * 1000 // 10 minutes
    },
    ropsten: {
      url: process.env.ROPSTEN_URL || '',
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : []
    },
    rinkeby: {
      url: `${process.env.RINKEBY_URL}`,
      chainId: 4,
      accounts: [process.env.PRIVATE_KEY],
      gasPrice: 60000000000,
      gas: 'auto'
    }
  },
  gasReporter: {
    currency: 'USD'
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY
  }
}
