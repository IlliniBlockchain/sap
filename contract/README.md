## Instructions:

First, set up your `.env` file. Use 12 random words as the mnemonic, strictly for demo purposes.
```bash
cp .env.example .env
```

Then install the packages.
```bash
yarn install
```

Then, on two different tabs, run each of the commands below.
```bash
npx hardhat node
yarn deploy --greeting "Example Hello"
```

You will see the address of the deployed contract, and a bunch of logs in your local node.

Finally, grab the private key of your mnemonic and import it to MetaMask
```bash
node scripts/generate-priv-key.js
```

** Make sure that you have localhost:8545 with chain ID 31337 added to your MetaMask.
