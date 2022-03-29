import type { NetworksUserConfig } from 'hardhat/types';
import { alchemyRinkebyEthKey, testnetPrivateKey } from './variables';

export const networks: NetworksUserConfig = {
	hardhat: {
		accounts: {
			mnemonic: 'test test test test test test test test test test test junk',
			initialIndex: 0,
			path: "m/44'/60'/0'/0",
			count: 20
		}
	},
	frame: {
		url: 'http://127.0.0.1:1248'
	},
	local: {
		chainId: 99,
		url: 'http://127.0.0.1:8545',
		allowUnlimitedContractSize: true
	},
	localh: {
		chainId: 31337,
		url: 'http://127.0.0.1:8545',
		allowUnlimitedContractSize: true
	},
	rinkeby: {
		url: `https://eth-rinkeby.alchemyapi.io/v2/${alchemyRinkebyEthKey}`,
		accounts: [testnetPrivateKey]
	}
};
