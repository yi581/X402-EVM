/**
 * X402InsuranceV8 简单测试
 * 逐步测试每个功能
 */

const { ethers } = require('ethers');
require('dotenv').config();

const BASE_SEPOLIA_CONFIG = {
    rpcUrl: process.env.BASE_SEPOLIA_RPC_URL || 'https://sepolia.base.org',
    usdc: '0x036CbD53842c5426634e7929541eC2318f3dCF7e'
};

// V8合约地址
const INSURANCE_V8_ADDRESS = '0x72486eF40BB3729298369d608de85c612adb223e';

// V8 ABI
const V8_ABI = [
    'function registerOrReactivate(uint256 amount)',
    'function getProviderInfo(address provider) view returns (bool isActive, uint256 poolBalance, uint256 totalLocked, uint256 successfulServices, uint256 failedServices, uint8 tier, uint256 registeredAt)',
    'function MIN_POOL_BALANCE() view returns (uint256)',
    'function owner() view returns (address)'
];

// USDC ABI
const USDC_ABI = [
    'function balanceOf(address owner) view returns (uint256)',
    'function approve(address spender, uint256 amount) returns (bool)',
    'function allowance(address owner, address spender) view returns (uint256)'
];

function formatUsdc(amount) {
    return ethers.formatUnits(amount, 6);
}

function parseUsdc(amount) {
    return ethers.parseUnits(amount.toString(), 6);
}

async function main() {
    console.log('='.repeat(80));
    console.log('🧪 X402InsuranceV8 简单测试');
    console.log('='.repeat(80));
    console.log('');

    const provider = new ethers.JsonRpcProvider(BASE_SEPOLIA_CONFIG.rpcUrl);
    const insurance = new ethers.Contract(INSURANCE_V8_ADDRESS, V8_ABI, provider);
    const usdc = new ethers.Contract(BASE_SEPOLIA_CONFIG.usdc, USDC_ABI, provider);

    const deployer = new ethers.Wallet(process.env.DEPLOYER_PRIVATE_KEY, provider);

    console.log(`📍 V8合约地址: ${INSURANCE_V8_ADDRESS}`);
    console.log(`📍 测试账户: ${deployer.address}`);
    console.log('');

    // 1. 检查基本信息
    console.log('1️⃣ 检查基本信息');
    console.log('-'.repeat(40));

    const owner = await insurance.owner();
    const minPoolBalance = await insurance.MIN_POOL_BALANCE();
    console.log(`合约Owner: ${owner}`);
    console.log(`最低池余额: ${formatUsdc(minPoolBalance)} USDC`);

    // 检查USDC余额
    const usdcBalance = await usdc.balanceOf(deployer.address);
    console.log(`账户USDC余额: ${formatUsdc(usdcBalance)} USDC`);

    // 2. 检查Provider状态（注册前）
    console.log('');
    console.log('2️⃣ 检查Provider状态（注册前）');
    console.log('-'.repeat(40));

    const providerInfoBefore = await insurance.getProviderInfo(deployer.address);
    console.log(`激活状态: ${providerInfoBefore.isActive}`);
    console.log(`池余额: ${formatUsdc(providerInfoBefore.poolBalance)} USDC`);
    console.log(`注册时间: ${providerInfoBefore.registeredAt}`);

    // 3. 检查授权
    console.log('');
    console.log('3️⃣ 检查USDC授权');
    console.log('-'.repeat(40));

    const currentAllowance = await usdc.allowance(deployer.address, INSURANCE_V8_ADDRESS);
    console.log(`当前授权额度: ${formatUsdc(currentAllowance)} USDC`);

    if (currentAllowance < parseUsdc('10')) {
        console.log('授权不足，进行授权...');
        try {
            const approveTx = await usdc.connect(deployer).approve(INSURANCE_V8_ADDRESS, parseUsdc('100'));
            console.log(`授权交易: ${approveTx.hash}`);
            const receipt = await approveTx.wait();
            console.log(`✅ 授权成功，区块: ${receipt.blockNumber}`);
        } catch (error) {
            console.error(`❌ 授权失败: ${error.message}`);
            return;
        }
    }

    // 再次检查授权
    const newAllowance = await usdc.allowance(deployer.address, INSURANCE_V8_ADDRESS);
    console.log(`新授权额度: ${formatUsdc(newAllowance)} USDC`);

    // 4. 注册Provider
    console.log('');
    console.log('4️⃣ 注册Provider');
    console.log('-'.repeat(40));

    const depositAmount = parseUsdc('10');
    console.log(`准备存入: ${formatUsdc(depositAmount)} USDC`);

    try {
        const registerTx = await insurance.connect(deployer).registerOrReactivate(depositAmount);
        console.log(`注册交易: ${registerTx.hash}`);
        const receipt = await registerTx.wait();
        console.log(`✅ 交易成功，区块: ${receipt.blockNumber}`);
        console.log(`Gas使用: ${receipt.gasUsed.toString()}`);

        // 检查事件
        if (receipt.logs.length > 0) {
            console.log(`事件数量: ${receipt.logs.length}`);
        }
    } catch (error) {
        console.error(`❌ 注册失败: ${error.message}`);
        if (error.reason) console.error(`原因: ${error.reason}`);
        if (error.data) console.error(`数据: ${error.data}`);
    }

    // 5. 检查注册后状态
    console.log('');
    console.log('5️⃣ 检查Provider状态（注册后）');
    console.log('-'.repeat(40));

    const providerInfoAfter = await insurance.getProviderInfo(deployer.address);
    console.log(`激活状态: ${providerInfoAfter.isActive}`);
    console.log(`池余额: ${formatUsdc(providerInfoAfter.poolBalance)} USDC`);
    console.log(`锁定金额: ${formatUsdc(providerInfoAfter.totalLocked)} USDC`);
    console.log(`注册时间: ${providerInfoAfter.registeredAt}`);

    // 检查USDC余额变化
    const usdcBalanceAfter = await usdc.balanceOf(deployer.address);
    console.log(`账户USDC余额: ${formatUsdc(usdcBalanceAfter)} USDC`);
    console.log(`USDC变化: ${formatUsdc(usdcBalance - usdcBalanceAfter)} USDC`);

    // 检查合约USDC余额
    const contractUsdcBalance = await usdc.balanceOf(INSURANCE_V8_ADDRESS);
    console.log(`合约USDC余额: ${formatUsdc(contractUsdcBalance)} USDC`);

    console.log('');
    console.log('✅ 测试完成');
}

main().catch(error => {
    console.error('❌ 测试失败:', error);
    process.exit(1);
});