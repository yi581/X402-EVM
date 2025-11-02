const { ethers } = require('ethers');
require('dotenv').config();

async function checkBalance() {
    const provider = new ethers.JsonRpcProvider('https://sepolia.base.org');
    const usdcAddress = '0x036CbD53842c5426634e7929541eC2318f3dCF7e';
    const accountAddress = '0xFC8BFfD6BBFc9CBCA95312F5bC3d5463c3cD3A71';

    const usdcAbi = ['function balanceOf(address) view returns (uint256)'];
    const usdc = new ethers.Contract(usdcAddress, usdcAbi, provider);

    const balance = await usdc.balanceOf(accountAddress);
    console.log(`USDC Balance: ${ethers.formatUnits(balance, 6)} USDC`);

    // Also check ETH balance
    const ethBalance = await provider.getBalance(accountAddress);
    console.log(`ETH Balance: ${ethers.formatEther(ethBalance)} ETH`);
}

checkBalance().catch(console.error);