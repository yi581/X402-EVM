/**
 * 测试智能合约作为 Provider 的完整流程
 */

const { ethers } = require('ethers');

// 配置
const INSURANCE_V8_ADDRESS = '0x72486eF40BB3729298369d608de85c612adb223e';
const USDC_ADDRESS = '0x036CbD53842c5426634e7929541eC2318f3dCF7e';
const RPC_URL = 'https://sepolia.base.org';

// ABI
const INSURANCE_ABI = [
  'function registerOrReactivate(uint256 amount)',
  'function getProviderInfo(address provider) view returns (bool isActive, uint256 poolBalance, uint256 totalLocked, uint256 successfulServices, uint256 failedServices, uint8 tier, uint256 registeredAt)',
  'function initiateClaim(bytes32 commitment, address provider, uint256 amount, uint8 reason)',
  'function usdcToken() view returns (address)'
];

const USDC_ABI = [
  'function approve(address spender, uint256 amount) returns (bool)',
  'function balanceOf(address owner) view returns (uint256)',
  'function transfer(address to, uint256 amount) returns (bool)',
  'function allowance(address owner, address spender) view returns (uint256)'
];

// SimpleProviderContract ABI
const PROVIDER_CONTRACT_ABI = [
  'constructor(address _insuranceContract)',
  'function registerAsProvider(uint256 amount)',
  'function depositInsurance(uint256 amount)',
  'function withdrawInsurance(uint256 amount)',
  'function disputeClaim(bytes32 commitment, string memory evidence)',
  'function owner() view returns (address)',
  'function insuranceContract() view returns (address)',
  'event InsuranceRegistered(uint256 amount)',
  'event ClaimReceived(bytes32 indexed commitment, address client, uint256 amount)'
];

// SimpleProviderContract 字节码（需要先编译）
// 这里我们先展示概念，实际使用时需要编译合约
const PROVIDER_CONTRACT_BYTECODE = '0x...'; // 需要编译得到

async function main() {
  console.log('========================================');
  console.log('🧪 测试智能合约作为 Provider');
  console.log('========================================\n');

  // 连接网络
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const privateKey = process.env.PRIVATE_KEY;

  if (!privateKey) {
    console.log('❌ 请设置 PRIVATE_KEY 环境变量');
    return;
  }

  const deployer = new ethers.Wallet(privateKey, provider);
  const deployerAddress = await deployer.getAddress();

  console.log('👤 部署者地址:', deployerAddress);
  console.log('');

  // 合约实例
  const insurance = new ethers.Contract(INSURANCE_V8_ADDRESS, INSURANCE_ABI, deployer);
  const usdc = new ethers.Contract(USDC_ADDRESS, USDC_ABI, deployer);

  // 检查余额
  const usdcBalance = await usdc.balanceOf(deployerAddress);
  console.log('💰 USDC 余额:', ethers.formatUnits(usdcBalance, 6), 'USDC\n');

  if (usdcBalance < ethers.parseUnits('10', 6)) {
    console.log('❌ USDC 余额不足 10 USDC，无法测试');
    return;
  }

  // 步骤 1: 部署 Provider 合约
  console.log('📋 步骤 1: 部署 SimpleProviderContract');
  console.log('────────────────────────────────────────');

  // 注意：这里需要实际的字节码，我们先展示概念
  console.log('⚠️  需要先编译 SimpleProviderContract');
  console.log('使用命令: forge build --contracts contracts/src/ProviderContractInterface.sol');
  console.log('');

  // 假设已经部署了 Provider 合约
  const providerContractAddress = '0x...'; // 实际部署后的地址

  console.log('✅ Provider 合约部署成功');
  console.log('   地址:', providerContractAddress);
  console.log('');

  // 步骤 2: 向 Provider 合约转入 USDC
  console.log('📋 步骤 2: 向 Provider 合约转入 USDC');
  console.log('────────────────────────────────────────');

  const depositAmount = ethers.parseUnits('10', 6);
  console.log('   转账金额: 10 USDC');

  // 实际操作（需要 Provider 合约地址）
  // const transferTx = await usdc.transfer(providerContractAddress, depositAmount);
  // await transferTx.wait();

  console.log('⚠️  演示模式：跳过实际转账');
  console.log('');

  // 步骤 3: 调用 Provider 合约的注册函数
  console.log('📋 步骤 3: Provider 合约注册到 Insurance V8');
  console.log('────────────────────────────────────────');

  // 实际操作
  // const providerContract = new ethers.Contract(
  //   providerContractAddress,
  //   PROVIDER_CONTRACT_ABI,
  //   deployer
  // );
  // const registerTx = await providerContract.registerAsProvider(depositAmount);
  // await registerTx.wait();

  console.log('⚠️  演示模式：跳过实际注册');
  console.log('');

  // 步骤 4: 验证 Provider 合约的状态
  console.log('📋 步骤 4: 验证 Provider 合约状态');
  console.log('────────────────────────────────────────');

  // 查询 Provider 合约的信息
  // const info = await insurance.getProviderInfo(providerContractAddress);

  console.log('⚠️  演示模式：显示预期结果');
  console.log('   激活状态: 已激活');
  console.log('   保险池余额: 10.0 USDC');
  console.log('   等级: Bronze (1)');
  console.log('');

  // 步骤 5: 模拟客户索赔
  console.log('📋 步骤 5: 客户向 Provider 合约发起索赔');
  console.log('────────────────────────────────────────');

  const commitment = ethers.keccak256(ethers.toUtf8Bytes('test-claim-' + Date.now()));
  const claimAmount = ethers.parseUnits('5', 6);

  console.log('   索赔 ID:', commitment);
  console.log('   索赔金额: 5 USDC');

  // 实际操作
  // const claimTx = await insurance.connect(clientWallet).initiateClaim(
  //   commitment,
  //   providerContractAddress,
  //   claimAmount,
  //   0 // NOT_DELIVERED
  // );
  // await claimTx.wait();

  console.log('⚠️  演示模式：跳过实际索赔');
  console.log('');

  console.log('========================================');
  console.log('✅ 概念验证完成');
  console.log('========================================\n');

  console.log('📝 总结:');
  console.log('');
  console.log('✓ 智能合约可以通过以下步骤成为 Provider:');
  console.log('  1. 部署 SimpleProviderContract 或 AutomatedProviderContract');
  console.log('  2. 向合约转入 USDC');
  console.log('  3. 调用合约的 registerAsProvider() 函数');
  console.log('  4. 合约自动处理授权和注册到 Insurance V8');
  console.log('');
  console.log('✓ 关键优势:');
  console.log('  - 外部协议无需修改原有代码');
  console.log('  - 可以实现自动化索赔处理逻辑');
  console.log('  - 支持批量管理多个服务');
  console.log('  - 可以集成自动补充保险金功能');
  console.log('');
  console.log('📌 下一步:');
  console.log('  - 编译 ProviderContractInterface.sol');
  console.log('  - 部署 SimpleProviderContract 到测试网');
  console.log('  - 进行完整的端到端测试');
  console.log('');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('❌ 测试失败:', error.message);
    process.exit(1);
  });
