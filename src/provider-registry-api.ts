/**
 * Provider Registry API
 * REST API for querying registered insurance providers
 */

import express from 'express';
import { ethers } from 'ethers';
import dotenv from 'dotenv';

dotenv.config();

const app = express();
app.use(express.json());

// Configuration
const PORT = process.env.REGISTRY_PORT || 3005;
const RPC_URL = process.env.BASE_SEPOLIA_RPC_URL || 'https://sepolia.base.org';
const INSURANCE_ADDRESS = process.env.INSURANCE_V3_ADDRESS;

// Contract ABI (minimal)
const INSURANCE_ABI = [
    "function getAllProviders() external view returns (address[])",
    "function getProviderInfo(address) external view returns (bool isActive, uint256 poolBalance, uint256 totalClaims, uint256 successfulServices, uint8 tier, uint256 claimedAmount)",
    "function getProviderTier(address) external view returns (uint8)"
];

// Initialize provider and contract
let provider: ethers.JsonRpcProvider;
let insurance: ethers.Contract | null = null;

if (INSURANCE_ADDRESS && INSURANCE_ADDRESS !== '') {
    provider = new ethers.JsonRpcProvider(RPC_URL);
    insurance = new ethers.Contract(INSURANCE_ADDRESS, INSURANCE_ABI, provider);
    console.log(`✅ Connected to Insurance contract: ${INSURANCE_ADDRESS}`);
} else {
    console.log('⚠️  Running in demo mode (no contract connected)');
}

// GET /api/providers - Get all providers
app.get('/api/providers', async (req, res) => {
    try {
        if (!insurance) {
            // Demo data
            return res.json({
                success: true,
                count: 1,
                providers: [{
                    address: '0x34D2185E7D4AfF17747Ee903a93Ad23A32B0626C',
                    isActive: true,
                    poolBalance: '5000000',
                    tier: 0,
                    tierName: 'Bronze',
                    metadata: {
                        name: 'Test Provider',
                        endpoint: 'http://localhost:3001',
                        description: 'Test provider on Base Sepolia'
                    }
                }]
            });
        }

        const providerAddresses = await insurance.getAllProviders();
        const providers = [];

        for (const address of providerAddresses) {
            const info = await insurance.getProviderInfo(address);
            const [isActive, poolBalance, totalClaims, successfulServices, tier, claimedAmount] = info;

            providers.push({
                address,
                isActive,
                poolBalance: poolBalance.toString(),
                totalClaims: totalClaims.toString(),
                successfulServices: successfulServices.toString(),
                tier: Number(tier),
                tierName: ['Bronze', 'Silver', 'Gold', 'Platinum'][Number(tier)],
                claimedAmount: claimedAmount.toString()
            });
        }

        res.json({
            success: true,
            count: providers.length,
            providers
        });
    } catch (error: any) {
        console.error('Error fetching providers:', error);
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

// GET /api/providers/:address - Get specific provider
app.get('/api/providers/:address', async (req, res) => {
    try {
        const { address } = req.params;

        if (!ethers.isAddress(address)) {
            return res.status(400).json({
                success: false,
                error: 'Invalid address format'
            });
        }

        if (!insurance) {
            // Demo response
            if (address.toLowerCase() === '0x34d2185e7d4aff17747ee903a93ad23a32b0626c') {
                return res.json({
                    success: true,
                    provider: {
                        address,
                        isActive: true,
                        poolBalance: '5000000',
                        tier: 0,
                        tierName: 'Bronze'
                    }
                });
            }
            return res.status(404).json({
                success: false,
                error: 'Provider not found'
            });
        }

        const info = await insurance.getProviderInfo(address);
        const [isActive, poolBalance, totalClaims, successfulServices, tier, claimedAmount] = info;

        if (!isActive && poolBalance == 0n) {
            return res.status(404).json({
                success: false,
                error: 'Provider not found'
            });
        }

        res.json({
            success: true,
            provider: {
                address,
                isActive,
                poolBalance: poolBalance.toString(),
                totalClaims: totalClaims.toString(),
                successfulServices: successfulServices.toString(),
                tier: Number(tier),
                tierName: ['Bronze', 'Silver', 'Gold', 'Platinum'][Number(tier)],
                claimedAmount: claimedAmount.toString()
            }
        });
    } catch (error: any) {
        console.error('Error fetching provider:', error);
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

// Health check
app.get('/health', (req, res) => {
    res.json({
        status: 'healthy',
        contractConnected: !!insurance,
        contractAddress: INSURANCE_ADDRESS || 'none'
    });
});

// Start server
app.listen(PORT, () => {
    console.log('========================================');
    console.log('Provider Registry API');
    console.log('========================================');
    console.log(`Service running on port ${PORT}\n`);
    console.log('Endpoints:');
    console.log(`  GET  http://localhost:${PORT}/api/providers`);
    console.log(`  GET  http://localhost:${PORT}/api/providers/:address`);
    console.log(`  GET  http://localhost:${PORT}/health`);
    console.log('');
    console.log(`Try: curl http://localhost:${PORT}/api/providers`);
    console.log('========================================');
});