import { ethers } from 'hardhat';
import type { KodexExchange__factory } from '../typechain';

const SYSTEM_FEE = 100; // 1,00%

async function main() {
	console.log('Starting!');
	const [deployer] = await ethers.getSigners();

	const KodexExhangeContract = (await ethers.getContractFactory('KodexExchange')) as KodexExchange__factory;
	const kodexExchange = await KodexExhangeContract.deploy(
		'0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85',
		'0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
		deployer.address,
		SYSTEM_FEE
	);
	await kodexExchange.deployed();

	await kodexExchange.transferOwnership('0x171940bFcBB287744D644E07333D6738fCC53DbF');

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
