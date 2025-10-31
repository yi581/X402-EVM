/**
 * X402 Client with Autonomous Refund Support
 *
 * This client demonstrates:
 * 1. Pre-flight health check of escrow bond
 * 2. Making paid API requests using x402
 * 3. Automatically claiming refunds on service failure
 */

import axios from 'axios';
import { config } from 'dotenv';
import { ethers, Contract, Wallet } from 'ethers';
// @ts-ignore - x402 has issues with module resolution
import { createPaymentHeader } from 'x402';
import { createWalletClient, http } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { baseSepolia } from 'viem/chains';
import { calculateRequestCommitment, sleep, formatError } from './utils.js';
import fs from 'fs';
import path from 'path';
import BondedEscrowABI from '../abi/BondedEscrow.json';

// Load environment variables
config();

const CLIENT_PRIVATE_KEY = process.env.CLIENT_PRIVATE_KEY as string;
const RPC_URL = process.env.RPC_URL || 'http://localhost:8545';
const CHAIN_ID = parseInt(process.env.CHAIN_ID || '84532');
const USDC_ADDRESS = process.env.USDC_ADDRESS as string;

const SERVER_URL = 'http://localhost:3000';
const FACILITATOR_URL = 'http://localhost:3001';

if (!CLIENT_PRIVATE_KEY || !USDC_ADDRESS) {
  console.error('❌ Missing required environment variables:');
  if (!CLIENT_PRIVATE_KEY) console.error('  - CLIENT_PRIVATE_KEY');
  if (!USDC_ADDRESS) console.error('  - USDC_ADDRESS');
  process.exit(1);
}

// ERC20 ABI (minimal)
const ERC20_ABI = [
  'function balanceOf(address) view returns (uint256)',
  'function approve(address spender, uint256 amount) returns (bool)',
  'function allowance(address owner, address spender) view returns (uint256)',
];

interface RefundBundle {
  amount: string;
  signature: string;
}

interface FailedResponse {
  success: false;
  code: string;
  message: string;
  requestCommitment: string;
  refund: RefundBundle;
}

/**
 * Get escrow contract address from server
 */
async function getEscrowAddress(): Promise<string> {
  console.log('📡 Fetching escrow contract address...');
  const response = await axios.get(`${SERVER_URL}/escrow`);
  const address = response.data.address;
  console.log(`✅ Escrow Address: ${address}\n`);
  return address;
}

/**
 * Check escrow health before making payment
 */
async function checkEscrowHealth(
  escrowContract: Contract
): Promise<boolean> {
  console.log('🏥 Checking escrow health...');

  const isHealthy = await escrowContract.isHealthy();
  const bondBalance = await escrowContract.getBondBalance();
  const minBond = await escrowContract.minBond();

  console.log(`  Bond Balance: ${ethers.formatUnits(bondBalance, 6)} USDC`);
  console.log(`  Minimum Bond: ${ethers.formatUnits(minBond, 6)} USDC`);
  console.log(`  Status: ${isHealthy ? '✅ Healthy' : '❌ Unhealthy'}\n`);

  return isHealthy;
}

/**
 * Make a paid request to the server
 */
async function makePaidRequest(
  endpoint: string,
  paymentAmount: bigint,
  wallet: Wallet
): Promise<any> {
  const url = `${SERVER_URL}${endpoint}`;
  console.log(`💰 Making paid request to ${endpoint}...`);

  // Create viem wallet client for x402
  const account = privateKeyToAccount(CLIENT_PRIVATE_KEY as `0x${string}`);
  const viemClient = createWalletClient({
    account,
    chain: baseSepolia,
    transport: http(RPC_URL),
  });

  // Prepare payment requirements
  const paymentRequirements = {
    scheme: 'exact' as const,
    network: 'base-sepolia' as const,
    asset: USDC_ADDRESS,
    amount: paymentAmount.toString(),
    to: SERVER_URL,
  };

  // Create x402 payment header (version 1)
  const xpay = await createPaymentHeader(viemClient, 1, paymentRequirements);

  // Make request
  const response = await axios.get(url, {
    headers: {
      'x-payment': xpay,
    },
    validateStatus: () => true, // Don't throw on 4xx/5xx
  });

  return { response, xpay };
}

/**
 * Claim refund from escrow
 */
async function claimRefund(
  escrowContract: Contract,
  requestCommitment: string,
  refundBundle: RefundBundle
): Promise<void> {
  console.log('\n💸 Claiming refund from escrow...');
  console.log(`  Request Commitment: ${requestCommitment}`);
  console.log(`  Amount: ${ethers.formatUnits(refundBundle.amount, 6)} USDC`);

  const tx = await escrowContract.claimRefund(
    requestCommitment,
    refundBundle.amount,
    refundBundle.signature
  );

  console.log(`  Transaction: ${tx.hash}`);
  console.log('  ⏳ Waiting for confirmation...');

  const receipt = await tx.wait();
  console.log(`  ✅ Refund claimed! (Block ${receipt.blockNumber})\n`);
}

/**
 * Save refund receipt to file
 */
function saveRefundReceipt(
  requestCommitment: string,
  refundBundle: RefundBundle
): void {
  const filename = `refund-${requestCommitment.slice(2, 12)}.json`;
  const filepath = path.join(process.cwd(), filename);

  const receipt = {
    timestamp: new Date().toISOString(),
    requestCommitment,
    ...refundBundle,
  };

  fs.writeFileSync(filepath, JSON.stringify(receipt, null, 2));
  console.log(`📄 Refund receipt saved: ${filename}\n`);
}

/**
 * Main client flow
 */
async function main() {
  console.log('🚀 X402 Client with Autonomous Refund\n');
  console.log('='.repeat(50) + '\n');

  // Setup provider and wallet
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const wallet = new Wallet(CLIENT_PRIVATE_KEY, provider);
  const clientAddress = wallet.address;

  console.log(`👤 Client Address: ${clientAddress}\n`);

  // Step 1: Get escrow address
  const escrowAddress = await getEscrowAddress();

  // Step 2: Initialize contracts
  const escrowContract = new Contract(escrowAddress, BondedEscrowABI, wallet);
  const usdcContract = new Contract(USDC_ADDRESS, ERC20_ABI, wallet);

  // Step 3: Check USDC balance
  const usdcBalance = await usdcContract.balanceOf(clientAddress);
  console.log(`💵 USDC Balance: ${ethers.formatUnits(usdcBalance, 6)} USDC\n`);

  if (usdcBalance === 0n) {
    console.error('❌ Insufficient USDC balance. Please fund your wallet first.');
    process.exit(1);
  }

  // Step 4: Check escrow health
  const isHealthy = await checkEscrowHealth(escrowContract);

  if (!isHealthy) {
    console.error('❌ Escrow is not healthy. Aborting request.');
    process.exit(1);
  }

  // Step 5: Approve USDC for facilitator (if needed)
  const paymentAmount = 1_000_000n; // 1 USDC
  const allowance = await usdcContract.allowance(clientAddress, FACILITATOR_URL);

  if (allowance < paymentAmount) {
    console.log('🔓 Approving USDC for facilitator...');
    const approveTx = await usdcContract.approve(
      FACILITATOR_URL,
      ethers.MaxUint256
    );
    await approveTx.wait();
    console.log('✅ USDC approved\n');
  }

  // Step 6: Make paid request to /fail endpoint (simulates failure)
  console.log('='.repeat(50));
  console.log('SCENARIO: Requesting /fail (service failure)');
  console.log('='.repeat(50) + '\n');

  const { response, xpay } = await makePaidRequest('/fail', paymentAmount, wallet);

  // Step 7: Handle response
  if (response.status === 400 && response.data.refund) {
    const failedResponse: FailedResponse = response.data;

    console.log(`❌ Request failed: ${failedResponse.message}`);
    console.log(`   Error Code: ${failedResponse.code}\n`);

    // Verify request commitment matches
    const method = 'GET';
    const url = `${SERVER_URL}/fail`;
    const window = '60';
    const calculatedCommitment = calculateRequestCommitment(method, url, xpay, window);

    if (calculatedCommitment !== failedResponse.requestCommitment) {
      console.error('❌ Request commitment mismatch! Possible attack.');
      process.exit(1);
    }

    // Save refund receipt
    saveRefundReceipt(failedResponse.requestCommitment, failedResponse.refund);

    // Claim refund
    await claimRefund(
      escrowContract,
      failedResponse.requestCommitment,
      failedResponse.refund
    );

    // Verify refund received
    const newBalance = await usdcContract.balanceOf(clientAddress);
    console.log(`💵 New USDC Balance: ${ethers.formatUnits(newBalance, 6)} USDC`);
    console.log(`📈 Balance Change: +${ethers.formatUnits(newBalance - usdcBalance, 6)} USDC\n`);
  } else {
    console.log('✅ Request succeeded:', response.data);
  }

  console.log('='.repeat(50));
  console.log('✅ Client demo completed successfully!');
  console.log('='.repeat(50) + '\n');
}

// Run client
main().catch((error) => {
  console.error('\n❌ Client error:', formatError(error));
  process.exit(1);
});
