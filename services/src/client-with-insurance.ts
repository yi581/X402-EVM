/**
 * X402 Client with Insurance Support
 *
 * This client demonstrates the x402 + Insurance hybrid model:
 * 1. Makes x402 payment (instant settlement to provider)
 * 2. Optionally purchases insurance for protection
 * 3. Can claim insurance if service fails or times out
 *
 * Benefits:
 * - Provider gets paid immediately (x402 preserved)
 * - Client has protection via insurance
 * - Provider earns insurance fee bonus if successful
 */

import axios from 'axios';
import { config } from 'dotenv';
import { ethers, Contract, Wallet } from 'ethers';
import { withPaymentInterceptor } from 'x402-axios';
import { createWalletClient, http } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { baseSepolia } from 'viem/chains';
import { calculateRequestCommitment, sleep, formatError } from './utils.js';
import fs from 'fs';
import path from 'path';
import X402InsuranceABI from '../abi/X402Insurance.json' assert { type: 'json' };

// Load environment variables
config();

const CLIENT_PRIVATE_KEY = process.env.CLIENT_PRIVATE_KEY as string;
const RPC_URL = process.env.RPC_URL || 'http://localhost:8545';
const CHAIN_ID = parseInt(process.env.CHAIN_ID || '84532');
const USDC_ADDRESS = process.env.USDC_ADDRESS as string;
const INSURANCE_ADDRESS = process.env.X402_INSURANCE_ADDRESS as string;

const SERVER_URL = 'http://localhost:4000';
const FACILITATOR_URL = 'http://localhost:4001';

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

interface InsuranceOptions {
  enabled: boolean;
  feePercentage: number; // e.g., 1 means 1% of payment amount
  timeoutMinutes: number; // How long to wait before can claim
}

interface InsuranceDetails {
  client: string;
  provider: string;
  paymentAmount: bigint;
  insuranceFee: bigint;
  deadline: bigint;
  status: number; // 0=Pending, 1=Confirmed, 2=Claimed
  timeLeft: bigint;
}

/**
 * Get server/provider address
 */
async function getProviderAddress(): Promise<string> {
  console.log('📡 Fetching provider address...');
  const response = await axios.get(`${SERVER_URL}/escrow`);
  const providerAddress = response.data.providerAddress || response.data.seller;
  console.log(`✅ Provider Address: ${providerAddress}\n`);
  return providerAddress;
}

/**
 * Check provider bond health in insurance contract
 */
async function checkProviderBond(
  insuranceContract: Contract,
  providerAddress: string
): Promise<{ bondBalance: bigint; minBond: bigint; isHealthy: boolean }> {
  console.log('🏥 Checking provider bond in insurance contract...');

  const stats = await insuranceContract.getProviderStats(providerAddress);

  console.log(
    `  Bond Balance: ${ethers.formatUnits(stats.bondBalance, 6)} USDC`
  );
  console.log(`  Minimum Bond: ${ethers.formatUnits(stats.minBond, 6)} USDC`);
  console.log(`  Status: ${stats.isHealthy ? '✅ Healthy' : '❌ Unhealthy'}\n`);

  return {
    bondBalance: stats.bondBalance,
    minBond: stats.minBond,
    isHealthy: stats.isHealthy,
  };
}

/**
 * Purchase insurance after x402 payment
 */
async function purchaseInsurance(
  insuranceContract: Contract,
  requestCommitment: string,
  providerAddress: string,
  paymentAmount: bigint,
  insuranceOptions: InsuranceOptions
): Promise<void> {
  console.log('\n🛡️  Purchasing insurance...');

  const insuranceFee =
    (paymentAmount * BigInt(insuranceOptions.feePercentage * 100)) / 10000n;

  console.log(
    `  Payment Amount: ${ethers.formatUnits(paymentAmount, 6)} USDC (already paid via x402)`
  );
  console.log(
    `  Insurance Fee: ${ethers.formatUnits(insuranceFee, 6)} USDC (${insuranceOptions.feePercentage}%)`
  );
  console.log(`  Timeout: ${insuranceOptions.timeoutMinutes} minutes`);
  console.log(`  Provider: ${providerAddress}`);

  const tx = await insuranceContract.purchaseInsurance(
    requestCommitment,
    providerAddress,
    paymentAmount,
    insuranceFee,
    insuranceOptions.timeoutMinutes
  );

  console.log(`  Transaction: ${tx.hash}`);
  console.log('  ⏳ Waiting for confirmation...');

  const receipt = await tx.wait();
  console.log(`  ✅ Insurance purchased! (Block ${receipt.blockNumber})\n`);
}

/**
 * Check if can claim insurance
 */
async function checkInsuranceClaim(
  insuranceContract: Contract,
  requestCommitment: string
): Promise<{ canClaim: boolean; details: InsuranceDetails }> {
  console.log('🔍 Checking insurance claim status...');

  const canClaim =
    await insuranceContract.canClaimInsurance(requestCommitment);
  const details = await insuranceContract.getClaimDetails(requestCommitment);

  const statusNames = ['Pending', 'Confirmed', 'Claimed'];

  console.log(`  Can Claim: ${canClaim ? '✅ Yes' : '❌ No'}`);
  console.log(`  Status: ${statusNames[details.status]}`);
  console.log(
    `  Payment Amount: ${ethers.formatUnits(details.paymentAmount, 6)} USDC`
  );
  console.log(
    `  Insurance Fee: ${ethers.formatUnits(details.insuranceFee, 6)} USDC`
  );

  if (details.timeLeft > 0n) {
    console.log(`  Time Left: ${details.timeLeft} seconds`);
  } else {
    console.log(`  ⏰ Timeout expired!`);
  }

  console.log();

  return {
    canClaim,
    details: {
      client: details.client,
      provider: details.provider,
      paymentAmount: details.paymentAmount,
      insuranceFee: details.insuranceFee,
      deadline: details.deadline,
      status: details.status,
      timeLeft: details.timeLeft,
    },
  };
}

/**
 * Claim insurance after timeout
 */
async function claimInsurance(
  insuranceContract: Contract,
  requestCommitment: string
): Promise<void> {
  console.log('\n💰 Claiming insurance...');

  const tx = await insuranceContract.claimInsurance(requestCommitment);

  console.log(`  Transaction: ${tx.hash}`);
  console.log('  ⏳ Waiting for confirmation...');

  const receipt = await tx.wait();
  console.log(`  ✅ Insurance claimed! (Block ${receipt.blockNumber})\n`);
}

/**
 * Make a paid request to the server using x402-axios
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

  // Create custom Base Sepolia chain config to match our RPC
  const customBaseSepolia = {
    ...baseSepolia,
    id: CHAIN_ID,
    rpcUrls: {
      default: { http: [RPC_URL] },
      public: { http: [RPC_URL] },
    },
  };

  const viemClient = createWalletClient({
    account,
    chain: customBaseSepolia,
    transport: http(RPC_URL),
  });

  // Create axios instance with x402 payment interceptor
  const api = withPaymentInterceptor(
    axios.create({
      baseURL: SERVER_URL,
    }),
    viemClient as any
  );

  // Make request - x402-axios will automatically handle 402 responses and retry with payment
  try {
    const response = await api.get(endpoint);

    // Extract x-payment header from request for commitment calculation
    const xpay =
      (response.config.headers?.['X-PAYMENT'] ||
        response.config.headers?.['x-payment'] ||
        response.config.headers?.['X-Payment'] ||
        '') as string;

    return { response, xpay };
  } catch (error: any) {
    // If request fails after payment, still return the response for analysis
    if (error.response) {
      const xpay =
        (error.config?.headers?.['x-payment'] ||
          error.config?.headers?.['X-Payment'] ||
          '') as string;
      return { response: error.response, xpay };
    }
    throw error;
  }
}

/**
 * Save insurance receipt to file
 */
function saveInsuranceReceipt(
  requestCommitment: string,
  details: any
): void {
  const filename = `insurance-${requestCommitment.slice(2, 12)}.json`;
  const filepath = path.join(process.cwd(), filename);

  const receipt = {
    timestamp: new Date().toISOString(),
    requestCommitment,
    ...details,
  };

  fs.writeFileSync(filepath, JSON.stringify(receipt, null, 2));
  console.log(`📄 Insurance receipt saved: ${filename}\n`);
}

/**
 * Main client flow with insurance
 */
async function main() {
  console.log('🚀 X402 Client with Insurance Support\n');
  console.log('='.repeat(50) + '\n');

  // Setup provider and wallet
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const wallet = new Wallet(CLIENT_PRIVATE_KEY, provider);
  const clientAddress = wallet.address;

  console.log(`👤 Client Address: ${clientAddress}\n`);

  // Step 1: Initialize contracts
  const usdcContract = new Contract(USDC_ADDRESS, ERC20_ABI, wallet);

  let insuranceContract: Contract | null = null;
  if (INSURANCE_ADDRESS) {
    insuranceContract = new Contract(
      INSURANCE_ADDRESS,
      X402InsuranceABI,
      wallet
    );
    console.log(`🛡️  Insurance Contract: ${INSURANCE_ADDRESS}\n`);
  }

  // Step 2: Check USDC balance
  const usdcBalance = await usdcContract.balanceOf(clientAddress);
  console.log(
    `💵 USDC Balance: ${ethers.formatUnits(usdcBalance, 6)} USDC\n`
  );

  if (usdcBalance === 0n) {
    console.error(
      '❌ Insufficient USDC balance. Please fund your wallet first.'
    );
    process.exit(1);
  }

  // Step 3: Get provider address
  const providerAddress = await getProviderAddress();

  // Step 4: Configure insurance options
  const insuranceOptions: InsuranceOptions = {
    enabled: !!insuranceContract,
    feePercentage: 1, // 1% of payment
    timeoutMinutes: 1, // 1 minute timeout for demo
  };

  // Step 5: Check provider bond if insurance enabled
  if (insuranceContract && insuranceOptions.enabled) {
    const bondInfo = await checkProviderBond(
      insuranceContract,
      providerAddress
    );

    if (!bondInfo.isHealthy) {
      console.warn(
        '⚠️  Provider bond is unhealthy. Insurance claims may not be honored.'
      );
      console.warn('   Consider disabling insurance or using a different provider.\n');
    }
  }

  // Step 6: Approve USDC for both server (x402 payment) and insurance contract
  const paymentAmount = 10_000n; // 0.01 USDC (matching $0.01 price)
  const insuranceFee =
    (paymentAmount * BigInt(insuranceOptions.feePercentage * 100)) / 10000n;
  const totalApproval = paymentAmount + insuranceFee;

  const serverAddress =
    process.env.SERVER_ADDRESS || '0x11a04550Cb4e281E3a62a6e4f37F4E8B480b0DAf';

  // Approve for server (x402 payment)
  const serverAllowance = await usdcContract.allowance(
    clientAddress,
    serverAddress
  );
  if (serverAllowance < paymentAmount) {
    console.log('🔓 Approving USDC for server (x402 payment)...');
    const approveTx = await usdcContract.approve(
      serverAddress,
      ethers.MaxUint256
    );
    await approveTx.wait();
    console.log('✅ USDC approved for server\n');
  }

  // Approve for insurance contract
  if (insuranceContract && insuranceOptions.enabled) {
    const insuranceAllowance = await usdcContract.allowance(
      clientAddress,
      INSURANCE_ADDRESS
    );
    if (insuranceAllowance < insuranceFee) {
      console.log('🔓 Approving USDC for insurance contract...');
      const approveTx = await usdcContract.approve(
        INSURANCE_ADDRESS,
        ethers.MaxUint256
      );
      await approveTx.wait();
      console.log('✅ USDC approved for insurance\n');
    }
  }

  // Step 7: Make paid request to /fail endpoint (simulates failure)
  console.log('='.repeat(50));
  console.log('SCENARIO: Requesting /fail with insurance protection');
  console.log('='.repeat(50) + '\n');

  const { response, xpay } = await makePaidRequest(
    '/fail',
    paymentAmount,
    wallet
  );

  console.log(`📊 Response Status: ${response.status}`);
  console.log(`📊 Response Data:`, JSON.stringify(response.data, null, 2));

  // Calculate request commitment
  const method = 'GET';
  const url = `${SERVER_URL}/fail`;
  const window = '60';
  const requestCommitment = calculateRequestCommitment(
    method,
    url,
    xpay,
    window
  );

  console.log(`\n🔑 Request Commitment: ${requestCommitment}\n`);

  // Step 8: Purchase insurance (even though payment already completed)
  if (insuranceContract && insuranceOptions.enabled) {
    console.log(
      '💡 Note: x402 payment already completed - provider received funds immediately'
    );
    console.log('   Now purchasing insurance for protection...\n');

    await purchaseInsurance(
      insuranceContract,
      requestCommitment,
      providerAddress,
      paymentAmount,
      insuranceOptions
    );

    // Save insurance receipt
    saveInsuranceReceipt(requestCommitment, {
      paymentAmount: paymentAmount.toString(),
      insuranceFee: insuranceFee.toString(),
      provider: providerAddress,
      timeoutMinutes: insuranceOptions.timeoutMinutes,
    });
  }

  // Step 9: Handle service failure
  if (response.status !== 200) {
    console.log('❌ Service request failed!\n');
    console.log(
      `   💸 x402 Payment settled: Client paid ${ethers.formatUnits(paymentAmount, 6)} USDC to Provider`
    );
    console.log(
      `   💸 Insurance purchased: Client paid ${ethers.formatUnits(insuranceFee, 6)} USDC insurance fee`
    );
    console.log(
      `   ⏰ Waiting ${insuranceOptions.timeoutMinutes} minute(s) for timeout...\n`
    );

    // Wait for timeout
    console.log(
      `⏳ Simulating ${insuranceOptions.timeoutMinutes}-minute wait...`
    );
    await sleep(insuranceOptions.timeoutMinutes * 60 * 1000 + 5000); // Add 5s buffer
    console.log('✅ Timeout period elapsed!\n');

    // Check if can claim
    if (insuranceContract) {
      const { canClaim, details } = await checkInsuranceClaim(
        insuranceContract,
        requestCommitment
      );

      if (canClaim) {
        // Check balance before claim
        const balanceBeforeClaim = await usdcContract.balanceOf(clientAddress);
        console.log(
          `💵 Balance before claim: ${ethers.formatUnits(balanceBeforeClaim, 6)} USDC`
        );

        // Claim insurance
        await claimInsurance(insuranceContract, requestCommitment);

        // Verify claim received
        const newBalance = await usdcContract.balanceOf(clientAddress);
        console.log(
          `💵 Balance after claim: ${ethers.formatUnits(newBalance, 6)} USDC`
        );
        console.log(
          `📈 Insurance payout: +${ethers.formatUnits(newBalance - balanceBeforeClaim, 6)} USDC`
        );
        console.log(
          `📈 Net change from initial: ${ethers.formatUnits(newBalance - usdcBalance, 6)} USDC\n`
        );

        console.log('💡 Summary:');
        console.log(
          `   - Paid provider via x402: ${ethers.formatUnits(paymentAmount, 6)} USDC`
        );
        console.log(
          `   - Paid insurance fee: ${ethers.formatUnits(insuranceFee, 6)} USDC`
        );
        console.log(
          `   - Received insurance claim: ${ethers.formatUnits(details.paymentAmount + details.insuranceFee, 6)} USDC`
        );
        console.log(
          `   - Net cost: ${ethers.formatUnits(usdcBalance - newBalance, 6)} USDC (ideally 0)\n`
        );
      } else {
        console.log('❌ Cannot claim insurance yet. Possible reasons:');
        console.log('   - Timeout not reached');
        console.log('   - Provider already confirmed service');
        console.log('   - Insurance already claimed\n');
      }
    }
  } else {
    console.log('✅ Request succeeded:', response.data);
    console.log(
      '\n💡 Note: If provider confirms service, they will earn the insurance fee as a bonus!\n'
    );
  }

  console.log('='.repeat(50));
  console.log('✅ Client with insurance demo completed!');
  console.log('='.repeat(50) + '\n');
}

// Run client
main().catch((error) => {
  console.error('\n❌ Client error:', formatError(error));
  process.exit(1);
});
