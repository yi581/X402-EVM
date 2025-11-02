/**
 * Claim Processing and Monitoring Service
 *
 * This service handles:
 * - Zero-gas claim processing (meta-transactions)
 * - Automatic unlocking of expired locks
 * - System health monitoring
 * - Alert notifications
 */

import { ethers } from 'ethers';
import express from 'express';
import dotenv from 'dotenv';
import X402InsuranceV3ABI from '../abi/X402InsuranceV3.json';

dotenv.config();

// ============ Types ============

interface ClaimRequest {
  commitment: string;
  client: string;
  amount: string;
  deadline: number;
  v: number;
  r: string;
  s: string;
}

interface MonitoringStats {
  totalPoolBalance: string;
  totalLockedBalance: string;
  activeProviders: number;
  totalTransactions: number;
  totalFailures: number;
  failureRate: number;
  platformRevenue: string;
  pendingUnlocks: number;
  criticalProviders: string[];
  warningProviders: string[];
}

// ============ Claim Service Class ============

export class ClaimAndMonitorService {
  private provider: ethers.JsonRpcProvider;
  private signer: ethers.Wallet;
  private insuranceContract: ethers.Contract;
  private isMonitoring: boolean = false;
  private monitoringInterval?: NodeJS.Timeout;
  private unlockInterval?: NodeJS.Timeout;

  constructor() {
    // Initialize provider
    const rpcUrl = process.env.BASE_SEPOLIA_RPC_URL || 'https://sepolia.base.org';
    this.provider = new ethers.JsonRpcProvider(rpcUrl);

    // Initialize signer (relayer wallet)
    if (!process.env.RELAYER_PRIVATE_KEY) {
      throw new Error('RELAYER_PRIVATE_KEY not configured');
    }
    this.signer = new ethers.Wallet(process.env.RELAYER_PRIVATE_KEY, this.provider);

    // Initialize insurance contract
    if (!process.env.INSURANCE_V3_ADDRESS) {
      throw new Error('INSURANCE_V3_ADDRESS not configured');
    }
    this.insuranceContract = new ethers.Contract(
      process.env.INSURANCE_V3_ADDRESS,
      X402InsuranceV3ABI.abi,
      this.signer
    );

    console.log(`Claim & Monitor Service initialized`);
    console.log(`Relayer address: ${this.signer.address}`);
  }

  // ============ Claim Processing ============

  /**
   * Process meta-transaction claim (zero gas for client)
   */
  async processMetaClaim(request: ClaimRequest): Promise<{
    success: boolean;
    transactionHash?: string;
    refundAmount?: string;
    error?: string;
  }> {
    try {
      console.log(`Processing claim for commitment: ${request.commitment}`);

      // Verify claim is valid
      const claimDetails = await this.insuranceContract.getClaimDetails(request.commitment);

      if (claimDetails.status !== 1) { // 1 = Locked
        return {
          success: false,
          error: 'Claim is not in locked status'
        };
      }

      if (claimDetails.client.toLowerCase() !== request.client.toLowerCase()) {
        return {
          success: false,
          error: 'Client address mismatch'
        };
      }

      const currentTime = Math.floor(Date.now() / 1000);
      if (currentTime < Number(claimDetails.unlockAt)) {
        return {
          success: false,
          error: 'Lock period not expired'
        };
      }

      // Execute meta-claim
      const tx = await this.insuranceContract.metaClaimInsurance(
        request.commitment,
        request.client,
        request.amount,
        request.deadline,
        request.v,
        request.r,
        request.s
      );

      const receipt = await tx.wait();

      console.log(`✅ Claim processed: ${receipt.hash}`);
      console.log(`   Refund: ${ethers.formatUnits(request.amount, 6)} USDC to ${request.client}`);

      return {
        success: true,
        transactionHash: receipt.hash,
        refundAmount: ethers.formatUnits(request.amount, 6)
      };

    } catch (error: any) {
      console.error('Claim processing failed:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }

  /**
   * Process direct claim (client pays gas)
   */
  async processDirectClaim(commitment: string, clientAddress: string): Promise<{
    success: boolean;
    shouldClaim: boolean;
    timeRemaining?: number;
    error?: string;
  }> {
    try {
      const claimDetails = await this.insuranceContract.getClaimDetails(commitment);

      if (claimDetails.status !== 1) {
        return {
          success: false,
          shouldClaim: false,
          error: 'Not in locked status'
        };
      }

      if (claimDetails.client.toLowerCase() !== clientAddress.toLowerCase()) {
        return {
          success: false,
          shouldClaim: false,
          error: 'Not your claim'
        };
      }

      const currentTime = Math.floor(Date.now() / 1000);
      const unlockTime = Number(claimDetails.unlockAt);

      if (currentTime >= unlockTime) {
        return {
          success: true,
          shouldClaim: true
        };
      } else {
        return {
          success: true,
          shouldClaim: false,
          timeRemaining: unlockTime - currentTime
        };
      }

    } catch (error: any) {
      return {
        success: false,
        shouldClaim: false,
        error: error.message
      };
    }
  }

  // ============ Auto Unlock Service ============

  /**
   * Start automatic unlock service
   */
  startAutoUnlockService(intervalMinutes: number = 60) {
    if (this.unlockInterval) {
      clearInterval(this.unlockInterval);
    }

    console.log(`Starting auto-unlock service (every ${intervalMinutes} minutes)`);

    const checkAndUnlock = async () => {
      try {
        console.log('Checking for expired locks...');

        // Get recent InsuranceLocked events
        const filter = this.insuranceContract.filters.InsuranceLocked();
        const events = await this.insuranceContract.queryFilter(filter, -5000); // Last 5000 blocks

        let unlockedCount = 0;
        const currentTime = Math.floor(Date.now() / 1000);

        for (const event of events) {
          if (!event.args) continue;

          const commitment = event.args[0];
          const unlockAt = Number(event.args[4]);

          // Check if should auto-unlock (48 hours after lock period)
          if (currentTime >= unlockAt + (24 * 60 * 60)) {
            try {
              const claimDetails = await this.insuranceContract.getClaimDetails(commitment);

              if (claimDetails.status === 1) { // Still locked
                console.log(`Auto-unlocking commitment: ${commitment}`);
                const tx = await this.insuranceContract.autoUnlock(commitment);
                await tx.wait();
                unlockedCount++;
                console.log(`✅ Auto-unlocked: ${commitment}`);
              }
            } catch (error) {
              console.error(`Failed to auto-unlock ${commitment}:`, error);
            }
          }
        }

        if (unlockedCount > 0) {
          console.log(`✅ Auto-unlocked ${unlockedCount} expired locks`);
        } else {
          console.log('No expired locks found');
        }

      } catch (error) {
        console.error('Auto-unlock service error:', error);
      }
    };

    // Run immediately
    checkAndUnlock();

    // Then run periodically
    this.unlockInterval = setInterval(checkAndUnlock, intervalMinutes * 60 * 1000);
  }

  /**
   * Stop auto-unlock service
   */
  stopAutoUnlockService() {
    if (this.unlockInterval) {
      clearInterval(this.unlockInterval);
      this.unlockInterval = undefined;
      console.log('Auto-unlock service stopped');
    }
  }

  // ============ Monitoring Service ============

  /**
   * Start monitoring service
   */
  startMonitoring(intervalMinutes: number = 5) {
    if (this.isMonitoring) {
      console.log('Monitoring already running');
      return;
    }

    this.isMonitoring = true;
    console.log(`Starting monitoring service (every ${intervalMinutes} minutes)`);

    const monitor = async () => {
      try {
        const stats = await this.getSystemStats();
        await this.checkSystemHealth(stats);
      } catch (error) {
        console.error('Monitoring error:', error);
      }
    };

    // Run immediately
    monitor();

    // Then run periodically
    this.monitoringInterval = setInterval(monitor, intervalMinutes * 60 * 1000);
  }

  /**
   * Stop monitoring service
   */
  stopMonitoring() {
    if (this.monitoringInterval) {
      clearInterval(this.monitoringInterval);
      this.monitoringInterval = undefined;
      this.isMonitoring = false;
      console.log('Monitoring service stopped');
    }
  }

  /**
   * Get system statistics
   */
  async getSystemStats(): Promise<MonitoringStats> {
    try {
      // Get platform stats from contract
      const platformStats = await this.insuranceContract.getPlatformStats();

      // Get provider warnings
      const filter = this.insuranceContract.filters.ProviderWarning();
      const recentWarnings = await this.insuranceContract.queryFilter(filter, -1000);

      const criticalProviders: Set<string> = new Set();
      const warningProviders: Set<string> = new Set();

      for (const event of recentWarnings) {
        if (!event.args) continue;
        const [provider, , level] = event.args;

        if (level === 'CRITICAL') {
          criticalProviders.add(provider);
        } else if (level === 'WARNING') {
          warningProviders.add(provider);
        }
      }

      // Calculate failure rate
      const totalTx = Number(platformStats.totalTransactions);
      const totalFailures = Number(platformStats.totalFailures);
      const failureRate = totalTx > 0 ? (totalFailures / totalTx) * 100 : 0;

      // Count pending unlocks
      const lockedFilter = this.insuranceContract.filters.InsuranceLocked();
      const lockedEvents = await this.insuranceContract.queryFilter(lockedFilter, -5000);

      let pendingUnlocks = 0;
      const currentTime = Math.floor(Date.now() / 1000);

      for (const event of lockedEvents) {
        if (!event.args) continue;
        const commitment = event.args[0];
        const unlockAt = Number(event.args[4]);

        if (currentTime >= unlockAt) {
          const details = await this.insuranceContract.getClaimDetails(commitment);
          if (details.status === 1) { // Still locked
            pendingUnlocks++;
          }
        }
      }

      return {
        totalPoolBalance: ethers.formatUnits(platformStats.totalPoolBalance, 6),
        totalLockedBalance: ethers.formatUnits(platformStats.totalLockedBalance, 6),
        activeProviders: Number(platformStats.activeProviders),
        totalTransactions: totalTx,
        totalFailures: totalFailures,
        failureRate: Math.round(failureRate * 100) / 100,
        platformRevenue: ethers.formatUnits(platformStats.totalPenalties, 6),
        pendingUnlocks,
        criticalProviders: Array.from(criticalProviders),
        warningProviders: Array.from(warningProviders)
      };

    } catch (error: any) {
      console.error('Failed to get system stats:', error);
      throw error;
    }
  }

  /**
   * Check system health and send alerts
   */
  async checkSystemHealth(stats: MonitoringStats) {
    console.log('\n📊 System Health Check');
    console.log('======================');
    console.log(`Total Pool Balance: $${stats.totalPoolBalance}`);
    console.log(`Total Locked: $${stats.totalLockedBalance}`);
    console.log(`Active Providers: ${stats.activeProviders}`);
    console.log(`Total Transactions: ${stats.totalTransactions}`);
    console.log(`Failure Rate: ${stats.failureRate}%`);
    console.log(`Platform Revenue: $${stats.platformRevenue}`);
    console.log(`Pending Unlocks: ${stats.pendingUnlocks}`);

    // Check for issues
    const alerts: string[] = [];

    if (stats.failureRate > 5) {
      alerts.push(`⚠️ High failure rate: ${stats.failureRate}%`);
    }

    if (stats.criticalProviders.length > 0) {
      alerts.push(`🚨 Critical providers: ${stats.criticalProviders.join(', ')}`);
    }

    if (stats.warningProviders.length > 0) {
      alerts.push(`⚠️ Warning providers: ${stats.warningProviders.join(', ')}`);
    }

    if (stats.pendingUnlocks > 10) {
      alerts.push(`⏰ High pending unlocks: ${stats.pendingUnlocks}`);
    }

    if (stats.activeProviders < 5) {
      alerts.push(`📉 Low active providers: ${stats.activeProviders}`);
    }

    // Send alerts
    if (alerts.length > 0) {
      console.log('\n🚨 ALERTS:');
      alerts.forEach(alert => console.log(`   ${alert}`));

      // In production, send to monitoring service
      await this.sendAlerts(alerts);
    } else {
      console.log('\n✅ System healthy');
    }
  }

  /**
   * Send alerts (placeholder - implement actual notification)
   */
  async sendAlerts(alerts: string[]) {
    // Implement notification service
    // Options: Email, Slack, Discord, PagerDuty, etc.

    if (process.env.SLACK_WEBHOOK) {
      try {
        // await axios.post(process.env.SLACK_WEBHOOK, {
        //   text: `X402 Insurance Alerts:\n${alerts.join('\n')}`
        // });
      } catch (error) {
        console.error('Failed to send Slack alert:', error);
      }
    }
  }

  /**
   * Get provider health status
   */
  async getProviderHealth(providerAddress: string): Promise<{
    status: 'HEALTHY' | 'WARNING' | 'CRITICAL' | 'INACTIVE';
    poolBalance: string;
    availableBalance: string;
    lockedBalance: string;
    successRate: number;
    recommendation?: string;
  }> {
    const info = await this.insuranceContract.getProviderInfo(providerAddress);
    const stats = await this.insuranceContract.getProviderStats(providerAddress);

    const poolBalance = Number(info.poolBalance);
    const availableBalance = Number(info.availableBalance);
    const lockedBalance = Number(info.lockedBalance);

    let status: 'HEALTHY' | 'WARNING' | 'CRITICAL' | 'INACTIVE';
    let recommendation;

    if (!info.isActive) {
      status = 'INACTIVE';
      recommendation = 'Provider needs to deposit funds to reactivate';
    } else if (poolBalance < 10 * 10**6) {
      status = 'CRITICAL';
      recommendation = 'Immediate deposit required to maintain service';
    } else if (poolBalance < 50 * 10**6) {
      status = 'WARNING';
      recommendation = 'Consider depositing more funds';
    } else {
      status = 'HEALTHY';
    }

    const totalTx = Number(stats.successCount) + Number(stats.failureCount);
    const successRate = totalTx > 0 ? (Number(stats.successCount) / totalTx) * 100 : 0;

    return {
      status,
      poolBalance: ethers.formatUnits(poolBalance, 6),
      availableBalance: ethers.formatUnits(availableBalance, 6),
      lockedBalance: ethers.formatUnits(lockedBalance, 6),
      successRate: Math.round(successRate * 100) / 100,
      recommendation
    };
  }
}

// ============ API Server ============

export function createClaimAPI(service: ClaimAndMonitorService) {
  const app = express();
  app.use(express.json());

  // Health check
  app.get('/health', (req, res) => {
    res.json({ status: 'ok', service: 'claim-and-monitor' });
  });

  // Process meta-claim
  app.post('/relay/claim', async (req, res) => {
    try {
      const result = await service.processMetaClaim(req.body);
      res.json(result);
    } catch (error: any) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Check claim status
  app.get('/claim/:commitment', async (req, res) => {
    try {
      const { commitment } = req.params;
      const { client } = req.query;

      if (!client) {
        return res.status(400).json({ error: 'Client address required' });
      }

      const result = await service.processDirectClaim(commitment, client as string);
      res.json(result);
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  });

  // Get system stats
  app.get('/stats', async (req, res) => {
    try {
      const stats = await service.getSystemStats();
      res.json(stats);
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  });

  // Get provider health
  app.get('/provider/:address/health', async (req, res) => {
    try {
      const health = await service.getProviderHealth(req.params.address);
      res.json(health);
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  });

  // Admin endpoints
  app.use('/admin', (req, res, next) => {
    const apiKey = req.headers['x-api-key'];
    if (apiKey !== process.env.ADMIN_API_KEY) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    next();
  });

  app.post('/admin/monitoring/start', (req, res) => {
    const { interval } = req.body;
    service.startMonitoring(interval || 5);
    res.json({ message: 'Monitoring started' });
  });

  app.post('/admin/monitoring/stop', (req, res) => {
    service.stopMonitoring();
    res.json({ message: 'Monitoring stopped' });
  });

  app.post('/admin/unlock/start', (req, res) => {
    const { interval } = req.body;
    service.startAutoUnlockService(interval || 60);
    res.json({ message: 'Auto-unlock service started' });
  });

  app.post('/admin/unlock/stop', (req, res) => {
    service.stopAutoUnlockService();
    res.json({ message: 'Auto-unlock service stopped' });
  });

  return app;
}

// ============ Main Entry Point ============

if (require.main === module) {
  async function main() {
    try {
      // Create service
      const service = new ClaimAndMonitorService();

      // Start auto-unlock service
      service.startAutoUnlockService(60); // Every hour

      // Start monitoring
      service.startMonitoring(5); // Every 5 minutes

      // Create and start API server
      const app = createClaimAPI(service);
      const PORT = process.env.CLAIM_SERVICE_PORT || 3002;

      app.listen(PORT, () => {
        console.log(`\n🚀 Claim & Monitor Service running on port ${PORT}`);
        console.log(`   Health: http://localhost:${PORT}/health`);
        console.log(`   Stats: http://localhost:${PORT}/stats`);
        console.log(`   Meta-claim: POST http://localhost:${PORT}/relay/claim`);
        console.log('\n   Admin endpoints require X-API-Key header');
      });

    } catch (error) {
      console.error('Failed to start service:', error);
      process.exit(1);
    }
  }

  main();
}