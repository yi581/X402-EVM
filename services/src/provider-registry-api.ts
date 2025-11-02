/**
 * Provider Registry API
 *
 * 提供Provider列表查询服务，让Client可以：
 * 1. 查询所有认证的Provider
 * 2. 查询特定Provider的信息
 * 3. 获取Provider的API端点
 */

import express from 'express';
import { ethers } from 'ethers';
import cors from 'cors';
import dotenv from 'dotenv';
import X402InsuranceV3ABI from '../abi/X402InsuranceV3.json';

dotenv.config();

// ============ Types ============

interface ProviderRegistration {
    address: string;
    apiEndpoint: string;
    name: string;
    description: string;
    tier: 'Bronze' | 'Silver' | 'Gold' | 'Platinum';
    poolBalance: string;
    successRate: number;
    isActive: boolean;
    registeredAt: Date;
    services: ServiceInfo[];
}

interface ServiceInfo {
    path: string;
    method: string;
    price: string;
    description: string;
}

// ============ Provider Registry Class ============

export class ProviderRegistry {
    private provider: ethers.JsonRpcProvider;
    private insuranceContract: ethers.Contract;

    // 本地存储Provider的API信息（实际项目中应该用数据库）
    private providerDatabase: Map<string, {
        apiEndpoint: string;
        name: string;
        description: string;
        services: ServiceInfo[];
    }> = new Map();

    constructor() {
        // 初始化区块链连接
        const rpcUrl = process.env.BASE_SEPOLIA_RPC_URL || 'https://sepolia.base.org';
        this.provider = new ethers.JsonRpcProvider(rpcUrl);

        // 初始化保险合约（如果配置了）
        if (process.env.INSURANCE_V3_ADDRESS) {
            this.insuranceContract = new ethers.Contract(
                process.env.INSURANCE_V3_ADDRESS,
                X402InsuranceV3ABI.abi,
                this.provider
            );
            console.log('✅ Connected to Insurance Contract:', process.env.INSURANCE_V3_ADDRESS);
        } else {
            console.log('⚠️  Running in demo mode (no contract connected)');
            // 创建一个mock contract用于演示
            this.insuranceContract = {
                filters: {
                    ProviderRegistered: () => ({})
                },
                queryFilter: async () => [],
                getProviderInfo: async () => ({
                    isActive: false,
                    tier: 0,
                    poolBalance: 0
                }),
                getProviderStats: async () => ({
                    successCount: 0,
                    failureCount: 0,
                    registeredAt: 0
                })
            } as any;
        }

        // 初始化一些测试Provider数据
        this.initTestProviders();
    }

    /**
     * 初始化测试Provider数据
     */
    private initTestProviders() {
        // 测试Provider 1 - 天气API
        this.providerDatabase.set('0x1111111111111111111111111111111111111111', {
            apiEndpoint: 'http://localhost:3001',
            name: 'Weather Data Provider',
            description: '提供全球天气数据查询服务',
            services: [
                {
                    path: '/api/weather/current',
                    method: 'GET',
                    price: '0.1',
                    description: '获取当前天气'
                },
                {
                    path: '/api/weather/forecast',
                    method: 'GET',
                    price: '0.5',
                    description: '获取7天天气预报'
                }
            ]
        });

        // 测试Provider 2 - 汇率API
        this.providerDatabase.set('0x2222222222222222222222222222222222222222', {
            apiEndpoint: 'http://localhost:3003',
            name: 'Exchange Rate Provider',
            description: '提供实时汇率数据',
            services: [
                {
                    path: '/api/rate/usd',
                    method: 'GET',
                    price: '0.05',
                    description: 'USD汇率查询'
                }
            ]
        });

        // 测试Provider 3 - AI服务
        this.providerDatabase.set('0x3333333333333333333333333333333333333333', {
            apiEndpoint: 'http://localhost:3004',
            name: 'AI Service Provider',
            description: 'AI文本和图像处理服务',
            services: [
                {
                    path: '/api/ai/text',
                    method: 'POST',
                    price: '1.0',
                    description: '文本生成'
                },
                {
                    path: '/api/ai/image',
                    method: 'POST',
                    price: '5.0',
                    description: '图像生成'
                }
            ]
        });
    }

    /**
     * 注册Provider的API信息
     */
    async registerProviderAPI(
        address: string,
        apiEndpoint: string,
        name: string,
        description: string,
        services: ServiceInfo[]
    ): Promise<boolean> {
        try {
            // 验证Provider是否在链上注册
            const info = await this.insuranceContract.getProviderInfo(address);
            if (!info.isActive) {
                throw new Error('Provider not registered on chain');
            }

            // 保存API信息
            this.providerDatabase.set(address.toLowerCase(), {
                apiEndpoint,
                name,
                description,
                services
            });

            console.log(`✅ Provider API registered: ${name} at ${apiEndpoint}`);
            return true;

        } catch (error) {
            console.error('Failed to register provider API:', error);
            return false;
        }
    }

    /**
     * 获取所有认证的Provider列表
     */
    async getAllProviders(): Promise<ProviderRegistration[]> {
        const providers: ProviderRegistration[] = [];

        try {
            // 从事件中获取所有注册的Provider
            const filter = this.insuranceContract.filters.ProviderRegistered();
            const events = await this.insuranceContract.queryFilter(filter, -10000);

            const uniqueProviders = new Set<string>();
            events.forEach(event => {
                if ('args' in event && event.args) {
                    uniqueProviders.add(event.args[0].toLowerCase());
                }
            });

            // 查询每个Provider的信息
            for (const providerAddress of uniqueProviders) {
                const providerInfo = await this.getProviderInfo(providerAddress);
                if (providerInfo && providerInfo.isActive) {
                    providers.push(providerInfo);
                }
            }

            // 添加测试数据（如果数据库为空）
            if (providers.length === 0) {
                console.log('No providers found, adding test data...');

                // 添加测试Provider
                for (const [address, data] of this.providerDatabase.entries()) {
                    providers.push({
                        address,
                        apiEndpoint: data.apiEndpoint,
                        name: data.name,
                        description: data.description,
                        tier: 'Silver',
                        poolBalance: '500',
                        successRate: 98.5,
                        isActive: true,
                        registeredAt: new Date(),
                        services: data.services
                    });
                }
            }

        } catch (error) {
            console.error('Failed to get providers:', error);

            // 返回测试数据
            for (const [address, data] of this.providerDatabase.entries()) {
                providers.push({
                    address,
                    apiEndpoint: data.apiEndpoint,
                    name: data.name,
                    description: data.description,
                    tier: 'Silver',
                    poolBalance: '500',
                    successRate: 98.5,
                    isActive: true,
                    registeredAt: new Date(),
                    services: data.services
                });
            }
        }

        return providers;
    }

    /**
     * 获取特定Provider的信息
     */
    async getProviderInfo(address: string): Promise<ProviderRegistration | null> {
        try {
            const normalizedAddress = address.toLowerCase();

            // 获取链上信息
            const info = await this.insuranceContract.getProviderInfo(address);
            const stats = await this.insuranceContract.getProviderStats(address);

            if (!info.isActive) {
                return null;
            }

            // 获取API信息
            const apiInfo = this.providerDatabase.get(normalizedAddress) || {
                apiEndpoint: `http://localhost:${3000 + Math.floor(Math.random() * 100)}`,
                name: `Provider ${address.slice(0, 8)}`,
                description: 'X402 Payment Service Provider',
                services: []
            };

            // 计算成功率
            const totalTx = Number(stats.successCount) + Number(stats.failureCount);
            const successRate = totalTx > 0 ?
                (Number(stats.successCount) / totalTx) * 100 : 100;

            // 确定等级
            const tierNames = ['None', 'Bronze', 'Silver', 'Gold', 'Platinum'];
            const tier = tierNames[Number(info.tier)] as ProviderRegistration['tier'];

            return {
                address,
                apiEndpoint: apiInfo.apiEndpoint,
                name: apiInfo.name,
                description: apiInfo.description,
                tier,
                poolBalance: ethers.formatUnits(info.poolBalance, 6),
                successRate: Math.round(successRate * 100) / 100,
                isActive: true,
                registeredAt: new Date(Number(stats.registeredAt) * 1000),
                services: apiInfo.services
            };

        } catch (error) {
            console.error('Failed to get provider info:', error);

            // 返回测试数据
            const apiInfo = this.providerDatabase.get(address.toLowerCase());
            if (apiInfo) {
                return {
                    address,
                    apiEndpoint: apiInfo.apiEndpoint,
                    name: apiInfo.name,
                    description: apiInfo.description,
                    tier: 'Silver',
                    poolBalance: '500',
                    successRate: 98.5,
                    isActive: true,
                    registeredAt: new Date(),
                    services: apiInfo.services
                };
            }

            return null;
        }
    }

    /**
     * 搜索Provider
     */
    async searchProviders(query: string): Promise<ProviderRegistration[]> {
        const allProviders = await this.getAllProviders();
        const queryLower = query.toLowerCase();

        return allProviders.filter(p =>
            p.name.toLowerCase().includes(queryLower) ||
            p.description.toLowerCase().includes(queryLower) ||
            p.address.toLowerCase().includes(queryLower) ||
            p.services.some(s => s.description.toLowerCase().includes(queryLower))
        );
    }

    /**
     * 获取Provider的健康状态
     */
    async getProviderHealth(address: string): Promise<{
        status: 'healthy' | 'warning' | 'critical' | 'offline';
        message: string;
    }> {
        try {
            const info = await this.getProviderInfo(address);

            if (!info) {
                return { status: 'offline', message: 'Provider not found' };
            }

            const balance = parseFloat(info.poolBalance);

            if (balance < 10) {
                return { status: 'critical', message: 'Balance too low' };
            } else if (balance < 50) {
                return { status: 'warning', message: 'Balance low' };
            } else {
                return { status: 'healthy', message: 'Operating normally' };
            }

        } catch (error) {
            return { status: 'offline', message: 'Cannot connect to provider' };
        }
    }
}

// ============ API Server ============

export function createRegistryAPI() {
    const app = express();
    app.use(express.json());
    app.use(cors()); // 允许跨域访问

    const registry = new ProviderRegistry();

    // 获取所有Provider
    app.get('/api/providers', async (req, res) => {
        try {
            const providers = await registry.getAllProviders();
            res.json({
                success: true,
                count: providers.length,
                providers
            });
        } catch (error: any) {
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    // 获取特定Provider
    app.get('/api/providers/:address', async (req, res) => {
        try {
            const provider = await registry.getProviderInfo(req.params.address);
            if (provider) {
                res.json({
                    success: true,
                    provider
                });
            } else {
                res.status(404).json({
                    success: false,
                    error: 'Provider not found'
                });
            }
        } catch (error: any) {
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    // 搜索Provider
    app.get('/api/providers/search/:query', async (req, res) => {
        try {
            const providers = await registry.searchProviders(req.params.query);
            res.json({
                success: true,
                count: providers.length,
                providers
            });
        } catch (error: any) {
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    // 获取Provider健康状态
    app.get('/api/providers/:address/health', async (req, res) => {
        try {
            const health = await registry.getProviderHealth(req.params.address);
            res.json({
                success: true,
                ...health
            });
        } catch (error: any) {
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    // 注册Provider API信息
    app.post('/api/providers/register', async (req, res) => {
        try {
            const { address, apiEndpoint, name, description, services } = req.body;

            // 验证API密钥（简单验证）
            const apiKey = req.headers['x-api-key'];
            if (apiKey !== process.env.REGISTRY_API_KEY) {
                return res.status(401).json({
                    success: false,
                    error: 'Unauthorized'
                });
            }

            const success = await registry.registerProviderAPI(
                address,
                apiEndpoint,
                name,
                description,
                services
            );

            res.json({ success });

        } catch (error: any) {
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    // 健康检查
    app.get('/health', (req, res) => {
        res.json({
            status: 'ok',
            service: 'provider-registry',
            timestamp: new Date()
        });
    });

    return app;
}

// ============ Main Entry Point ============

// Check if this file is being run directly
const isMainModule = import.meta.url === `file://${process.argv[1]}`;

if (isMainModule) {
    const app = createRegistryAPI();
    const PORT = process.env.REGISTRY_PORT || 3005;

    app.listen(PORT, () => {
        console.log('========================================');
        console.log('Provider Registry API');
        console.log('========================================');
        console.log(`Service running on port ${PORT}`);
        console.log('');
        console.log('Endpoints:');
        console.log(`  GET  http://localhost:${PORT}/api/providers`);
        console.log(`  GET  http://localhost:${PORT}/api/providers/:address`);
        console.log(`  GET  http://localhost:${PORT}/api/providers/search/:query`);
        console.log(`  GET  http://localhost:${PORT}/api/providers/:address/health`);
        console.log(`  POST http://localhost:${PORT}/api/providers/register`);
        console.log('');
        console.log('Try: curl http://localhost:' + PORT + '/api/providers');
        console.log('========================================');
    });
}