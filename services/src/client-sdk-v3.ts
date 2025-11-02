/**
 * X402 Insurance V3 Client SDK
 *
 * Complete client SDK for interacting with the X402 Insurance V3 protocol.
 * Handles payment creation, insurance verification, and claim processing.
 */

import { ethers } from 'ethers';
import axios from 'axios';
import X402InsuranceV3ABI from '../abi/X402InsuranceV3.json';

// ============ Types ============

export interface X402PaymentRequest {
  scheme: 'exact';
  network: 'base' | 'base-sepolia';
  asset: string; // USDC address
  payTo: string; // Provider address
  maxAmountRequired: string; // Amount in smallest units
  facilitator: string; // Facilitator URL
}

export interface InsuranceInfo {
  isActive: boolean;
  tier: 'None' | 'Bronze' | 'Silver' | 'Gold' | 'Platinum';
  poolBalance: string;
  availableBalance: string;
  successRate: number;
  hasInsurance: boolean;
}

export interface PaymentResult {
  success: boolean;
  transactionHash?: string;
  insuranceLocked?: boolean;
  commitment?: string;
  error?: string;
}

export interface ClaimResult {
  success: boolean;
  refundAmount?: string;
  transactionHash?: string;
  error?: string;
}

export interface ClientConfig {
  rpcUrl: string;
  insuranceAddress: string;
  privateKey?: string;
  signer?: ethers.Signer;
}

// ============ Client SDK Class ============

export class X402ClientSDK {
  private provider: ethers.JsonRpcProvider;
  private signer: ethers.Signer;
  private insuranceContract: ethers.Contract;
  private address: string;

  constructor(config: ClientConfig) {
    // Initialize provider
    this.provider = new ethers.JsonRpcProvider(config.rpcUrl);

    // Initialize signer
    if (config.signer) {
      this.signer = config.signer;
    } else if (config.privateKey) {
      this.signer = new ethers.Wallet(config.privateKey, this.provider);
    } else {
      throw new Error('Either signer or privateKey must be provided');
    }

    // Get address
    this.address = '';
    this.signer.getAddress().then(addr => {
      this.address = addr;
    });

    // Initialize insurance contract
    this.insuranceContract = new ethers.Contract(
      config.insuranceAddress,
      X402InsuranceV3ABI.abi,
      this.signer
    );
  }

  /**
   * Parse 402 Payment Required response
   */
  parse402Response(responseBody: any): X402PaymentRequest {
    if (!responseBody.x402Version || !responseBody.accepts) {
      throw new Error('Invalid 402 response format');
    }

    const accept = responseBody.accepts[0];
    return {
      scheme: accept.scheme,
      network: accept.network,
      asset: accept.asset,
      payTo: accept.payTo,
      maxAmountRequired: accept.maxAmountRequired,
      facilitator: accept.facilitator
    };
  }

  /**
   * Check if provider has insurance
   */
  async checkInsurance(providerAddress: string): Promise<InsuranceInfo> {
    try {
      // Get provider info from contract
      const info = await this.insuranceContract.getProviderInfo(providerAddress);

      // Calculate success rate
      const stats = await this.insuranceContract.getProviderStats(providerAddress);
      const totalTx = Number(stats.successCount) + Number(stats.failureCount);
      const successRate = totalTx > 0 ? (Number(stats.successCount) * 100) / totalTx : 0;

      // Determine tier name
      const tierNames = ['None', 'Bronze', 'Silver', 'Gold', 'Platinum'];
      const tier = tierNames[Number(info.tier)] as InsuranceInfo['tier'];

      return {
        isActive: info.isActive,
        tier,
        poolBalance: ethers.formatUnits(info.poolBalance, 6),
        availableBalance: ethers.formatUnits(info.availableBalance, 6),
        successRate: Math.round(successRate * 100) / 100,
        hasInsurance: info.isActive && Number(info.availableBalance) > 0
      };
    } catch (error: any) {
      console.error('Failed to check insurance:', error);
      return {
        isActive: false,
        tier: 'None',
        poolBalance: '0',
        availableBalance: '0',
        successRate: 0,
        hasInsurance: false
      };
    }
  }

  /**
   * Create and sign payment
   */
  async createPayment(
    request: X402PaymentRequest,
    memo?: string
  ): Promise<string> {
    // Create payment object
    const payment = {
      to: request.payTo,
      amount: request.maxAmountRequired,
      asset: request.asset,
      network: request.network,
      from: this.address,
      nonce: Date.now(),
      memo
    };

    // Sign payment
    const message = ethers.solidityPackedKeccak256(
      ['address', 'address', 'uint256', 'address', 'string', 'uint256'],
      [payment.from, payment.to, payment.amount, payment.asset, payment.network, payment.nonce]
    );

    const signature = await this.signer.signMessage(ethers.getBytes(message));

    // Combine payment and signature
    const signedPayment = {
      ...payment,
      signature
    };

    // Encode as base64
    return Buffer.from(JSON.stringify(signedPayment)).toString('base64');
  }

  /**
   * Make payment with insurance protection
   */
  async makePayment(
    apiUrl: string,
    headers?: Record<string, string>
  ): Promise<PaymentResult> {
    try {
      // Step 1: Make initial request
      const initialResponse = await axios.get(apiUrl, {
        headers,
        validateStatus: (status) => status === 402 || status < 400
      });

      if (initialResponse.status !== 402) {
        return {
          success: true,
          error: 'No payment required'
        };
      }

      // Step 2: Parse payment request
      const paymentRequest = this.parse402Response(initialResponse.data);

      // Step 3: Check insurance
      const insurance = await this.checkInsurance(paymentRequest.payTo);

      console.log(`Provider Insurance Status:`);
      console.log(`  Active: ${insurance.isActive}`);
      console.log(`  Tier: ${insurance.tier}`);
      console.log(`  Success Rate: ${insurance.successRate}%`);

      if (!insurance.hasInsurance) {
        console.warn('⚠️ Warning: Provider does not have insurance protection');
        // Optionally, ask user to confirm
        // if (!await confirmPaymentWithoutInsurance()) return;
      }

      // Step 4: Create payment
      const paymentData = await this.createPayment(paymentRequest);

      // Step 5: Record payment for insurance (if available)
      let commitment: string | undefined;
      if (insurance.hasInsurance) {
        commitment = ethers.keccak256(ethers.toUtf8Bytes(paymentData));

        // Note: In production, this would be done by the facilitator
        // Here we show how it could be called directly
        try {
          const tx = await this.insuranceContract.lockInsurance(
            commitment,
            paymentRequest.payTo,
            this.address,
            ethers.parseUnits(ethers.formatUnits(paymentRequest.maxAmountRequired, 0), 6)
          );
          await tx.wait();
          console.log('✅ Insurance locked for this payment');
        } catch (error) {
          console.error('Failed to lock insurance:', error);
        }
      }

      // Step 6: Make payment request
      const paymentResponse = await axios.get(apiUrl, {
        headers: {
          ...headers,
          'X-PAYMENT': paymentData
        }
      });

      return {
        success: true,
        transactionHash: paymentResponse.headers['x-payment-response'],
        insuranceLocked: insurance.hasInsurance,
        commitment
      };

    } catch (error: any) {
      return {
        success: false,
        error: error.message
      };
    }
  }

  /**
   * Claim insurance (for failed delivery)
   */
  async claimInsurance(commitment: string): Promise<ClaimResult> {
    try {
      // Check claim status
      const claimDetails = await this.insuranceContract.getClaimDetails(commitment);

      if (claimDetails.status !== 1) { // 1 = Locked
        return {
          success: false,
          error: 'Claim is not in locked status'
        };
      }

      // Check if timeout has passed
      const currentTime = Math.floor(Date.now() / 1000);
      if (currentTime < Number(claimDetails.unlockAt)) {
        const timeLeft = Number(claimDetails.unlockAt) - currentTime;
        const hoursLeft = Math.floor(timeLeft / 3600);
        return {
          success: false,
          error: `Cannot claim yet. ${hoursLeft} hours remaining`
        };
      }

      // Submit claim
      const tx = await this.insuranceContract.claimInsurance(commitment);
      const receipt = await tx.wait();

      return {
        success: true,
        refundAmount: ethers.formatUnits(claimDetails.amount, 6),
        transactionHash: receipt.hash
      };

    } catch (error: any) {
      return {
        success: false,
        error: error.message
      };
    }
  }

  /**
   * Claim insurance with meta-transaction (zero gas)
   */
  async createMetaClaimSignature(
    commitment: string,
    relayerUrl: string
  ): Promise<ClaimResult> {
    try {
      // Get claim details
      const claimDetails = await this.insuranceContract.getClaimDetails(commitment);

      // Get nonce
      const nonce = await this.insuranceContract.clientNonces(this.address);

      // Create deadline (1 hour from now)
      const deadline = Math.floor(Date.now() / 1000) + 3600;

      // Create EIP-712 signature
      const domain = {
        name: 'X402InsuranceV3',
        version: '1.0.0',
        chainId: await this.provider.getNetwork().then(n => n.chainId),
        verifyingContract: await this.insuranceContract.getAddress()
      };

      const types = {
        ClaimInsurance: [
          { name: 'commitment', type: 'bytes32' },
          { name: 'client', type: 'address' },
          { name: 'amount', type: 'uint256' },
          { name: 'nonce', type: 'uint256' },
          { name: 'deadline', type: 'uint256' }
        ]
      };

      const value = {
        commitment,
        client: this.address,
        amount: claimDetails.amount,
        nonce: Number(nonce),
        deadline
      };

      // Sign the data
      const signature = await this.signer.signTypedData(domain, types, value);
      const { v, r, s } = ethers.Signature.from(signature);

      // Send to relayer
      const response = await axios.post(`${relayerUrl}/relay/claim`, {
        commitment,
        client: this.address,
        amount: claimDetails.amount.toString(),
        deadline,
        v,
        r,
        s
      });

      if (response.data.success) {
        return {
          success: true,
          refundAmount: ethers.formatUnits(claimDetails.amount, 6),
          transactionHash: response.data.transactionHash
        };
      } else {
        return {
          success: false,
          error: response.data.error
        };
      }

    } catch (error: any) {
      return {
        success: false,
        error: error.message
      };
    }
  }

  /**
   * Get all pending claims for this client
   */
  async getPendingClaims(): Promise<Array<{
    commitment: string;
    provider: string;
    amount: string;
    lockedAt: Date;
    unlockAt: Date;
    canClaimNow: boolean;
  }>> {
    // This would require event filtering or a separate indexer
    // For now, return empty array
    // In production, you would query events or use a subgraph
    return [];
  }

  /**
   * Monitor payment status
   */
  async monitorPayment(
    commitment: string,
    callback: (status: string) => void
  ): Promise<void> {
    const checkStatus = async () => {
      const details = await this.insuranceContract.getClaimDetails(commitment);
      const statusNames = ['None', 'Locked', 'Success', 'Failed'];
      const status = statusNames[Number(details.status)];

      callback(status);

      if (status === 'Locked') {
        // Check again in 1 minute
        setTimeout(checkStatus, 60000);
      }
    };

    checkStatus();
  }
}

// ============ Utility Functions ============

/**
 * Format insurance info for display
 */
export function formatInsuranceInfo(info: InsuranceInfo): string {
  const tierEmoji = {
    'None': '❌',
    'Bronze': '🥉',
    'Silver': '🥈',
    'Gold': '🥇',
    'Platinum': '💎'
  };

  return `
Insurance Status:
  Active: ${info.isActive ? '✅' : '❌'}
  Tier: ${tierEmoji[info.tier]} ${info.tier}
  Pool Balance: ${info.poolBalance} USDC
  Available: ${info.availableBalance} USDC
  Success Rate: ${info.successRate}%
  Protected: ${info.hasInsurance ? '✅ Yes' : '⚠️ No'}
  `;
}

/**
 * Calculate potential refund
 */
export function calculateRefund(amount: string): {
  refundAmount: string;
  platformFee: string;
  providerLoss: string;
} {
  const amountNum = parseFloat(amount);
  return {
    refundAmount: amount, // 100% refund to client
    platformFee: (amountNum * 0.02).toFixed(2), // 2% to platform
    providerLoss: (amountNum * 1.02).toFixed(2) // 102% from provider
  };
}

// ============ Usage Example ============

if (require.main === module) {
  async function example() {
    // Initialize SDK
    const sdk = new X402ClientSDK({
      rpcUrl: process.env.BASE_SEPOLIA_RPC || 'https://sepolia.base.org',
      insuranceAddress: process.env.INSURANCE_V3_ADDRESS!,
      privateKey: process.env.CLIENT_PRIVATE_KEY!
    });

    // Example 1: Check provider insurance
    const providerAddress = '0x...';
    const insurance = await sdk.checkInsurance(providerAddress);
    console.log(formatInsuranceInfo(insurance));

    // Example 2: Make payment with insurance
    const result = await sdk.makePayment('https://api.provider.com/data');
    if (result.success) {
      console.log('Payment successful!');
      console.log('Transaction:', result.transactionHash);
      console.log('Insurance:', result.insuranceLocked ? 'Protected' : 'Not protected');

      if (result.commitment) {
        // Monitor the payment
        sdk.monitorPayment(result.commitment, (status) => {
          console.log('Payment status:', status);
        });
      }
    }

    // Example 3: Claim insurance (if service not delivered)
    if (result.commitment) {
      // Wait 24 hours...
      setTimeout(async () => {
        const claim = await sdk.claimInsurance(result.commitment!);
        if (claim.success) {
          console.log(`Refund received: ${claim.refundAmount} USDC`);
        }
      }, 24 * 60 * 60 * 1000);
    }
  }

  // Run example if this file is executed directly
  example().catch(console.error);
}