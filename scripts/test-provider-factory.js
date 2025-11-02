/**
 * 测试 ProviderFactory - 一键创建 Provider
 */

require('dotenv').config();
const { ethers } = require('ethers');

// 配置
const FACTORY_ADDRESS = '0xbed30550aB282bED6A6ED57F23E9C99FAd8b7b76';
const INSURANCE_V8_ADDRESS = '0x72486eF40BB3729298369d608de85c612adb223e';
const USDC_ADDRESS = '0x036CbD53842c5426634e7929541eC2318f3dCF7e';
const RPC_URL = 'https://sepolia.base.org';

// ABIs
const FACTORY_ABI = [
  'function createProvider(uint256 initialDeposit) returns (address)',
  'function getUserProviders(address user) view returns (address[])',
  'function getAllProviders() view returns (address[])',
  'event ProviderCreated(address indexed owner, address indexed providerContract, uint256 initialDeposit)'
];

const USDC_ABI = [
  'function approve(address spender, uint256 amount) returns (bool)',
  'function balanceOf(address owner) view returns (uint256)',
  'function allowance(address owner, address spender) view returns (uint256)'
];

const INSURANCE_ABI = [
  'function getProviderInfo(address provider) view returns (bool isActive, uint256 poolBalance, uint256 totalLocked, uint256 successfulServices, uint256 failedServices, uint8 tier, uint256 registeredAt)'
];

async function main() {
  console.log('========================================');
  console.log('🧪 测试 ProviderFactory');
  console.log('========================================\n');

  // 连接网络
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const privateKey = process.env.PRIVATE_KEY || process.env.DEPLOYER_PRIVATE_KEY;

  if (!privateKey) {
    console.log('❌ 请设置 PRIVATE_KEY 环境变量');
    return;
  }

  const wallet = new ethers.Wallet(privateKey, provider);
  const walletAddress = await wallet.getAddress();

  console.log('👤 测试账户:', walletAddress);

  // 合约实例
  const factory = new ethers.Contract(FACTORY_ADDRESS, FACTORY_ABI, wallet);
  const usdc = new ethers.Contract(USDC_ADDRESS, USDC_ABI, wallet);
  const insurance = new ethers.Contract(INSURANCE_V8_ADDRESS, INSURANCE_ABI, provider);

  // 检查 USDC 余额
  const usdcBalance = await usdc.balanceOf(walletAddress);
  console.log('💰 USDC 余额:', ethers.formatUnits(usdcBalance, 6), 'USDC\n');

  if (usdcBalance < ethers.parseUnits('1', 6)) {
    console.log('⚠️  USDC 余额不足，需要至少 1 USDC');
    console.log('ℹ️  仅演示流程，不实际执行');
    console.log('');

    // 演示流程
    console.log('📋 使用流程:');
    console.log('────────────────────────────────────────');
    console.log('1. 授权 USDC:');
    console.log(`   await usdc.approve("${FACTORY_ADDRESS}", amount)`);
    console.log('');
    console.log('2. 创建 Provider:');
    console.log(`   const tx = await factory.createProvider(amount)`);
    console.log('   const receipt = await tx.wait()');
    console.log('');
    console.log('3. 获取 Provider 地址:');
    console.log('   const event = receipt.logs.find(log => log.eventName === "ProviderCreated")');
    console.log('   const providerAddress = event.args.providerContract');
    console.log('');
    console.log('4. 完成！你的 Provider 已创建并自动注册');
    console.log('');

    return;
  }

  // 步骤 1: 授权 USDC
  console.log('📋 步骤 1: 授权 USDC');
  console.log('────────────────────────────────────────');

  const amount = ethers.parseUnits('10', 6); // 10 USDC
  console.log('   授权金额: 10 USDC');

  const allowance = await usdc.allowance(walletAddress, FACTORY_ADDRESS);
  if (allowance < amount) {
    console.log('   正在授权...');
    const approveTx = await usdc.approve(FACTORY_ADDRESS, amount);
    await approveTx.wait();
    console.log('   ✅ 授权成功');
  } else {
    console.log('   ✅ 已授权');
  }
  console.log('');

  // 步骤 2: 创建 Provider
  console.log('📋 步骤 2: 创建 Provider');
  console.log('────────────────────────────────────────');
  console.log('   初始保险金: 10 USDC');
  console.log('');

  console.log('   ⏳ 正在创建 Provider...');
  const createTx = await factory.createProvider(amount);
  console.log('   交易哈希:', createTx.hash);

  const receipt = await createTx.wait();
  console.log('   ✅ 交易确认');
  console.log('');

  // 步骤 3: 获取 Provider 地址
  console.log('📋 步骤 3: 获取 Provider 地址');
  console.log('────────────────────────────────────────');

  // 从事件中获取 Provider 地址
  const event = receipt.logs
    .map(log => {
      try {
        return factory.interface.parseLog(log);
      } catch {
        return null;
      }
    })
    .find(e => e && e.name === 'ProviderCreated');

  if (!event) {
    console.log('   ❌ 无法找到 ProviderCreated 事件');
    return;
  }

  const providerAddress = event.args.providerContract;
  const depositAmount = event.args.initialDeposit;

  console.log('   ✅ Provider 创建成功!');
  console.log('   Provider 地址:', providerAddress);
  console.log('   初始保险金:', ethers.formatUnits(depositAmount, 6), 'USDC');
  console.log('');

  // 步骤 4: 验证 Provider 状态
  console.log('📋 步骤 4: 验证 Provider 状态');
  console.log('────────────────────────────────────────');

  const info = await insurance.getProviderInfo(providerAddress);

  const tierNames = ['None', 'Bronze', 'Silver', 'Gold'];

  console.log('   激活状态:', info.isActive ? '✅ 已激活' : '❌ 未激活');
  console.log('   保险池余额:', ethers.formatUnits(info.poolBalance, 6), 'USDC');
  console.log('   已锁定金额:', ethers.formatUnits(info.totalLocked, 6), 'USDC');
  console.log('   Provider 等级:', tierNames[Number(info.tier)]);
  console.log('   注册时间:', new Date(Number(info.registeredAt) * 1000).toLocaleString());
  console.log('');

  // 步骤 5: 获取用户的所有 Provider
  console.log('📋 步骤 5: 获取用户的所有 Provider');
  console.log('────────────────────────────────────────');

  const userProviders = await factory.getUserProviders(walletAddress);
  console.log(`   你拥有 ${userProviders.length} 个 Provider:`);
  userProviders.forEach((addr, i) => {
    console.log(`   ${i + 1}. ${addr}`);
  });
  console.log('');

  console.log('========================================');
  console.log('✅ 测试完成!');
  console.log('========================================\n');

  console.log('🎉 总结:');
  console.log('   ✓ 成功授权 USDC');
  console.log('   ✓ 成功创建 Provider 合约');
  console.log('   ✓ Provider 自动注册到 Insurance V8');
  console.log('   ✓ Provider 状态正常');
  console.log('');

  console.log('🔗 区块浏览器:');
  console.log(`   Provider 合约: https://sepolia.basescan.org/address/${providerAddress}`);
  console.log(`   创建交易: https://sepolia.basescan.org/tx/${createTx.hash}`);
  console.log('');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('❌ 测试失败:', error);
    process.exit(1);
  });
