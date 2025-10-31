/**
 * X402 Resource Server with Refund Support
 *
 * This server provides paid API endpoints and can issue refund authorizations
 * when services fail to deliver.
 */

import express, { Request, Response } from 'express';
import { config } from 'dotenv';
import { paymentMiddleware } from 'x402-express';
import { Wallet } from 'ethers';
import { decodeAbiParameters, parseAbiParameters } from 'viem';
import { calculateRequestCommitment } from './utils.js';

// Load environment variables
config();

const SERVER_PRIVATE_KEY = process.env.SERVER_PRIVATE_KEY as string;
const BOND_ESCROW_ADDRESS = process.env.BOND_ESCROW_ADDRESS as string;
const RPC_URL = process.env.RPC_URL || 'http://localhost:8545';
const CHAIN_ID = parseInt(process.env.CHAIN_ID || '84532');
const PORT = parseInt(process.env.SERVER_PORT || '3000');

if (!SERVER_PRIVATE_KEY || !BOND_ESCROW_ADDRESS) {
  console.error('❌ Missing required environment variables:');
  if (!SERVER_PRIVATE_KEY) console.error('  - SERVER_PRIVATE_KEY');
  if (!BOND_ESCROW_ADDRESS) console.error('  - BOND_ESCROW_ADDRESS');
  process.exit(1);
}

const app = express();
const wallet = new Wallet(SERVER_PRIVATE_KEY);

// EIP-712 Domain for BondedEscrow
const DOMAIN = {
  name: 'BondedEscrow',
  version: '1',
  chainId: CHAIN_ID,
  verifyingContract: BOND_ESCROW_ADDRESS as `0x${string}`,
};

// EIP-712 RefundClaim type
const REFUND_CLAIM_TYPE = {
  RefundClaim: [
    { name: 'requestCommitment', type: 'bytes32' },
    { name: 'amount', type: 'uint256' },
  ],
};

/**
 * Decode x402 payment header to extract amount
 * This is a simplified decoder for the EXACT payment scheme
 */
function decodePaymentHeader(xpay: string): { amount: string } {
  try {
    // The x402 payment header is base64 encoded JSON
    const decoded = Buffer.from(xpay, 'base64').toString('utf-8');
    const paymentData = JSON.parse(decoded);

    // Extract amount from payment data
    // The structure varies but amount should be in the payload
    const amount = paymentData.payload?.amount || paymentData.amount || '1000000';

    return { amount };
  } catch (error) {
    // Fallback: assume 1 USDC if decode fails
    console.warn('Failed to decode payment header:', error);
    return { amount: '1000000' };
  }
}

/**
 * Sign refund authorization using EIP-712
 */
async function signRefundClaim(
  requestCommitment: string,
  amount: string
): Promise<string> {
  const message = {
    requestCommitment,
    amount,
  };

  // Sign using ethers v6 TypedDataEncoder
  const signature = await wallet.signTypedData(DOMAIN, REFUND_CLAIM_TYPE, message);
  return signature;
}

// ==============================================================
//                         ENDPOINTS
// ==============================================================

/**
 * GET /escrow
 * Returns the escrow contract address
 */
app.get('/escrow', (req: Request, res: Response) => {
  res.json({
    success: true,
    address: BOND_ESCROW_ADDRESS,
  });
});

/**
 * GET /premium
 * Successful paid endpoint (returns content after payment verification)
 */
app.get(
  '/premium',
  paymentMiddleware(
    wallet.address as `0x${string}`,
    {
      '/premium': {
        price: '$0.01',
        network: 'base-sepolia',
      },
    }
  ),
  (req: Request, res: Response) => {
    res.json({
      success: true,
      message: 'Premium content delivered!',
      data: {
        secret: 'This is valuable paid content',
        timestamp: new Date().toISOString(),
      },
    });
  }
);

/**
 * GET /fail
 * Simulates a failed service that returns a refund authorization
 */
app.get('/fail', async (req: Request, res: Response) => {
  try {
    // Get x-payment header
    const xpay = req.headers['x-payment'] as string;

    if (!xpay) {
      return res.status(400).json({
        success: false,
        error: 'Missing x-payment header',
      });
    }

    // Decode payment to get amount
    const decoded = decodePaymentHeader(xpay);
    const amount = decoded.amount;

    // Calculate request commitment
    const method = req.method; // "GET"
    const url = `${req.protocol}://${req.get('host')}${req.originalUrl}`;
    const window = '60'; // Time window parameter

    const requestCommitment = calculateRequestCommitment(method, url, xpay, window);

    console.log('\n🔴 Service failure detected:');
    console.log(`  Method: ${method}`);
    console.log(`  URL: ${url}`);
    console.log(`  Payment Amount: ${amount}`);
    console.log(`  Request Commitment: ${requestCommitment}`);

    // Sign refund authorization
    const signature = await signRefundClaim(requestCommitment, amount);

    console.log(`  Signature: ${signature.slice(0, 20)}...`);
    console.log('  ✅ Refund authorization signed\n');

    // Return 400 with refund bundle
    res.status(400).json({
      success: false,
      code: 'INTERNAL_ERROR',
      message: 'Service temporarily unavailable',
      requestCommitment,
      refund: {
        amount,
        signature,
      },
    });
  } catch (error) {
    console.error('❌ Error processing failed request:', error);
    res.status(500).json({
      success: false,
      error: 'Internal server error',
    });
  }
});

/**
 * GET /health
 * Health check endpoint
 */
app.get('/health', (req: Request, res: Response) => {
  res.json({
    success: true,
    status: 'healthy',
    escrowAddress: BOND_ESCROW_ADDRESS,
  });
});

// Start server
app.listen(PORT, () => {
  console.log('🚀 X402 Resource Server Starting...\n');
  console.log(`✅ Server running on http://localhost:${PORT}`);
  console.log(`📄 Escrow Contract: ${BOND_ESCROW_ADDRESS}`);
  console.log(`🔑 Signer Address: ${wallet.address}`);
  console.log(`⛓️  Chain ID: ${CHAIN_ID}\n`);
  console.log('Available endpoints:');
  console.log(`  GET /escrow   - Get escrow contract address`);
  console.log(`  GET /premium  - Paid endpoint (success scenario)`);
  console.log(`  GET /fail     - Paid endpoint (failure + refund)`);
  console.log(`  GET /health   - Health check\n`);
});

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\n\n👋 Shutting down server...');
  process.exit(0);
});
