/**
 * X402 Insurance 兼容层
 * 自动选择合适的保险合约版本
 */

import { ethers } from 'ethers';

export interface InsuranceConfig {
    version?: 'v3' | 'v5' | 'v6' | 'v7' | 'auto';
    address?: string;
    provider: ethers.Provider;
}

export class X402Insurance {
    private contract: ethers.Contract;
    private version: string;

    constructor(config: InsuranceConfig) {
        // 优先使用 V7
        const address = config.address ||
                       process.env.INSURANCE_V7_ADDRESS ||
                       process.env.INSURANCE_V6_ADDRESS ||
                       process.env.INSURANCE_V5_ADDRESS ||
                       process.env.INSURANCE_V3_ADDRESS;

        if (!address) {
            throw new Error('No insurance contract address found');
        }

        // 通用 ABI（所有版本共享的函数）
        const commonABI = [
            "function registerOrReactivate(uint256 amount)",
            "function depositAdditional(uint256 amount)",
            "function withdraw(uint256 amount)",
            "function withdrawAllAndDeactivate()",
            "function initiateClaim(bytes32 commitment, address provider, uint256 amount, uint8 reason)",
            "function disputeClaim(bytes32 commitment, string memory evidence)",
            "function executeClaim(bytes32 commitment)",
            "function getProviderInfo(address provider) view returns (bool, uint256, uint256, uint256, uint256, uint8, uint256)",
            "function getClaimInfo(bytes32 commitment) view returns (address, address, uint256, uint256, uint256, uint8, uint8)"
        ];

        // V6/V7 新增函数
        const v6PlusABI = [
            ...commonABI,
            "function canAcceptService(address provider, uint256 amount) view returns (bool, string)",
            "function getProviderCapacity(address provider) view returns (uint256, uint256)",
            "function getProviderRiskScore(address provider) view returns (uint256)"
        ];

        // V7 独有函数
        const v7ABI = [
            ...v6PlusABI,
            "function getTotalAvailableFunds(address provider) view returns (uint256)"
        ];

        // 自动检测版本
        if (config.version === 'auto' || !config.version) {
            this.version = this.detectVersion(address, config.provider);
        } else {
            this.version = config.version;
        }

        // 根据版本选择 ABI
        let abi = commonABI;
        if (this.version === 'v7') {
            abi = v7ABI;
        } else if (this.version === 'v6') {
            abi = v6PlusABI;
        }

        this.contract = new ethers.Contract(address, abi, config.provider);
    }

    private async detectVersion(address: string, provider: ethers.Provider): Promise<string> {
        const testContract = new ethers.Contract(address, [
            "function getTotalAvailableFunds(address) view returns (uint256)",
            "function canAcceptService(address, uint256) view returns (bool, string)"
        ], provider);

        try {
            // 尝试调用 V7 独有函数
            await testContract.getTotalAvailableFunds(ethers.ZeroAddress);
            return 'v7';
        } catch {
            try {
                // 尝试调用 V6 函数
                await testContract.canAcceptService(ethers.ZeroAddress, 0);
                return 'v6';
            } catch {
                // 默认为 V5 或更早
                return 'v5';
            }
        }
    }

    // 通用接口方法
    async initiateClaim(
        commitment: string,
        provider: string,
        amount: bigint,
        reason: number
    ): Promise<ethers.ContractTransaction> {
        try {
            return await this.contract.initiateClaim(commitment, provider, amount, reason);
        } catch (error: any) {
            // V7 特有错误处理
            if (error.reason === "Insufficient funds across all pools") {
                throw new Error(`Provider 资金不足: 需要 ${ethers.formatUnits(amount, 6)} USDC，但总可用资金不足`);
            }
            throw error;
        }
    }

    async canAcceptService(provider: string, amount: bigint): Promise<{ canAccept: boolean; reason: string }> {
        if (this.version >= 'v6') {
            return await this.contract.canAcceptService(provider, amount);
        } else {
            // V5 及以下版本的兼容实现
            const info = await this.contract.getProviderInfo(provider);
            const available = info[1] - info[2]; // poolBalance - totalLocked
            return {
                canAccept: available >= amount,
                reason: available >= amount ? "OK" : "Insufficient balance"
            };
        }
    }

    async getTotalAvailableFunds(provider: string): Promise<bigint> {
        if (this.version === 'v7') {
            return await this.contract.getTotalAvailableFunds(provider);
        } else {
            // 兼容实现：只返回 provider 的可用余额
            const info = await this.contract.getProviderInfo(provider);
            return info[1] > info[2] ? info[1] - info[2] : 0n;
        }
    }

    getVersion(): string {
        return this.version;
    }

    getContract(): ethers.Contract {
        return this.contract;
    }
}

// ClaimReason 枚举（所有版本通用）
export enum ClaimReason {
    NOT_DELIVERED = 0,
    SERVICE_TIMEOUT = 1,
    PARTIAL_DELIVERY = 2
}

// 导出默认实例
export default X402Insurance;
