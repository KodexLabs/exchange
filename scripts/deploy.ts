import { ethers } from 'hardhat';
import type { KodexExchange__factory } from '../typechain';

const SYSTEM_FEE = 30; // 3%

async function main() {
	const [deployer] = await ethers.getSigners();

	const KodexExhangeContract = (await ethers.getContractFactory('KodexExchange')) as KodexExchange__factory;
	const kodexExchange = await KodexExhangeContract.deploy(
		'0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e',
		// Rinkeby WETH
		'0xc778417E063141139Fce010982780140Aa0cD5Ab',
		deployer.address,
		SYSTEM_FEE
	);
	await kodexExchange.deployed();

	console.log(
		[
			` - "KodexExchange" deployed to ${kodexExchange.address}`, //
			`Deployer address is ${deployer.address}`
		].join('\n')
	);
}

main()
	.then(() => process.exit(0))
	.catch((error) => {
		console.error(error);
		process.exit(1);
	});
