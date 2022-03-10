import '@nomiclabs/hardhat-ethers';
import '@typechain/hardhat';
import 'hardhat-abi-exporter';
import { HardhatUserConfig, task } from 'hardhat/config';
import { networks } from './networks.hardhat';

task('accounts', 'Prints the list of accounts', async (_, hre) => {
	const accounts = await hre.ethers.getSigners();

	for (const account of accounts) {
		console.log(account.address);
	}
});

const config: HardhatUserConfig = {
	paths: {
		sources: './src/contracts',
		tests: './test'
	},
	solidity: {
		version: '0.8.11',
		settings: {
			optimizer: {
				enabled: true,
				runs: 2000
			}
		}
	},
	defaultNetwork: 'hardhat',
	networks,
	abiExporter: {
		path: './abis',
		runOnCompile: true,
		clear: true,
		flat: true,
		only: ['KodexExchange']
	},
	typechain: {
		outDir: 'typechain',
		target: 'ethers-v5',
		alwaysGenerateOverloads: false
	}
};

export default config;
