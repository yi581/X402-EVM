/**
 * Demo: 展示如何使用Provider Registry（无需钱包）
 *
 * 这个演示展示了Client如何：
 * 1. 查询所有认证的Provider
 * 2. 搜索特定服务
 * 3. 检查Provider健康状态
 * 4. 选择最佳Provider
 */

const axios = require('axios');

// Registry API地址
const REGISTRY_API = 'http://localhost:3005';

// ============ 演示函数 ============

/**
 * 1. 获取并显示所有Provider
 */
async function showAllProviders() {
    console.log('📋 查询所有认证的Provider...\n');

    try {
        const response = await axios.get(`${REGISTRY_API}/api/providers`);

        if (response.data.success) {
            const providers = response.data.providers;
            console.log(`找到 ${providers.length} 个认证的Provider：\n`);

            providers.forEach((p, index) => {
                console.log(`${index + 1}. ${p.name}`);
                console.log(`   地址: ${p.address}`);
                console.log(`   API端点: ${p.apiEndpoint}`);
                console.log(`   等级: ${p.tier}`);
                console.log(`   保险池余额: ${p.poolBalance} USDC`);
                console.log(`   成功率: ${p.successRate}%`);
                console.log(`   状态: ${p.isActive ? '✅ 活跃' : '❌ 离线'}`);
                console.log(`   服务列表:`);
                p.services.forEach(s => {
                    console.log(`     • ${s.description}`);
                    console.log(`       路径: ${s.path}`);
                    console.log(`       价格: ${s.price} USDC`);
                });
                console.log('');
            });

            return providers;
        }
    } catch (error) {
        console.error('❌ 无法获取Provider列表:', error.message);
    }

    return [];
}

/**
 * 2. 搜索特定服务
 */
async function searchService(keyword) {
    console.log(`🔍 搜索包含"${keyword}"的服务...\n`);

    try {
        const response = await axios.get(
            `${REGISTRY_API}/api/providers/search/${encodeURIComponent(keyword)}`
        );

        if (response.data.success) {
            const providers = response.data.providers;

            if (providers.length === 0) {
                console.log(`没有找到提供"${keyword}"服务的Provider\n`);
            } else {
                console.log(`找到 ${providers.length} 个相关Provider：\n`);
                providers.forEach(p => {
                    console.log(`• ${p.name} (${p.apiEndpoint})`);
                    const relevantServices = p.services.filter(s =>
                        s.description.includes(keyword) || s.path.includes(keyword)
                    );
                    relevantServices.forEach(s => {
                        console.log(`  - ${s.description} (${s.price} USDC)`);
                    });
                });
                console.log('');
            }

            return providers;
        }
    } catch (error) {
        console.error('❌ 搜索失败:', error.message);
    }

    return [];
}

/**
 * 3. 检查Provider健康状态
 */
async function checkHealth(address) {
    console.log(`🏥 检查Provider健康状态...\n`);

    try {
        const response = await axios.get(
            `${REGISTRY_API}/api/providers/${address}/health`
        );

        if (response.data.success) {
            const status = response.data.status;
            const message = response.data.message;

            const statusMap = {
                'healthy': '✅ 健康',
                'warning': '⚠️  警告',
                'critical': '🚨 危急',
                'offline': '❌ 离线'
            };

            console.log(`Provider: ${address}`);
            console.log(`状态: ${statusMap[status] || status}`);
            console.log(`说明: ${message}\n`);

            return { status, message };
        }
    } catch (error) {
        console.error('❌ 健康检查失败:', error.message);
    }

    return null;
}

/**
 * 4. 比较Provider价格
 */
async function comparePrices() {
    console.log('💰 比较各Provider的服务价格...\n');

    try {
        const response = await axios.get(`${REGISTRY_API}/api/providers`);

        if (response.data.success) {
            const providers = response.data.providers;
            const serviceMap = {};

            // 收集所有服务和价格
            providers.forEach(p => {
                p.services.forEach(s => {
                    if (!serviceMap[s.description]) {
                        serviceMap[s.description] = [];
                    }
                    serviceMap[s.description].push({
                        provider: p.name,
                        price: parseFloat(s.price),
                        tier: p.tier,
                        successRate: p.successRate
                    });
                });
            });

            // 显示价格比较
            Object.entries(serviceMap).forEach(([service, offers]) => {
                console.log(`📊 ${service}:`);

                // 按价格排序
                offers.sort((a, b) => a.price - b.price);

                offers.forEach((offer, index) => {
                    const medal = index === 0 ? '🏆' : '  ';
                    console.log(`${medal} ${offer.provider}: ${offer.price} USDC (${offer.tier}, ${offer.successRate}%)`);
                });
                console.log('');
            });
        }
    } catch (error) {
        console.error('❌ 无法比较价格:', error.message);
    }
}

/**
 * 5. 推荐最佳Provider
 */
async function recommendProvider(serviceName) {
    console.log(`🎯 为"${serviceName}"服务推荐最佳Provider...\n`);

    const providers = await searchService(serviceName);

    if (providers.length === 0) {
        console.log('没有找到提供该服务的Provider\n');
        return null;
    }

    // 评分算法
    const scored = providers.map(p => {
        let score = 0;

        // 成功率权重：40%
        score += (p.successRate / 100) * 40;

        // 等级权重：30%
        const tierScore = {
            'Platinum': 30,
            'Gold': 22.5,
            'Silver': 15,
            'Bronze': 7.5
        };
        score += tierScore[p.tier] || 0;

        // 余额权重：20%（余额越高越稳定）
        const balanceScore = Math.min(parseFloat(p.poolBalance) / 1000, 1) * 20;
        score += balanceScore;

        // 价格权重：10%（价格越低越好）
        const avgPrice = p.services.reduce((sum, s) => sum + parseFloat(s.price), 0) / p.services.length;
        const priceScore = Math.max(0, 10 - avgPrice * 2);
        score += priceScore;

        return { ...p, score };
    });

    // 按分数排序
    scored.sort((a, b) => b.score - a.score);

    const best = scored[0];

    console.log(`🏆 推荐Provider: ${best.name}`);
    console.log(`   综合评分: ${best.score.toFixed(2)}/100`);
    console.log(`   推荐理由:`);
    console.log(`   • ${best.tier}级认证`);
    console.log(`   • ${best.successRate}%成功率`);
    console.log(`   • ${best.poolBalance} USDC保险池`);
    console.log('');

    return best;
}

/**
 * 6. 模拟Client选择Provider的决策过程
 */
async function simulateClientDecision() {
    console.log('🤖 模拟Client智能选择Provider的过程...\n');

    console.log('步骤1: Client需要天气数据服务');
    console.log('步骤2: 查询Registry获取认证Provider列表');

    const weatherProviders = await searchService('天气');

    if (weatherProviders.length === 0) {
        console.log('❌ 没有找到提供天气服务的认证Provider');
        return;
    }

    console.log(`步骤3: 找到${weatherProviders.length}个提供天气服务的Provider`);
    console.log('步骤4: 评估各Provider：');

    for (const p of weatherProviders) {
        console.log(`\n   正在评估: ${p.name}`);
        console.log(`   - 等级: ${p.tier}`);
        console.log(`   - 成功率: ${p.successRate}%`);
        console.log(`   - 保险池: ${p.poolBalance} USDC`);

        // 检查健康状态
        const health = await checkHealth(p.address);
        console.log(`   - 健康状态: ${health.status}`);
    }

    console.log('\n步骤5: 基于评估结果选择最佳Provider');
    const best = await recommendProvider('天气');

    if (best) {
        console.log(`\n✅ 决定：选择 ${best.name}`);
        console.log(`   理由：综合评分最高 (${best.score.toFixed(2)}/100)`);
        console.log(`   API端点：${best.apiEndpoint}`);
        console.log(`   预期服务质量：优秀`);
    }
}

// ============ 主演示程序 ============

async function main() {
    console.log('========================================');
    console.log('X402 Provider Registry 演示');
    console.log('========================================\n');
    console.log('这个演示展示了Client如何通过Registry API');
    console.log('发现和选择认证的Provider\n');

    // 检查Registry是否运行
    try {
        await axios.get(`${REGISTRY_API}/health`);
        console.log('✅ Registry API正在运行\n');
    } catch (error) {
        console.error('❌ Registry API未运行！');
        console.error('请先启动Registry: npm run registry:start\n');
        return;
    }

    console.log('【演示1：显示所有认证Provider】');
    console.log('========================================');
    await showAllProviders();

    console.log('【演示2：搜索特定服务】');
    console.log('========================================');
    await searchService('AI');
    await searchService('汇率');

    console.log('【演示3：比较价格】');
    console.log('========================================');
    await comparePrices();

    console.log('【演示4：智能推荐】');
    console.log('========================================');
    await recommendProvider('天气');
    await recommendProvider('AI');

    console.log('【演示5：模拟Client决策】');
    console.log('========================================');
    await simulateClientDecision();

    console.log('\n========================================');
    console.log('演示完成！');
    console.log('========================================\n');

    console.log('总结：');
    console.log('1. Client可以通过Registry查询所有认证的Provider');
    console.log('2. 每个Provider都有保险保护，确保服务安全');
    console.log('3. Client可以比较价格、成功率、等级等指标');
    console.log('4. Registry提供健康检查，避免选择故障Provider');
    console.log('5. 所有信息透明公开，Client可以做出明智选择');
    console.log('\n这就解决了"如何确认哪个Provider是我们认证的"问题！');
}

// 运行演示
if (require.main === module) {
    main().catch(console.error);
}