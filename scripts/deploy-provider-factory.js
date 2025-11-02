/**
 * 部署 ProviderFactory 合约到 Base Sepolia
 */

require('dotenv').config();
const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

// 配置
const INSURANCE_V8_ADDRESS = '0x72486eF40BB3729298369d608de85c612adb223e';
const USDC_ADDRESS = '0x036CbD53842c5426634e7929541eC2318f3dCF7e';
const RPC_URL = 'https://sepolia.base.org';

async function main() {
  console.log('========================================');
  console.log('🚀 部署 ProviderFactory');
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
  const ethBalance = await provider.getBalance(deployerAddress);
  console.log('💰 ETH 余额:', ethers.formatEther(ethBalance), 'ETH');
  console.log('');

  if (ethBalance < ethers.parseEther('0.001')) {
    console.log('⚠️  警告：ETH 余额可能不足以支付 gas 费用');
  }

  // 读取编译的合约
  const artifactPath = path.join(
    __dirname,
    '../out/ProviderFactory.sol/ProviderFactory.json'
  );

  if (!fs.existsSync(artifactPath)) {
    console.log('❌ 合约未编译，请先运行: forge build');
    return;
  }

  const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'));
  const contractABI = artifact.abi;
  const contractBytecode = artifact.bytecode.object;

  // 部署 ProviderFactory
  console.log('📋 部署 ProviderFactory');
  console.log('────────────────────────────────────────');
  console.log('   Insurance V8:', INSURANCE_V8_ADDRESS);
  console.log('   USDC:', USDC_ADDRESS);
  console.log('');

  const factory = new ethers.ContractFactory(contractABI, contractBytecode, deployer);

  console.log('⏳ 正在部署...');
  const providerFactory = await factory.deploy(INSURANCE_V8_ADDRESS, USDC_ADDRESS);
  await providerFactory.waitForDeployment();

  const factoryAddress = await providerFactory.getAddress();

  console.log('✅ ProviderFactory 部署成功!');
  console.log('   地址:', factoryAddress);
  console.log('');

  // 保存部署信息
  const deploymentInfo = {
    network: 'Base Sepolia',
    chainId: 84532,
    timestamp: new Date().toISOString(),
    deployer: deployerAddress,
    contracts: {
      providerFactory: factoryAddress,
      insuranceV8: INSURANCE_V8_ADDRESS,
      usdc: USDC_ADDRESS
    },
    usage: {
      step1: `await usdc.approve("${factoryAddress}", amount)`,
      step2: `await factory.createProvider(amount)`
    }
  };

  const deploymentsDir = path.join(__dirname, '../deployments');
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }

  fs.writeFileSync(
    path.join(deploymentsDir, 'provider-factory-deployment.json'),
    JSON.stringify(deploymentInfo, null, 2)
  );

  console.log('========================================');
  console.log('✅ 部署完成!');
  console.log('========================================\n');

  console.log('📝 部署信息已保存到:');
  console.log('   deployments/provider-factory-deployment.json');
  console.log('');

  console.log('🎯 使用方式:');
  console.log('');
  console.log('   // 1. 授权 USDC');
  console.log(`   await usdc.approve("${factoryAddress}", amount);`);
  console.log('');
  console.log('   // 2. 创建 Provider');
  console.log(`   await factory.createProvider(amount);`);
  console.log('');

  console.log('📌 重要地址:');
  console.log('   ProviderFactory:', factoryAddress);
  console.log('   Insurance V8:', INSURANCE_V8_ADDRESS);
  console.log('   USDC:', USDC_ADDRESS);
  console.log('');

  console.log('🔗 区块浏览器:');
  console.log(`   https://sepolia.basescan.org/address/${factoryAddress}`);
  console.log('');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('❌ 部署失败:', error);
    process.exit(1);
  });
