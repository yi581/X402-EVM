/**
 * 简化版：直接从用户钱包给 Provider 充值
 */

require('dotenv').config();
const { ethers } = require('ethers');

const PROVIDER_ADDRESS = '0xBfED0E16A8E77b78e05BB1cb16aE2c047efB606d';
const INSURANCE_V8_ADDRESS = '0x72486eF40BB3729298369d608de85c612adb223e';
const USDC_ADDRESS = '0x036CbD53842c5426634e7929541eC2318f3dCF7e';
const RPC_URL = 'https://sepolia.base.org';

const INSURANCE_ABI = [
  'function depositAdditionalFor(address provider, uint256 amount)',
  'function getProviderInfo(address) view returns (bool,uint256,uint256,uint256,uint256,uint8,uint256)'
];

const USDC_ABI = [
  'function approve(address, uint256) returns (bool)',
  'function balanceOf(address) view returns (uint256)'
];

async function main() {
  console.log('🔄 简单充值测试\n');

  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const privateKey = process.env.PRIVATE_KEY || process.env.DEPLOYER_PRIVATE_KEY;
  const wallet = new ethers.Wallet(privateKey, provider);

  const insurance = new ethers.Contract(INSURANCE_V8_ADDRESS, INSURANCE_ABI, wallet);
  const usdc = new ethers.Contract(USDC_ADDRESS, USDC_ABI, wallet);

  // 查看当前状态
  console.log('📊 充值前状态:');
  const infoBefore = await insurance.getProviderInfo(PROVIDER_ADDRESS);
  console.log('   保险池:', ethers.formatUnits(infoBefore[1], 6), 'USDC');
  console.log('   锁定:', ethers.formatUnits(infoBefore[2], 6), 'USDC\n');

  // 充值 3 USDC
  const amount = ethers.parseUnits('3', 6);
  console.log('💰 充值 3 USDC...');

  console.log('   授权 USDC...');
  const approveTx = await usdc.approve(INSURANCE_V8_ADDRESS, amount);
  await approveTx.wait();
  console.log('   ✅ 授权成功\n');

  console.log('   充值到保险池...');
  const depositTx = await insurance.depositAdditionalFor(PROVIDER_ADDRESS, amount);
  await depositTx.wait();
  console.log('   ✅ 充值成功');
  console.log('   TX:', depositTx.hash, '\n');

  // 查看充值后状态
  console.log('📊 充值后状态:');
  const infoAfter = await insurance.getProviderInfo(PROVIDER_ADDRESS);
  console.log('   保险池:', ethers.formatUnits(infoAfter[1], 6), 'USDC');
  console.log('   锁定:', ethers.formatUnits(infoAfter[2], 6), 'USDC\n');

  const增加 = infoAfter[1] - infoBefore[1];
  console.log('✅ 成功充值:', ethers.formatUnits(增加, 6), 'USDC');
}

main().catch(console.error);
