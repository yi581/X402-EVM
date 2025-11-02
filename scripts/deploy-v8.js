/**
 * Deploy X402InsuranceV8 to Base Sepolia
 * 比例赔付与延迟补偿版本
 */

const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

const BASE_SEPOLIA_CONFIG = {
    rpcUrl: process.env.BASE_SEPOLIA_RPC_URL || 'https://sepolia.base.org',
    chainId: 84532,
    usdc: '0x036CbD53842c5426634e7929541eC2318f3dCF7e'
};

async function main() {
    console.log('='.repeat(80));
    console.log('🚀 部署 X402InsuranceV8 - 比例赔付与延迟补偿版本');
    console.log('='.repeat(80));
    console.log('');

    // 连接到Base Sepolia
    const provider = new ethers.JsonRpcProvider(BASE_SEPOLIA_CONFIG.rpcUrl);
    const deployer = new ethers.Wallet(process.env.DEPLOYER_PRIVATE_KEY, provider);

    console.log('📍 网络: Base Sepolia');
    console.log(`📍 部署者: ${deployer.address}`);
    console.log(`📍 USDC地址: ${BASE_SEPOLIA_CONFIG.usdc}`);

    // 检查余额
    const balance = await provider.getBalance(deployer.address);
    console.log(`📍 ETH余额: ${ethers.formatEther(balance)} ETH`);
    console.log('');

    // 编译合约（如果需要）
    console.log('📦 编译V8合约...');
    const { execSync } = require('child_process');
    try {
        execSync('forge build', { stdio: 'inherit' });
        console.log('✅ 编译成功');
    } catch (error) {
        console.error('❌ 编译失败，请检查合约代码');
        process.exit(1);
    }

    // 读取编译后的合约
    const contractPath = path.join(__dirname, '../out/X402InsuranceV8.sol/X402InsuranceV8.json');
    if (!fs.existsSync(contractPath)) {
        console.error('❌ 合约编译文件不存在');
        process.exit(1);
    }

    const contractJson = JSON.parse(fs.readFileSync(contractPath, 'utf8'));
    const abi = contractJson.abi;
    const bytecode = contractJson.bytecode.object;

    // 部署合约
    console.log('');
    console.log('📦 开始部署V8合约...');
    const factory = new ethers.ContractFactory(abi, bytecode, deployer);

    const contract = await factory.deploy(
        BASE_SEPOLIA_CONFIG.usdc,  // USDC token address
        deployer.address           // Owner address
    );

    console.log(`📝 交易哈希: ${contract.deploymentTransaction().hash}`);
    console.log('⏳ 等待确认...');

    await contract.waitForDeployment();
    const contractAddress = await contract.getAddress();

    console.log('');
    console.log('✅ 合约部署成功！');
    console.log(`📍 合约地址: ${contractAddress}`);
    console.log(`🔗 查看: https://sepolia.basescan.org/address/${contractAddress}`);

    // 保存部署信息
    const deploymentInfo = {
        network: 'base-sepolia',
        contractName: 'X402InsuranceV8',
        contractAddress: contractAddress,
        deployer: deployer.address,
        usdcToken: BASE_SEPOLIA_CONFIG.usdc,
        deployedAt: new Date().toISOString(),
        transactionHash: contract.deploymentTransaction().hash,
        features: [
            '比例赔付机制 - 资金不足时按比例支付',
            '延迟补偿系统 - 记录未付部分待后续补偿',
            '自动补偿触发 - Provider充值时自动补偿',
            '继续比例分配 - 补偿时继续按比例而非先到先得',
            '池永不为负 - 保持系统稳定性'
        ],
        improvements: [
            '解决了V7完全拒绝索赔的问题',
            '客户至少能获得部分赔付',
            'Provider充值后自动补偿所有待付索赔',
            '公平的比例分配机制',
            '不会侵占其他Provider的资金'
        ]
    };

    const deploymentPath = path.join(__dirname, '../deployments/v8-deployment.json');
    fs.writeFileSync(deploymentPath, JSON.stringify(deploymentInfo, null, 2));
    console.log(`📁 部署信息已保存到: ${deploymentPath}`);

    // 更新.env文件
    const envPath = path.join(__dirname, '../.env');
    let envContent = fs.readFileSync(envPath, 'utf8');

    // 添加或更新V8地址
    if (envContent.includes('INSURANCE_V8_ADDRESS=')) {
        envContent = envContent.replace(/INSURANCE_V8_ADDRESS=.*/, `INSURANCE_V8_ADDRESS=${contractAddress}`);
    } else {
        envContent += `\n# X402InsuranceV8 (比例赔付与延迟补偿)\nINSURANCE_V8_ADDRESS=${contractAddress}\n`;
    }

    fs.writeFileSync(envPath, envContent);
    console.log('📝 .env文件已更新');

    // 验证合约状态
    console.log('');
    console.log('🔍 验证合约状态...');
    const deployedContract = new ethers.Contract(contractAddress, abi, provider);

    const owner = await deployedContract.owner();
    const usdcToken = await deployedContract.usdcToken();
    const minPoolBalance = await deployedContract.MIN_POOL_BALANCE();
    const penaltyRate = await deployedContract.PENALTY_RATE();
    const maxExposure = await deployedContract.MAX_EXPOSURE_RATIO();

    console.log(`  Owner: ${owner}`);
    console.log(`  USDC Token: ${usdcToken}`);
    console.log(`  最低池余额: ${ethers.formatUnits(minPoolBalance, 6)} USDC`);
    console.log(`  罚金率: ${Number(penaltyRate) / 100}%`);
    console.log(`  最大暴露率: ${Number(maxExposure) / 100}%`);

    console.log('');
    console.log('='.repeat(80));
    console.log('🎉 V8合约部署完成！');
    console.log('='.repeat(80));
    console.log('');
    console.log('📌 V8核心特性：');
    console.log('  1. ✅ 比例赔付：资金不足时按比例支付');
    console.log('  2. ✅ 延迟补偿：记录待付金额');
    console.log('  3. ✅ 自动补偿：充值时自动触发');
    console.log('  4. ✅ 继续比例分配：补偿仍按比例，非先到先得');
    console.log('  5. ✅ 系统稳定：池永不为负');
    console.log('');
    console.log('📌 相比V7的改进：');
    console.log('  - V7：资金不足时完全拒绝索赔');
    console.log('  - V8：资金不足时按比例支付，记录待补偿');
    console.log('');
    console.log('下一步：');
    console.log('  1. 运行测试脚本: node scripts/test-v8-proportional.js');
    console.log('  2. 测试比例赔付场景');
    console.log('  3. 测试自动补偿机制');
}

main().catch(error => {
    console.error('❌ 部署失败:', error);
    process.exit(1);
});