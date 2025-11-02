/**
 * Client示例：使用Provider Registry查询认证Provider
 *
 * 这个例子展示如何：
 * 1. 查询所有认证的Provider
 * 2. 选择一个Provider进行支付
 * 3. 验证Provider的保险状态
 */

const axios = require('axios');
const { ethers } = require('ethers');

// ============ 配置 ============
const CONFIG = {
    // Provider Registry API
    REGISTRY_API: 'http://localhost:3005',

    // 您的钱包私钥
    PRIVATE_KEY: '0x...your-private-key...',

    // Base Sepolia RPC
    RPC_URL: 'https://sepolia.base.org',

    // 保险合约地址
    INSURANCE_ADDRESS: '0x...insurance-address...',

    // USDC地址（Base Sepolia）
    USDC_ADDRESS: '0x036CbD53842c5426634e7929541eC2318f3dCF7e'
};

// ============ 带Registry的Client ============
class X402ClientWithRegistry {
    constructor() {
        this.provider = new ethers.JsonRpcProvider(CONFIG.RPC_URL);
        this.wallet = new ethers.Wallet(CONFIG.PRIVATE_KEY, this.provider);
        this.address = this.wallet.address;
    }

    /**
     * 1. 获取所有认证的Provider列表
     */
    async getProviderList() {
        try {
            console.log('📋 查询认证Provider列表...');

            const response = await axios.get(`${CONFIG.REGISTRY_API}/api/providers`);

            if (response.data.success) {
                const providers = response.data.providers;
                console.log(`✅ 找到 ${providers.length} 个认证Provider\n`);

                // 显示Provider信息
                providers.forEach(p => {
                    console.log(`🏢 ${p.name}`);
                    console.log(`   地址: ${p.address}`);
                    console.log(`   API: ${p.apiEndpoint}`);
                    console.log(`   等级: ${p.tier} | 余额: ${p.poolBalance} USDC`);
                    console.log(`   成功率: ${p.successRate}%`);
                    console.log(`   服务:`);
                    p.services.forEach(s => {
                        console.log(`     - ${s.path} (${s.price} USDC): ${s.description}`);
                    });
                    console.log('');
                });

                return providers;
            }

            return [];

        } catch (error) {
            console.error('❌ 无法获取Provider列表:', error.message);
            return [];
        }
    }

    /**
     * 2. 搜索特定类型的Provider
     */
    async searchProviders(query) {
        try {
            console.log(`🔍 搜索: "${query}"`);

            const response = await axios.get(
                `${CONFIG.REGISTRY_API}/api/providers/search/${encodeURIComponent(query)}`
            );

            if (response.data.success) {
                const providers = response.data.providers;
                console.log(`✅ 找到 ${providers.length} 个匹配的Provider\n`);
                return providers;
            }

            return [];

        } catch (error) {
            console.error('❌ 搜索失败:', error.message);
            return [];
        }
    }

    /**
     * 3. 检查特定Provider的健康状态
     */
    async checkProviderHealth(address) {
        try {
            console.log(`🏥 检查Provider健康状态: ${address}`);

            const response = await axios.get(
                `${CONFIG.REGISTRY_API}/api/providers/${address}/health`
            );

            if (response.data.success) {
                const status = response.data.status;
                const message = response.data.message;

                const statusEmoji = {
                    'healthy': '✅',
                    'warning': '⚠️',
                    'critical': '🚨',
                    'offline': '❌'
                };

                console.log(`${statusEmoji[status]} 状态: ${status} - ${message}\n`);
                return { status, message };
            }

            return { status: 'unknown', message: 'Cannot check' };

        } catch (error) {
            console.error('❌ 健康检查失败:', error.message);
            return { status: 'error', message: error.message };
        }
    }

    /**
     * 4. 选择最佳Provider
     */
    async selectBestProvider(service) {
        const providers = await this.getProviderList();

        // 筛选提供该服务的Provider
        const validProviders = providers.filter(p => {
            // 检查是否提供该服务
            const hasService = p.services.some(s =>
                s.path.includes(service) || s.description.includes(service)
            );

            // 检查余额是否充足
            const hasBalance = parseFloat(p.poolBalance) >= 10;

            // 检查成功率
            const hasGoodRate = p.successRate >= 95;

            return hasService && hasBalance && hasGoodRate;
        });

        if (validProviders.length === 0) {
            console.log('⚠️  没有找到合适的Provider');
            return null;
        }

        // 按成功率和等级排序
        validProviders.sort((a, b) => {
            // 优先级：成功率 > 等级 > 余额
            if (a.successRate !== b.successRate) {
                return b.successRate - a.successRate;
            }

            const tierOrder = { 'Platinum': 4, 'Gold': 3, 'Silver': 2, 'Bronze': 1 };
            if (tierOrder[a.tier] !== tierOrder[b.tier]) {
                return tierOrder[b.tier] - tierOrder[a.tier];
            }

            return parseFloat(b.poolBalance) - parseFloat(a.poolBalance);
        });

        const best = validProviders[0];
        console.log(`🏆 选择最佳Provider: ${best.name} (${best.tier}, ${best.successRate}%)\n`);

        return best;
    }

    /**
     * 5. 使用选定的Provider进行支付
     */
    async payToProvider(provider, servicePath) {
        try {
            const apiUrl = `${provider.apiEndpoint}${servicePath}`;
            console.log(`💳 请求付费API: ${apiUrl}`);

            // 找到服务价格
            const service = provider.services.find(s => s.path === servicePath);
            const expectedPrice = service ? service.price : '1.0';

            console.log(`   预期价格: ${expectedPrice} USDC`);
            console.log(`   Provider: ${provider.name}`);
            console.log(`   地址: ${provider.address}`);

            // 第一次请求
            let response = await axios.get(apiUrl, {
                validateStatus: status => true
            });

            if (response.status === 402) {
                console.log('   需要支付...');

                const paymentInfo = response.data.accepts[0];

                // 验证是否是我们认证的Provider
                if (paymentInfo.insuranceProtected) {
                    console.log('   ✅ Provider有保险保护');
                } else {
                    console.log('   ⚠️  Provider无保险保护');
                }

                // 创建支付
                const payment = await this.createPayment(
                    paymentInfo.payTo,
                    paymentInfo.maxAmountRequired
                );

                // 带支付信息重新请求
                response = await axios.get(apiUrl, {
                    headers: {
                        'X-PAYMENT': payment
                    }
                });

                if (response.status === 200) {
                    console.log('   ✅ 支付成功！\n');
                    return response.data;
                }
            }

            return response.data;

        } catch (error) {
            console.error('❌ 支付失败:', error.message);
            throw error;
        }
    }

    /**
     * 创建支付签名
     */
    async createPayment(to, amount) {
        const payment = {
            from: this.address,
            to: to,
            amount: amount,
            asset: CONFIG.USDC_ADDRESS,
            network: 'base-sepolia',
            nonce: Date.now(),
            timestamp: Math.floor(Date.now() / 1000)
        };

        const message = ethers.solidityPackedKeccak256(
            ['address', 'address', 'uint256', 'uint256'],
            [payment.from, payment.to, payment.amount, payment.nonce]
        );

        const signature = await this.wallet.signMessage(ethers.getBytes(message));

        return Buffer.from(JSON.stringify({
            ...payment,
            signature
        })).toString('base64');
    }
}

// ============ 使用示例 ============

async function demonstrateRegistry() {
    console.log('========================================');
    console.log('X402 Client + Registry 示例');
    console.log('========================================\n');

    const client = new X402ClientWithRegistry();

    // 1. 获取所有Provider
    console.log('【步骤1：获取所有认证Provider】');
    const allProviders = await client.getProviderList();

    // 2. 搜索特定服务
    console.log('【步骤2：搜索天气服务】');
    const weatherProviders = await client.searchProviders('天气');

    // 3. 检查Provider健康状态
    if (allProviders.length > 0) {
        console.log('【步骤3：检查Provider健康状态】');
        await client.checkProviderHealth(allProviders[0].address);
    }

    // 4. 选择最佳Provider
    console.log('【步骤4：自动选择最佳Provider】');
    const bestProvider = await client.selectBestProvider('weather');

    // 5. 使用选定的Provider
    if (bestProvider) {
        console.log('【步骤5：向选定的Provider支付】');

        // 检查配置
        if (CONFIG.PRIVATE_KEY === '0x...your-private-key...') {
            console.log('⚠️  请先配置私钥才能进行支付');
            console.log('   编辑 CONFIG.PRIVATE_KEY');
        } else {
            // 选择一个服务进行支付
            const service = bestProvider.services[0];
            if (service) {
                try {
                    const result = await client.payToProvider(bestProvider, service.path);
                    console.log('📊 获得数据:', result);
                } catch (error) {
                    console.log('支付演示跳过（需要真实Provider运行）');
                }
            }
        }
    }

    console.log('\n========================================');
    console.log('演示完成！');
    console.log('========================================');
}

// ============ 快速函数 ============

/**
 * 一行代码：获取最便宜的Provider
 */
async function getCheapestProvider(serviceName) {
    const client = new X402ClientWithRegistry();
    const providers = await client.searchProviders(serviceName);

    if (providers.length === 0) return null;

    // 按价格排序
    providers.sort((a, b) => {
        const priceA = Math.min(...a.services.map(s => parseFloat(s.price)));
        const priceB = Math.min(...b.services.map(s => parseFloat(s.price)));
        return priceA - priceB;
    });

    return providers[0];
}

/**
 * 一行代码：获取成功率最高的Provider
 */
async function getMostReliableProvider(serviceName) {
    const client = new X402ClientWithRegistry();
    const providers = await client.searchProviders(serviceName);

    if (providers.length === 0) return null;

    // 按成功率排序
    providers.sort((a, b) => b.successRate - a.successRate);

    return providers[0];
}

// ============ 导出 ============

module.exports = {
    X402ClientWithRegistry,
    getCheapestProvider,
    getMostReliableProvider,
    demonstrateRegistry
};

// ============ 直接运行 ============

if (require.main === module) {
    demonstrateRegistry().catch(console.error);
}

/* ============================================
   总结：Client如何使用Registry

   1. 查询所有认证Provider:
      GET http://localhost:3005/api/providers

   2. 搜索特定服务:
      GET http://localhost:3005/api/providers/search/weather

   3. 检查Provider健康:
      GET http://localhost:3005/api/providers/:address/health

   4. 获取特定Provider信息:
      GET http://localhost:3005/api/providers/:address

   优势：
   - Client可以发现所有认证的Provider
   - 可以比较价格和服务质量
   - 可以选择成功率最高的Provider
   - 可以避免使用未认证的Provider
   - 完全透明的Provider信息

   这解决了您提出的问题：
   "client如何查询是不是有认证的？"
   答：通过Registry API查询！
============================================ */