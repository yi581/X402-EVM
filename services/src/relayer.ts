/**
 * X402 Guard Relayer Service
 *
 * 功能：
 * - 监听客户端退款签名请求
 * - 代付 gas 执行 Meta Transaction
 * - 记录 gas 消耗统计
 * - 自动从 Gas Tank 补充 ETH
 */

import express, { Request, Response } from 'express';
import { config } from 'dotenv';
import { ethers, Contract, Wallet } from 'ethers';
import BondedEscrowV2ABI from '../abi/BondedEscrowV2.json';

// Load environment variables
config();

const RELAYER_PRIVATE_KEY = process.env.RELAYER_PRIVATE_KEY as string;
const RPC_URL = process.env.RPC_URL || 'http://localhost:8545';
const PORT = parseInt(process.env.RELAYER_PORT || '4002');
const USDC_ADDRESS = process.env.USDC_ADDRESS as string;

if (!RELAYER_PRIVATE_KEY || !USDC_ADDRESS) {
  console.error('❌ Missing required environment variables:');
  if (!RELAYER_PRIVATE_KEY) console.error('  - RELAYER_PRIVATE_KEY');
  if (!USDC_ADDRESS) console.error('  - USDC_ADDRESS');
  process.exit(1);
}

// Setup provider and relayer wallet
const provider = new ethers.JsonRpcProvider(RPC_URL);
const relayerWallet = new Wallet(RELAYER_PRIVATE_KEY, provider);

// Express app
const app = express();
app.use(express.json());

// Statistics
let stats = {
  totalRelays: 0,
  successfulRelays: 0,
  failedRelays: 0,
  totalGasUsed: BigInt(0),
  totalGasCost: BigInt(0),
};

/**
 * Health check endpoint
 */
app.get('/health', async (req: Request, res: Response) => {
  try {
    const balance = await provider.getBalance(relayerWallet.address);
    const blockNumber = await provider.getBlockNumber();

    res.json({
      success: true,
      relayer: relayerWallet.address,
      ethBalance: ethers.formatEther(balance),
      blockNumber,
      network: await provider.getNetwork().then(n => n.chainId),
      stats,
    });
  } catch (error) {
    res.status(500).json({ success: false, error: (error as Error).message });
  }
});

/**
 * POST /relay-refund
 * 客户端提交 Meta Transaction 签名，Relayer 代付 gas 执行
 */
app.post('/relay-refund', async (req: Request, res: Response) => {
  const startTime = Date.now();
  stats.totalRelays++;

  try {
    const {
      escrowAddress,
      requestCommitment,
      amount,
      client,
      deadline,
      clientSignature,
      serverSignature,
    } = req.body;

    // Validate parameters
    if (!escrowAddress || !requestCommitment || !amount || !client || !deadline || !clientSignature || !serverSignature) {
      return res.status(400).json({
        success: false,
        error: 'Missing required parameters',
      });
    }

    console.log('\n⚡ Relayer: Processing Meta Transaction');
    console.log(`  Client: ${client}`);
    console.log(`  Amount: ${ethers.formatUnits(amount, 6)} USDC`);
    console.log(`  Escrow: ${escrowAddress}`);
    console.log(`  Request Commitment: ${requestCommitment}`);

    // Create contract instance
    const escrow = new Contract(escrowAddress, BondedEscrowV2ABI, relayerWallet);

    // Check if already settled
    const isSettled = await escrow.commitmentSettled(requestCommitment);
    if (isSettled) {
      return res.status(400).json({
        success: false,
        error: 'Request already settled',
      });
    }

    // Check deadline
    const now = Math.floor(Date.now() / 1000);
    if (now > deadline) {
      return res.status(400).json({
        success: false,
        error: 'Signature expired',
      });
    }

    // Estimate gas
    const gasEstimate = await escrow.metaClaimRefund.estimateGas(
      requestCommitment,
      amount,
      client,
      deadline,
      clientSignature,
      serverSignature
    );

    console.log(`  Estimated Gas: ${gasEstimate.toString()}`);

    // Execute transaction (Relayer pays gas!)
    const tx = await escrow.metaClaimRefund(
      requestCommitment,
      amount,
      client,
      deadline,
      clientSignature,
      serverSignature,
      {
        gasLimit: gasEstimate * BigInt(120) / BigInt(100), // 20% buffer
      }
    );

    console.log(`  ⏳ Transaction sent: ${tx.hash}`);
    console.log(`  Waiting for confirmation...`);

    const receipt = await tx.wait();

    // Calculate gas cost
    const gasUsed = receipt.gasUsed;
    const effectiveGasPrice = receipt.gasPrice || tx.gasPrice;
    const gasCost = gasUsed * effectiveGasPrice;

    // Update stats
    stats.successfulRelays++;
    stats.totalGasUsed += gasUsed;
    stats.totalGasCost += gasCost;

    const elapsed = Date.now() - startTime;

    console.log(`  ✅ Refund relayed successfully!`);
    console.log(`  Block: ${receipt.blockNumber}`);
    console.log(`  Gas Used: ${gasUsed.toString()}`);
    console.log(`  Gas Cost: ${ethers.formatEther(gasCost)} ETH`);
    console.log(`  Elapsed: ${elapsed}ms\n`);

    res.json({
      success: true,
      txHash: tx.hash,
      blockNumber: receipt.blockNumber,
      gasUsed: gasUsed.toString(),
      gasCost: ethers.formatEther(gasCost),
      elapsed: `${elapsed}ms`,
      message: 'Refund claimed! Gas paid by X402 Guard platform.',
    });

  } catch (error) {
    stats.failedRelays++;
    console.error('❌ Relay failed:', error);

    const elapsed = Date.now() - startTime;

    res.status(500).json({
      success: false,
      error: (error as Error).message,
      elapsed: `${elapsed}ms`,
    });
  }
});

/**
 * POST /relay-timeout-refund
 * 超时退款（无需服务器签名）
 */
app.post('/relay-timeout-refund', async (req: Request, res: Response) => {
  const startTime = Date.now();
  stats.totalRelays++;

  try {
    const { escrowAddress, requestCommitment, clientSignature } = req.body;

    if (!escrowAddress || !requestCommitment || !clientSignature) {
      return res.status(400).json({
        success: false,
        error: 'Missing required parameters',
      });
    }

    console.log('\n⏰ Relayer: Processing Timeout Refund');
    console.log(`  Escrow: ${escrowAddress}`);
    console.log(`  Request Commitment: ${requestCommitment}`);

    const escrow = new Contract(escrowAddress, BondedEscrowV2ABI, relayerWallet);

    // Get payment info
    const payment = await escrow.pendingPayments(requestCommitment);
    if (payment.refunded || payment.completed) {
      return res.status(400).json({
        success: false,
        error: 'Payment already settled',
      });
    }

    // Check if expired
    const now = Math.floor(Date.now() / 1000);
    if (now <= payment.deadline) {
      return res.status(400).json({
        success: false,
        error: 'Payment not yet expired',
        timeLeft: payment.deadline - now,
      });
    }

    // Execute timeout refund
    const tx = await escrow.claimTimeoutRefund(requestCommitment);
    console.log(`  ⏳ Transaction sent: ${tx.hash}`);

    const receipt = await tx.wait();
    const gasUsed = receipt.gasUsed;
    const gasCost = gasUsed * (receipt.gasPrice || tx.gasPrice);

    stats.successfulRelays++;
    stats.totalGasUsed += gasUsed;
    stats.totalGasCost += gasCost;

    const elapsed = Date.now() - startTime;

    console.log(`  ✅ Timeout refund processed!`);
    console.log(`  Gas Cost: ${ethers.formatEther(gasCost)} ETH`);
    console.log(`  Elapsed: ${elapsed}ms\n`);

    res.json({
      success: true,
      txHash: tx.hash,
      blockNumber: receipt.blockNumber,
      gasUsed: gasUsed.toString(),
      gasCost: ethers.formatEther(gasCost),
      elapsed: `${elapsed}ms`,
    });

  } catch (error) {
    stats.failedRelays++;
    console.error('❌ Relay failed:', error);

    res.status(500).json({
      success: false,
      error: (error as Error).message,
    });
  }
});

/**
 * GET /stats
 * 获取 Relayer 统计数据
 */
app.get('/stats', async (req: Request, res: Response) => {
  const ethBalance = await provider.getBalance(relayerWallet.address);
  const avgGasCost = stats.successfulRelays > 0
    ? stats.totalGasCost / BigInt(stats.successfulRelays)
    : BigInt(0);

  res.json({
    success: true,
    relayer: relayerWallet.address,
    ethBalance: ethers.formatEther(ethBalance),
    stats: {
      ...stats,
      totalGasUsed: stats.totalGasUsed.toString(),
      totalGasCost: ethers.formatEther(stats.totalGasCost),
      avgGasCost: ethers.formatEther(avgGasCost),
      successRate: stats.totalRelays > 0
        ? ((stats.successfulRelays / stats.totalRelays) * 100).toFixed(2) + '%'
        : '0%',
    },
  });
});

/**
 * POST /reset-stats
 * 重置统计数据（仅用于测试）
 */
app.post('/reset-stats', (req: Request, res: Response) => {
  stats = {
    totalRelays: 0,
    successfulRelays: 0,
    failedRelays: 0,
    totalGasUsed: BigInt(0),
    totalGasCost: BigInt(0),
  };

  res.json({ success: true, message: 'Stats reset' });
});

// Start server
app.listen(PORT, () => {
  console.log('🚀 X402 Guard Relayer Service Starting...\n');
  console.log(`✅ Relayer running on http://localhost:${PORT}`);
  console.log(`🔑 Relayer Address: ${relayerWallet.address}`);
  console.log(`⛓️  RPC URL: ${RPC_URL}\n`);
  console.log('Available endpoints:');
  console.log(`  GET  /health              - Health check`);
  console.log(`  POST /relay-refund        - Relay meta transaction refund`);
  console.log(`  POST /relay-timeout-refund - Relay timeout refund`);
  console.log(`  GET  /stats               - Get relayer statistics`);
  console.log(`  POST /reset-stats         - Reset statistics\n`);
  console.log('💡 Tip: Fund this address with ETH to pay for gas fees');
  console.log('='.repeat(60) + '\n');
});

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\n\n👋 Shutting down relayer...');
  console.log('Final stats:', {
    ...stats,
    totalGasUsed: stats.totalGasUsed.toString(),
    totalGasCost: ethers.formatEther(stats.totalGasCost),
  });
  process.exit(0);
});

// Check relayer balance on startup
(async () => {
  const balance = await provider.getBalance(relayerWallet.address);
  const balanceEth = ethers.formatEther(balance);

  if (parseFloat(balanceEth) < 0.01) {
    console.warn('⚠️  WARNING: Relayer ETH balance is low!');
    console.warn(`   Current: ${balanceEth} ETH`);
    console.warn(`   Please fund ${relayerWallet.address} with ETH\n`);
  } else {
    console.log(`💰 Relayer ETH Balance: ${balanceEth} ETH\n`);
  }
})();
