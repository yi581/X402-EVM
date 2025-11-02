/**
 * Provider Service for X402 Insurance V3
 *
 * This service helps providers:
 * - Register and manage their insurance pool
 * - Monitor their tier status
 * - Handle service delivery confirmations
 * - Track statistics and performance
 */

import { ethers } from 'ethers';
import express from 'express';
import dotenv from 'dotenv';
import { CoinbaseFacilitatorV3, createX402Middleware } from './coinbase-facilitator-v3';

dotenv.config();

// Import V3 Insurance ABI
import X402InsuranceV3ABI from '../abi/X402InsuranceV3.json';

// ============ Provider Manager Class ============

export class ProviderManagerV3 {
  private provider: ethers.JsonRpcProvider;
  private signer: ethers.Wallet;
  private insuranceContract: ethers.Contract;
  private facilitator: CoinbaseFacilitatorV3;
  private providerAddress: string;

  constructor() {
    // Initialize blockchain connection
    const rpcUrl = process.env.BASE_SEPOLIA_RPC_URL || 'https://sepolia.base.org';
    this.provider = new ethers.JsonRpcProvider(rpcUrl);

    // Initialize signer
    if (!process.env.PROVIDER_PRIVATE_KEY) {
      throw new Error('PROVIDER_PRIVATE_KEY not set');
    }
    this.signer = new ethers.Wallet(process.env.PROVIDER_PRIVATE_KEY, this.provider);
    this.providerAddress = this.signer.address;

    // Initialize insurance contract
    if (!process.env.INSURANCE_V3_ADDRESS) {
      throw new Error('INSURANCE_V3_ADDRESS not set');
    }
    this.insuranceContract = new ethers.Contract(
      process.env.INSURANCE_V3_ADDRESS,
      X402InsuranceV3ABI,
      this.signer
    );

    // Initialize facilitator
    this.facilitator = new CoinbaseFacilitatorV3({
      network: 'base-sepolia',
      insuranceAddress: process.env.INSURANCE_V3_ADDRESS
    });

    console.log(`Provider Manager initialized for address: ${this.providerAddress}`);
  }

  /**
   * Register as a provider and make initial deposit
   */
  async registerAndDeposit(amountUSDC: string): Promise<{
    success: boolean;
    txHash?: string;
    tier?: string;
    error?: string;
  }> {
    try {
      console.log(`Registering provider with ${amountUSDC} USDC deposit...`);

      // Convert to USDC units (6 decimals)
      const amount = ethers.parseUnits(amountUSDC, 6);

      // Approve USDC spending
      const usdcAddress = process.env.USDC_ADDRESS;
      if (!usdcAddress) {
        throw new Error('USDC_ADDRESS not configured');
      }

      const usdcContract = new ethers.Contract(
        usdcAddress,
        ['function approve(address spender, uint256 amount) returns (bool)'],
        this.signer
      );

      console.log('Approving USDC...');
      const approveTx = await usdcContract.approve(this.insuranceContract.target, amount);
      await approveTx.wait();

      // Register and deposit
      console.log('Registering and depositing...');
      const tx = await this.insuranceContract.registerAndDeposit(amount);
      const receipt = await tx.wait();

      // Get tier information
      const info = await this.insuranceContract.getProviderInfo(this.providerAddress);
      const tierNames = ['None', 'Bronze', 'Silver', 'Gold', 'Platinum'];
      const tier = tierNames[info.tier];

      console.log(`Registration successful! Tier: ${tier}`);

      return {
        success: true,
        txHash: receipt.hash,
        tier
      };
    } catch (error: any) {
      console.error('Registration failed:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }

  /**
   * Add more funds to insurance pool
   */
  async deposit(amountUSDC: string): Promise<{
    success: boolean;
    txHash?: string;
    newBalance?: string;
    newTier?: string;
    error?: string;
  }> {
    try {
      const amount = ethers.parseUnits(amountUSDC, 6);

      // Approve USDC
      const usdcContract = new ethers.Contract(
        process.env.USDC_ADDRESS!,
        ['function approve(address spender, uint256 amount) returns (bool)'],
        this.signer
      );

      const approveTx = await usdcContract.approve(this.insuranceContract.target, amount);
      await approveTx.wait();

      // Deposit
      const tx = await this.insuranceContract.deposit(amount);
      const receipt = await tx.wait();

      // Get updated info
      const info = await this.insuranceContract.getProviderInfo(this.providerAddress);
      const tierNames = ['None', 'Bronze', 'Silver', 'Gold', 'Platinum'];

      return {
        success: true,
        txHash: receipt.hash,
        newBalance: ethers.formatUnits(info.poolBalance, 6),
        newTier: tierNames[info.tier]
      };
    } catch (error: any) {
      return {
        success: false,
        error: error.message
      };
    }
  }

  /**
   * Withdraw funds from insurance pool
   */
  async withdraw(amountUSDC: string): Promise<{
    success: boolean;
    txHash?: string;
    remainingBalance?: string;
    error?: string;
  }> {
    try {
      const amount = ethers.parseUnits(amountUSDC, 6);

      const tx = await this.insuranceContract.withdraw(amount);
      const receipt = await tx.wait();

      const info = await this.insuranceContract.getProviderInfo(this.providerAddress);

      return {
        success: true,
        txHash: receipt.hash,
        remainingBalance: ethers.formatUnits(info.poolBalance, 6)
      };
    } catch (error: any) {
      return {
        success: false,
        error: error.message
      };
    }
  }

  /**
   * Confirm service delivery
   */
  async confirmDelivery(commitment: string): Promise<{
    success: boolean;
    txHash?: string;
    error?: string;
  }> {
    try {
      const tx = await this.insuranceContract.confirmDelivery(commitment);
      const receipt = await tx.wait();

      console.log(`Service delivery confirmed for commitment: ${commitment}`);

      return {
        success: true,
        txHash: receipt.hash
      };
    } catch (error: any) {
      return {
        success: false,
        error: error.message
      };
    }
  }

  /**
   * Get current status
   */
  async getStatus(): Promise<{
    address: string;
    isActive: boolean;
    tier: string;
    poolBalance: string;
    availableBalance: string;
    lockedBalance: string;
    successCount: number;
    failureCount: number;
    successRate: number;
    totalDeposited: string;
    totalWithdrawn: string;
    totalPenalties: string;
  }> {
    const info = await this.insuranceContract.getProviderInfo(this.providerAddress);
    const stats = await this.insuranceContract.getProviderStats(this.providerAddress);

    const tierNames = ['None', 'Bronze', 'Silver', 'Gold', 'Platinum'];
    const totalTx = Number(stats.successCount) + Number(stats.failureCount);
    const successRate = totalTx > 0 ? (Number(stats.successCount) * 100) / totalTx : 0;

    return {
      address: this.providerAddress,
      isActive: info.isActive,
      tier: tierNames[info.tier],
      poolBalance: ethers.formatUnits(info.poolBalance, 6),
      availableBalance: ethers.formatUnits(info.availableBalance, 6),
      lockedBalance: ethers.formatUnits(info.lockedBalance, 6),
      successCount: Number(stats.successCount),
      failureCount: Number(stats.failureCount),
      successRate: Math.round(successRate * 100) / 100,
      totalDeposited: ethers.formatUnits(stats.totalDeposited, 6),
      totalWithdrawn: ethers.formatUnits(stats.totalWithdrawn, 6),
      totalPenalties: ethers.formatUnits(stats.totalPenalties, 6)
    };
  }

  /**
   * Monitor for events
   */
  startEventMonitoring() {
    // Listen for insurance locked events
    this.insuranceContract.on('InsuranceLocked',
      async (commitment, provider, client, amount, unlockAt) => {
        if (provider === this.providerAddress) {
          console.log('\n🔒 New Insurance Locked:');
          console.log(`   Commitment: ${commitment}`);
          console.log(`   Client: ${client}`);
          console.log(`   Amount: ${ethers.formatUnits(amount, 6)} USDC`);
          console.log(`   Unlock at: ${new Date(Number(unlockAt) * 1000).toLocaleString()}`);

          // Store commitment for later confirmation
          this.storePendingCommitment(commitment, client, amount);
        }
      }
    );

    // Listen for tier changes
    this.insuranceContract.on('TierUpgraded',
      async (provider, oldTier, newTier) => {
        if (provider === this.providerAddress) {
          const tierNames = ['None', 'Bronze', 'Silver', 'Gold', 'Platinum'];
          const direction = newTier > oldTier ? '⬆️' : '⬇️';
          console.log(`\n${direction} Tier Changed: ${tierNames[oldTier]} → ${tierNames[newTier]}`);
        }
      }
    );

    // Listen for warnings
    this.insuranceContract.on('ProviderWarning',
      async (provider, balance, level) => {
        if (provider === this.providerAddress) {
          const emoji = level === 'CRITICAL' ? '🚨' : '⚠️';
          console.log(`\n${emoji} Warning: Balance ${ethers.formatUnits(balance, 6)} USDC (${level})`);

          if (level === 'CRITICAL') {
            // Auto-deposit if configured
            if (process.env.AUTO_TOPUP_AMOUNT) {
              console.log('Attempting auto top-up...');
              await this.deposit(process.env.AUTO_TOPUP_AMOUNT);
            }
          }
        }
      }
    );

    console.log('Event monitoring started');
  }

  /**
   * Store pending commitment for tracking
   */
  private pendingCommitments = new Map<string, any>();

  private storePendingCommitment(commitment: string, client: string, amount: bigint) {
    this.pendingCommitments.set(commitment, {
      client,
      amount: ethers.formatUnits(amount, 6),
      timestamp: Date.now()
    });
  }

  /**
   * Get pending commitments
   */
  getPendingCommitments(): Array<{
    commitment: string;
    client: string;
    amount: string;
    timestamp: number;
  }> {
    return Array.from(this.pendingCommitments.entries()).map(([commitment, data]) => ({
      commitment,
      ...data
    }));
  }
}

// ============ API Server ============

export function createProviderAPI(manager: ProviderManagerV3) {
  const app = express();
  app.use(express.json());

  // Apply X402 payment middleware to paid endpoints
  const facilitator = new CoinbaseFacilitatorV3({
    network: 'base-sepolia',
    insuranceAddress: process.env.INSURANCE_V3_ADDRESS
  });

  const paymentMiddleware = createX402Middleware(facilitator);

  // Public endpoints
  app.get('/status', async (req, res) => {
    try {
      const status = await manager.getStatus();
      res.json(status);
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  });

  app.get('/pending', (req, res) => {
    res.json({
      commitments: manager.getPendingCommitments()
    });
  });

  // Management endpoints (require API key)
  app.use('/manage', (req, res, next) => {
    const apiKey = req.headers['x-api-key'];
    if (apiKey !== process.env.PROVIDER_API_KEY) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    next();
  });

  app.post('/manage/register', async (req, res) => {
    const { amount } = req.body;
    if (!amount) {
      return res.status(400).json({ error: 'Amount required' });
    }

    const result = await manager.registerAndDeposit(amount);
    res.json(result);
  });

  app.post('/manage/deposit', async (req, res) => {
    const { amount } = req.body;
    const result = await manager.deposit(amount);
    res.json(result);
  });

  app.post('/manage/withdraw', async (req, res) => {
    const { amount } = req.body;
    const result = await manager.withdraw(amount);
    res.json(result);
  });

  app.post('/manage/confirm', async (req, res) => {
    const { commitment } = req.body;
    const result = await manager.confirmDelivery(commitment);
    res.json(result);
  });

  // Paid API endpoints (require X402 payment)
  app.use('/api', paymentMiddleware);

  app.get('/api/data', (req: any, res) => {
    // This endpoint requires payment
    res.json({
      message: 'Premium data access granted',
      payment: req.payment,
      data: {
        timestamp: Date.now(),
        content: 'Your valuable data here'
      }
    });
  });

  app.post('/api/compute', (req: any, res) => {
    // This endpoint requires payment for computation
    const { input } = req.body;
    res.json({
      message: 'Computation completed',
      payment: req.payment,
      result: {
        input,
        output: `Processed: ${input}`,
        timestamp: Date.now()
      }
    });
  });

  return app;
}

// ============ Main Entry Point ============

if (require.main === module) {
  async function main() {
    try {
      // Create provider manager
      const manager = new ProviderManagerV3();

      // Check current status
      const status = await manager.getStatus();
      console.log('\n📊 Current Provider Status:');
      console.log(`   Address: ${status.address}`);
      console.log(`   Active: ${status.isActive}`);
      console.log(`   Tier: ${status.tier}`);
      console.log(`   Pool Balance: ${status.poolBalance} USDC`);
      console.log(`   Available: ${status.availableBalance} USDC`);
      console.log(`   Success Rate: ${status.successRate}%`);

      // Register if not active
      if (!status.isActive) {
        const initialDeposit = process.env.INITIAL_DEPOSIT || '100';
        console.log(`\n📝 Provider not active. Registering with ${initialDeposit} USDC...`);

        const registration = await manager.registerAndDeposit(initialDeposit);
        if (registration.success) {
          console.log(`✅ Registration successful! Tier: ${registration.tier}`);
        } else {
          console.error(`❌ Registration failed: ${registration.error}`);
        }
      }

      // Start event monitoring
      manager.startEventMonitoring();

      // Create and start API server
      const app = createProviderAPI(manager);
      const PORT = process.env.PROVIDER_PORT || 3001;

      app.listen(PORT, () => {
        console.log(`\n🚀 Provider Service V3 running on port ${PORT}`);
        console.log(`   Status: http://localhost:${PORT}/status`);
        console.log(`   Pending: http://localhost:${PORT}/pending`);
        console.log(`   Paid API: http://localhost:${PORT}/api/*`);
        console.log('\n   Management endpoints require X-API-Key header');
      });

    } catch (error) {
      console.error('Failed to start provider service:', error);
      process.exit(1);
    }
  }

  main();
}