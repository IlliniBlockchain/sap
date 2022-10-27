require('dotenv').config()

const { Wallet } = require('ethers')

async function main() {
  const wallet = Wallet.fromMnemonic(process.env.MNEMONIC)
  console.log('Private key:', wallet.privateKey)
}

main()