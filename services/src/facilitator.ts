/**
 * X402 Payment Facilitator
 *
 * This service handles payment settlement for x402 protocol.
 * It verifies payment signatures and processes on-chain transfers.
 */

import { Facilitator, createExpressAdapter } from '@x402-sovereign/core';
import { baseSepolia } from 'viem/chains';
import { config } from 'dotenv';
import express from 'express';

// Load environment variables
config();

const FACILITATOR_PRIVATE_KEY = process.env.FACILITATOR_PRIVATE_KEY as string;
const RPC_URL = process.env.RPC_URL || 'http://localhost:8545';
const PORT = parseInt(process.env.FACILITATOR_PORT || '3001');
const CHAIN_ID = parseInt(process.env.CHAIN_ID || '84532');

if (!FACILITATOR_PRIVATE_KEY) {
  console.error('❌ FACILITATOR_PRIVATE_KEY not set in .env');
  process.exit(1);
}

async function main() {
  console.log('🚀 Starting X402 Facilitator...\n');

  // Create facilitator instance
  const facilitator = new Facilitator({
    evmPrivateKey: FACILITATOR_PRIVATE_KEY,
    networks: [
      {
        ...baseSepolia,
        id: CHAIN_ID,
        rpcUrls: {
          default: { http: [RPC_URL] },
          public: { http: [RPC_URL] },
        },
      },
    ],
  });

  // Create Express app
  const app = express();
  app.use(express.json());

  // Mount facilitator endpoints using Express adapter
  createExpressAdapter(facilitator, app, '/');

  // Start server
  app.listen(PORT, () => {
    console.log('✅ Facilitator running on port', PORT);
    console.log(`📡 RPC URL: ${RPC_URL}`);
    console.log(`⛓️  Chain ID: ${CHAIN_ID}`);
    console.log('\nReady to process x402 payments...\n');
  });

  // Graceful shutdown
  process.on('SIGINT', () => {
    console.log('\n\n👋 Shutting down facilitator...');
    process.exit(0);
  });
}

main().catch((error) => {
  console.error('❌ Facilitator error:', error);
  process.exit(1);
});
