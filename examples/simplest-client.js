/**
 * 最简单的X402 Client实现
 *
 * 只需要5分钟就能集成！
 */

const axios = require('axios');
const { ethers } = require('ethers');

// ============ 配置（只需要改这里）============
const CONFIG = {
    // 您的钱包私钥
    PRIVATE_KEY: '0x...your-private-key...',

    // Base Sepolia RPC
    RPC_URL: 'https://sepolia.base.org',

    // 保险合约地址（部署后获得）
    INSURANCE_ADDRESS: '0x...insurance-address...',

    // USDC地址（Base Sepolia）
    USDC_ADDRESS: '0x036CbD53842c5426634e7929541eC2318f3dCF7e'
};

// ============ 超简单的X402 Client ============
class SuperSimpleX402Client {
    constructor() {
        // 初始化钱包
        this.provider = new ethers.JsonRpcProvider(CONFIG.RPC_URL);
        this.wallet = new ethers.Wallet(CONFIG.PRIVATE_KEY, this.provider);
        this.address = this.wallet.address;

        console.log('Client初始化成功，地址:', this.address);
    }

    /**
     * 请求付费API（全自动处理）
     */
    async request(url) {
        try {
            console.log('\n📡 请求API:', url);

            // Step 1: 尝试请求
            let response = await axios.get(url, {
                validateStatus: status => true // 接受所有状态码
            });

            // Step 2: 如果需要支付（返回402）
            if (response.status === 402) {
                console.log('💳 需要支付，金额:', response.data.accepts[0].maxAmountRequired / 1000000, 'USDC');

                // 获取支付信息
                const paymentInfo = response.data.accepts[0];
                const provider = paymentInfo.payTo;
                const amount = paymentInfo.maxAmountRequired;

                // Step 3: 检查Provider保险（可选但推荐）
                const hasInsurance = await this.checkProviderInsurance(provider);
                if (hasInsurance) {
                    console.log('✅ Provider已认证，有保险保护');
                } else {
                    console.log('⚠️  Provider未认证，无保险保护');
                    // 可以选择是否继续
                }

                // Step 4: 创建支付
                const payment = await this.createPayment(provider, amount);

                // Step 5: 带支付信息重新请求
                console.log('🔄 发送支付...');
                response = await axios.get(url, {
                    headers: {
                        'X-PAYMENT': payment
                    }
                });

                if (response.status === 200) {
                    console.log('✅ 支付成功，获得数据！');
                }
            }

            return response.data;

        } catch (error) {
            console.error('❌ 请求失败:', error.message);
            throw error;
        }
    }

    /**
     * 检查Provider是否有保险
     */
    async checkProviderInsurance(providerAddress) {
        try {
            // 简化的ABI，只需要查询功能
            const abi = [
                "function getProviderInfo(address) view returns (uint256, uint256, uint256, uint8, bool, uint256)"
            ];

            const insurance = new ethers.Contract(CONFIG.INSURANCE_ADDRESS, abi, this.provider);
            const info = await insurance.getProviderInfo(providerAddress);

            const isActive = info[4]; // 第5个返回值是isActive
            return isActive;

        } catch (error) {
            console.log('无法查询保险状态:', error.message);
            return false;
        }
    }

    /**
     * 创建支付签名
     */
    async createPayment(to, amount) {
        // 创建支付对象
        const payment = {
            from: this.address,
            to: to,
            amount: amount,
            asset: CONFIG.USDC_ADDRESS,
            network: 'base-sepolia',
            nonce: Date.now(),
            timestamp: Math.floor(Date.now() / 1000)
        };

        // 创建签名消息
        const message = ethers.solidityPackedKeccak256(
            ['address', 'address', 'uint256', 'uint256'],
            [payment.from, payment.to, payment.amount, payment.nonce]
        );

        // 签名
        const signature = await this.wallet.signMessage(ethers.getBytes(message));

        // 组合支付数据
        const signedPayment = {
            ...payment,
            signature: signature
        };

        // 编码为Base64
        return Buffer.from(JSON.stringify(signedPayment)).toString('base64');
    }

    /**
     * 查询余额（辅助功能）
     */
    async getBalance() {
        const abi = ["function balanceOf(address) view returns (uint256)"];
        const usdc = new ethers.Contract(CONFIG.USDC_ADDRESS, abi, this.provider);
        const balance = await usdc.balanceOf(this.address);
        return ethers.formatUnits(balance, 6);
    }
}

// ============ 使用示例 ============

async function example() {
    // 1. 创建Client（一行代码）
    const client = new SuperSimpleX402Client();

    // 2. 查询余额
    const balance = await client.getBalance();
    console.log('💰 USDC余额:', balance, 'USDC');

    // 3. 请求付费API（自动处理支付）
    const data = await client.request('https://api.provider.com/paid/weather');
    console.log('📊 获得数据:', data);

    // 就这么简单！
}

// ============ 更简单的封装 ============

/**
 * 一行代码完成支付请求！
 */
async function payAndGet(url) {
    const client = new SuperSimpleX402Client();
    return await client.request(url);
}

// 使用：
// const data = await payAndGet('https://api.provider.com/data');

// ============ Provider认证检查工具 ============

/**
 * 批量检查哪些Provider是我们认证的
 */
async function checkProviders(providerList) {
    const client = new SuperSimpleX402Client();
    const results = {};

    for (const provider of providerList) {
        results[provider] = await client.checkProviderInsurance(provider);
    }

    console.log('\n🔍 Provider认证状态:');
    for (const [address, isInsured] of Object.entries(results)) {
        console.log(`${address}: ${isInsured ? '✅ 已认证' : '❌ 未认证'}`);
    }

    return results;
}

// ============ 导出 ============

module.exports = {
    SuperSimpleX402Client,
    payAndGet,
    checkProviders
};

// ============ 直接运行示例 ============

if (require.main === module) {
    // 测试函数
    async function test() {
        console.log('========================================');
        console.log('X402 超简单Client示例');
        console.log('========================================\n');

        // 检查配置
        if (CONFIG.PRIVATE_KEY === '0x...your-private-key...') {
            console.log('⚠️  请先配置您的私钥！');
            console.log('编辑CONFIG.PRIVATE_KEY');
            return;
        }

        if (CONFIG.INSURANCE_ADDRESS === '0x...insurance-address...') {
            console.log('⚠️  请先配置保险合约地址！');
            console.log('编辑CONFIG.INSURANCE_ADDRESS');
            return;
        }

        // 运行示例
        try {
            await example();
        } catch (error) {
            console.error('测试失败:', error);
        }
    }

    test();
}

/* ============================================
   集成步骤总结（给开发者的说明）：

   1. 安装依赖:
      npm install axios ethers

   2. 复制这个文件到您的项目

   3. 修改CONFIG配置:
      - PRIVATE_KEY: 您的钱包私钥
      - INSURANCE_ADDRESS: 保险合约地址

   4. 使用（一行代码）:
      const data = await payAndGet('https://api.com/data');

   就这么简单！不需要理解复杂的协议细节。

   常见问题：

   Q: 如何获得测试USDC？
   A: 访问 https://faucet.x402.io

   Q: 如何知道Provider是否认证？
   A: checkProviderInsurance()会自动检查

   Q: 支付失败怎么办？
   A: 24小时后自动退款

   Q: 需要支付保险费吗？
   A: 不需要！完全免费
============================================ */