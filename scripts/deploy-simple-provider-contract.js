/**
 * 部署 SimpleProviderContract 并测试作为 Provider 的功能
 */

require('dotenv').config();
const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

// 配置
const INSURANCE_V8_ADDRESS = '0x72486eF40BB3729298369d608de85c612adb223e';
const USDC_ADDRESS = '0x036CbD53842c5426634e7929541eC2318f3dCF7e';
const RPC_URL = 'https://sepolia.base.org';

// USDC ABI
const USDC_ABI = [
  'function approve(address spender, uint256 amount) returns (bool)',
  'function balanceOf(address owner) view returns (uint256)',
  'function transfer(address to, uint256 amount) returns (bool)',
  'function allowance(address owner, address spender) view returns (uint256)'
];

// Insurance ABI
const INSURANCE_ABI = [
  'function getProviderInfo(address provider) view returns (bool isActive, uint256 poolBalance, uint256 totalLocked, uint256 successfulServices, uint256 failedServices, uint8 tier, uint256 registeredAt)',
  'function initiateClaim(bytes32 commitment, address provider, uint256 amount, uint8 reason)'
];

async function main() {
  console.log('========================================');
  console.log('🚀 部署 SimpleProviderContract');
  console.log('========================================\n');

  // 连接网络
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const privateKey = process.env.PRIVATE_KEY || process.env.DEPLOYER_PRIVATE_KEY;

  if (!privateKey) {
    console.log('❌ 请设置 PRIVATE_KEY 或 DEPLOYER_PRIVATE_KEY 环境变量');
    return;
  }

  const deployer = new ethers.Wallet(privateKey, provider);
  const deployerAddress = await deployer.getAddress();

  console.log('👤 部署者地址:', deployerAddress);

  // 检查余额
  const usdc = new ethers.Contract(USDC_ADDRESS, USDC_ABI, deployer);
  const usdcBalance = await usdc.balanceOf(deployerAddress);
  const ethBalance = await provider.getBalance(deployerAddress);

  console.log('💰 余额:');
  console.log('   USDC:', ethers.formatUnits(usdcBalance, 6), 'USDC');
  console.log('   ETH:', ethers.formatEther(ethBalance), 'ETH');
  console.log('');

  // 读取编译的合约
  const artifactPath = path.join(
    __dirname,
    '../out/ProviderContractInterface.sol/SimpleProviderContract.json'
  );

  if (!fs.existsSync(artifactPath)) {
    console.log('❌ 合约未编译，请先运行: forge build');
    return;
  }

  const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'));
  const contractABI = artifact.abi;
  const contractBytecode = artifact.bytecode.object;

  // 步骤 1: 部署 SimpleProviderContract
  console.log('📋 步骤 1: 部署 SimpleProviderContract');
  console.log('────────────────────────────────────────');
  console.log('   Insurance V8:', INSURANCE_V8_ADDRESS);

  const factory = new ethers.ContractFactory(contractABI, contractBytecode, deployer);

  console.log('⏳ 正在部署...');
  const providerContract = await factory.deploy(INSURANCE_V8_ADDRESS);
  await providerContract.waitForDeployment();

  const providerContractAddress = await providerContract.getAddress();
  console.log('✅ SimpleProviderContract 部署成功!');
  console.log('   地址:', providerContractAddress);
  console.log('');

  // 步骤 2: 向 Provider 合约转入 USDC
  console.log('📋 步骤 2: 向 Provider 合约转入 USDC');
  console.log('────────────────────────────────────────');

  const depositAmount = ethers.parseUnits('5', 6);
  console.log('   转账金额: 5 USDC');

  const transferTx = await usdc.transfer(providerContractAddress, depositAmount);
  console.log('   交易哈希:', transferTx.hash);

  await transferTx.wait();
  console.log('✅ USDC 转账成功');

  // 验证余额
  const contractUsdcBalance = await usdc.balanceOf(providerContractAddress);
  console.log('   合约 USDC 余额:', ethers.formatUnits(contractUsdcBalance, 6), 'USDC');
  console.log('');

  // 步骤 3: Provider 合约注册到 Insurance V8
  console.log('📋 步骤 3: Provider 合约注册到 Insurance V8');
  console.log('────────────────────────────────────────');
  console.log('   注册金额: 5 USDC');

  const registerTx = await providerContract.registerAsProvider(depositAmount);
  console.log('   交易哈希:', registerTx.hash);

  await registerTx.wait();
  console.log('✅ Provider 合约注册成功');
  console.log('');

  // 步骤 4: 验证 Provider 状态
  console.log('📋 步骤 4: 验证 Provider 状态');
  console.log('────────────────────────────────────────');

  const insurance = new ethers.Contract(INSURANCE_V8_ADDRESS, INSURANCE_ABI, deployer);
  const info = await insurance.getProviderInfo(providerContractAddress);

  const tierNames = ['None', 'Bronze', 'Silver', 'Gold'];

  console.log('   激活状态:', info.isActive ? '✅ 已激活' : '❌ 未激活');
  console.log('   保险池余额:', ethers.formatUnits(info.poolBalance, 6), 'USDC');
  console.log('   已锁定金额:', ethers.formatUnits(info.totalLocked, 6), 'USDC');
  console.log('   成功服务数:', info.successfulServices.toString());
  console.log('   失败服务数:', info.failedServices.toString());
  console.log('   Provider 等级:', tierNames[Number(info.tier)]);
  console.log('   注册时间:', new Date(Number(info.registeredAt) * 1000).toLocaleString());
  console.log('');

  // 保存部署信息
  const deploymentInfo = {
    network: 'Base Sepolia',
    timestamp: new Date().toISOString(),
    deployer: deployerAddress,
    contracts: {
      simpleProviderContract: providerContractAddress,
      insuranceV8: INSURANCE_V8_ADDRESS,
      usdc: USDC_ADDRESS
    },
    providerInfo: {
      isActive: info.isActive,
      poolBalance: ethers.formatUnits(info.poolBalance, 6),
      tier: tierNames[Number(info.tier)]
    }
  };

  const deploymentsDir = path.join(__dirname, '../deployments');
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }

  fs.writeFileSync(
    path.join(deploymentsDir, 'simple-provider-contract-deployment.json'),
    JSON.stringify(deploymentInfo, null, 2)
  );

  console.log('========================================');
  console.log('✅ 部署和注册完成!');
  console.log('========================================\n');

  console.log('📝 部署信息已保存到:');
  console.log('   deployments/simple-provider-contract-deployment.json');
  console.log('');

  console.log('🎯 下一步测试:');
  console.log('   1. 使用另一个账户作为 Client 发起索赔');
  console.log('   2. 测试 Provider 合约的争议功能');
  console.log('   3. 测试自动化 Provider 合约');
  console.log('');

  console.log('📌 关键发现:');
  console.log('   ✓ 智能合约可以成功注册为 Provider');
  console.log('   ✓ msg.sender 在注册时是合约地址');
  console.log('   ✓ 合约可以管理自己的 USDC 和授权');
  console.log('   ✓ 这证明了外部协议可以通过部署 Provider 合约来集成保险功能');
  console.log('');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('❌ 部署失败:', error);
    process.exit(1);
  });
