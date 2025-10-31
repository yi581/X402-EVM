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
const FACILITATOR_URL = process.env.FACILITATOR_URL || 'http://localhost:4001';

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
    // For EXACT scheme: payload.authorization.value contains the amount
    const amount = paymentData.payload?.authorization?.value ||
                   paymentData.payload?.amount ||
                   paymentData.amount ||
                   '10000'; // Fallback to 0.01 USDC (matches price: '$0.01')

    console.log('DEBUG: Decoded payment amount:', amount);
    return { amount };
  } catch (error) {
    // Fallback: assume 0.01 USDC (10000 units with 6 decimals)
    console.warn('Failed to decode payment header:', error);
    return { amount: '10000' };
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
    },
    FACILITATOR_URL
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
 *
 * IMPORTANT: This endpoint uses paymentMiddleware to:
 * 1. Verify the payment signature
 * 2. Settle the payment (execute real USDC transfer from client to server)
 * 3. Then simulate a service failure
 * 4. Return a refund authorization for the client to claim back their money
 */
app.get(
  '/fail',
  paymentMiddleware(
    wallet.address as `0x${string}`,
    {
      '/fail': {
        price: '$0.01', // 0.01 USD = 10000 units (USDC has 6 decimals)
        network: 'base-sepolia',
      },
    },
    FACILITATOR_URL
  ),
  async (req: Request, res: Response) => {
    try {
      // At this point, paymentMiddleware has already:
      // 1. Verified the payment
      // 2. Settled the payment (USDC transferred from client to server)

      // Get x-payment header
      const xpay = req.headers['x-payment'] as string;

      // Decode payment to get amount
      const decoded = decodePaymentHeader(xpay);
      const amount = decoded.amount;

      // Calculate request commitment
      const method = req.method; // "GET"
      const url = `${req.protocol}://${req.get('host')}${req.originalUrl}`;
      const window = '60'; // Time window parameter

      const requestCommitment = calculateRequestCommitment(method, url, xpay, window);

      console.log('\n🔴 Service failure detected (AFTER payment settled):');
      console.log(`  Method: ${method}`);
      console.log(`  URL: ${url}`);
      console.log(`  Payment Amount: ${amount}`);
      console.log(`  💸 USDC already transferred: Client → Server`);
      console.log(`  Request Commitment: ${requestCommitment}`);

      // Sign refund authorization
      const signature = await signRefundClaim(requestCommitment, amount);

      console.log(`  Signature: ${signature.slice(0, 20)}...`);
      console.log('  ✅ Refund authorization signed\n');

      // Return 200 with refund bundle (not 400, because payment succeeded)
      // The service "fails" logically but payment was already settled
      res.status(200).json({
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
  }
);

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
