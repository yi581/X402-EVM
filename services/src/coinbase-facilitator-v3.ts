/**
 * Coinbase X402 Facilitator Integration with Insurance V3
 *
 * This service integrates the Coinbase X402 facilitator with our V3 insurance pool,
 * automatically locking insurance for every payment processed through the facilitator.
 */

import { ethers } from 'ethers';
import axios from 'axios';
import crypto from 'crypto';
import dotenv from 'dotenv';

dotenv.config();

// Import V3 Insurance ABI (we'll generate this)
import X402InsuranceV3ABI from '../abi/X402InsuranceV3.json';

// ============ Configuration ============

interface FacilitatorConfig {
  apiKeyId: string;
  apiKeySecret: string;
  baseUrl: string;
  network: 'base' | 'base-sepolia';
  insuranceAddress?: string;
}

interface PaymentRequest {
  amount: string;           // Amount in USDC
  recipient: string;        // Provider address
  sender: string;          // Client address
  network: string;         // 'base' or 'base-sepolia'
  currency: string;        // 'USDC'
  memo?: string;          // Optional memo
  commitment?: string;     // Optional commitment hash
}

interface PaymentVerificationResponse {
  valid: boolean;
  transactionHash?: string;
  blockNumber?: number;
  timestamp?: number;
  amount?: string;
  sender?: string;
  recipient?: string;
  error?: string;
}

interface InsuranceLockResult {
  success: boolean;
  lockTxHash?: string;
  commitment?: string;
  unlockAt?: number;
  error?: string;
}

// ============ Coinbase Facilitator Service ============

export class CoinbaseFacilitatorV3 {
  private config: FacilitatorConfig;
  private provider: ethers.JsonRpcProvider;
  private insuranceContract?: ethers.Contract;
  private signer?: ethers.Wallet;

  constructor(config: Partial<FacilitatorConfig> = {}) {
    this.config = {
      apiKeyId: config.apiKeyId || process.env.CDP_API_KEY_ID || '',
      apiKeySecret: config.apiKeySecret || process.env.CDP_API_KEY_SECRET || '',
      baseUrl: config.baseUrl || 'https://api.cdp.coinbase.com/x402/v1',
      network: config.network || 'base-sepolia',
      insuranceAddress: config.insuranceAddress || process.env.INSURANCE_V3_ADDRESS
    };

    // Initialize provider
    const rpcUrl = this.config.network === 'base'
      ? process.env.BASE_RPC_URL
      : process.env.BASE_SEPOLIA_RPC_URL;

    this.provider = new ethers.JsonRpcProvider(rpcUrl);

    // Initialize insurance contract if address provided
    if (this.config.insuranceAddress && process.env.PRIVATE_KEY) {
      this.signer = new ethers.Wallet(process.env.PRIVATE_KEY, this.provider);
      this.insuranceContract = new ethers.Contract(
        this.config.insuranceAddress,
        X402InsuranceV3ABI,
        this.signer
      );
    }
  }

  /**
   * Generate API signature for Coinbase requests
   */
  private generateSignature(
    method: string,
    path: string,
    body: string = ''
  ): { signature: string; timestamp: string } {
    const timestamp = Math.floor(Date.now() / 1000).toString();
    const message = timestamp + method.toUpperCase() + path + body;

    const signature = crypto
      .createHmac('sha256', this.config.apiKeySecret)
      .update(message)
      .digest('hex');

    return { signature, timestamp };
  }

  /**
   * Make authenticated request to Coinbase API
   */
  private async makeRequest<T>(
    method: string,
    path: string,
    data?: any
  ): Promise<T> {
    const body = data ? JSON.stringify(data) : '';
    const { signature, timestamp } = this.generateSignature(method, path, body);

    try {
      const response = await axios({
        method,
        url: `${this.config.baseUrl}${path}`,
        headers: {
          'CB-ACCESS-KEY': this.config.apiKeyId,
          'CB-ACCESS-SIGN': signature,
          'CB-ACCESS-TIMESTAMP': timestamp,
          'Content-Type': 'application/json'
        },
        data: body || undefined
      });

      return response.data;
    } catch (error: any) {
      console.error('Coinbase API error:', error.response?.data || error.message);
      throw error;
    }
  }

  /**
   * Verify a payment through Coinbase facilitator
   */
  async verifyPayment(paymentData: string): Promise<PaymentVerificationResponse> {
    try {
      // Parse payment data (expected to be from X-PAYMENT header)
      const payment = JSON.parse(Buffer.from(paymentData, 'base64').toString());

      // Verify with Coinbase facilitator
      const verification = await this.makeRequest<any>('POST', '/verify', {
        payment: paymentData,
        network: this.config.network,
        expectedRecipient: payment.recipient,
        expectedAmount: payment.amount
      });

      return {
        valid: verification.valid,
        transactionHash: verification.txHash,
        blockNumber: verification.blockNumber,
        timestamp: verification.timestamp,
        amount: verification.amount,
        sender: verification.sender,
        recipient: verification.recipient
      };
    } catch (error: any) {
      return {
        valid: false,
        error: error.message
      };
    }
  }

  /**
   * Lock insurance for a payment (V3 integration)
   */
  async lockInsurance(
    commitment: string,
    provider: string,
    client: string,
    amount: string
  ): Promise<InsuranceLockResult> {
    if (!this.insuranceContract) {
      return {
        success: false,
        error: 'Insurance contract not configured'
      };
    }

    try {
      // Convert amount to USDC units (6 decimals)
      const amountInUnits = ethers.parseUnits(amount, 6);

      // Call lockInsurance on V3 contract
      const tx = await this.insuranceContract.lockInsurance(
        commitment,
        provider,
        client,
        amountInUnits
      );

      // Wait for confirmation
      const receipt = await tx.wait();

      // Calculate unlock time (24 hours from now)
      const unlockAt = Math.floor(Date.now() / 1000) + (24 * 60 * 60);

      return {
        success: true,
        lockTxHash: receipt.hash,
        commitment,
        unlockAt
      };
    } catch (error: any) {
      console.error('Insurance lock error:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }

  /**
   * Process payment with insurance
   * This is the main integration point
   */
  async processPaymentWithInsurance(
    paymentData: string,
    commitment?: string
  ): Promise<{
    paymentValid: boolean;
    insuranceLocked: boolean;
    transactionHash?: string;
    insuranceTxHash?: string;
    error?: string;
  }> {
    // Step 1: Verify payment through Coinbase
    const verification = await this.verifyPayment(paymentData);

    if (!verification.valid) {
      return {
        paymentValid: false,
        insuranceLocked: false,
        error: verification.error || 'Payment verification failed'
      };
    }

    // Step 2: Lock insurance if contract is configured
    if (this.insuranceContract && verification.recipient && verification.sender && verification.amount) {
      // Generate commitment if not provided
      const finalCommitment = commitment || this.generateCommitment(
        verification.sender,
        verification.recipient,
        verification.amount,
        Date.now().toString()
      );

      const insuranceResult = await this.lockInsurance(
        finalCommitment,
        verification.recipient, // provider
        verification.sender,    // client
        verification.amount
      );

      return {
        paymentValid: true,
        insuranceLocked: insuranceResult.success,
        transactionHash: verification.transactionHash,
        insuranceTxHash: insuranceResult.lockTxHash,
        error: insuranceResult.error
      };
    }

    return {
      paymentValid: true,
      insuranceLocked: false,
      transactionHash: verification.transactionHash
    };
  }

  /**
   * Settle payment on blockchain
   */
  async settlePayment(paymentData: string): Promise<{
    success: boolean;
    transactionHash?: string;
    error?: string;
  }> {
    try {
      const settlement = await this.makeRequest<any>('POST', '/settle', {
        payment: paymentData,
        network: this.config.network
      });

      return {
        success: true,
        transactionHash: settlement.txHash
      };
    } catch (error: any) {
      return {
        success: false,
        error: error.message
      };
    }
  }

  /**
   * Generate commitment hash for insurance
   */
  private generateCommitment(
    client: string,
    provider: string,
    amount: string,
    nonce: string
  ): string {
    const payload = ethers.solidityPackedKeccak256(
      ['address', 'address', 'uint256', 'string'],
      [client, provider, ethers.parseUnits(amount, 6), nonce]
    );
    return payload;
  }

  /**
   * Check provider insurance status
   */
  async checkProviderStatus(providerAddress: string): Promise<{
    isActive: boolean;
    tier: string;
    poolBalance: string;
    availableBalance: string;
    successRate: number;
  }> {
    if (!this.insuranceContract) {
      throw new Error('Insurance contract not configured');
    }

    const info = await this.insuranceContract.getProviderInfo(providerAddress);

    const tierNames = ['None', 'Bronze', 'Silver', 'Gold', 'Platinum'];

    return {
      isActive: info.isActive,
      tier: tierNames[info.tier],
      poolBalance: ethers.formatUnits(info.poolBalance, 6),
      availableBalance: ethers.formatUnits(info.availableBalance, 6),
      successRate: info.successRate.toNumber()
    };
  }

  /**
   * Generate payment request for client
   */
  generatePaymentRequest(
    amount: string,
    recipient: string,
    memo?: string
  ): string {
    const request: PaymentRequest = {
      amount,
      recipient,
      sender: '', // Will be filled by client
      network: this.config.network,
      currency: 'USDC',
      memo,
      commitment: this.generateCommitment(
        '0x0000000000000000000000000000000000000000', // Placeholder
        recipient,
        amount,
        Date.now().toString()
      )
    };

    // Encode as base64 for X-PAYMENT-REQUEST header
    return Buffer.from(JSON.stringify(request)).toString('base64');
  }
}

// ============ Express Middleware ============

export function createX402Middleware(facilitator: CoinbaseFacilitatorV3) {
  return async (req: any, res: any, next: any) => {
    // Check if payment is required
    const paymentHeader = req.headers['x-payment'];

    if (!paymentHeader) {
      // No payment provided, return 402
      const amount = req.headers['x-payment-amount'] || '1.0'; // Default 1 USDC
      const recipient = req.headers['x-payment-recipient'] || process.env.PROVIDER_ADDRESS;

      if (!recipient) {
        return res.status(500).json({ error: 'Payment recipient not configured' });
      }

      const paymentRequest = facilitator.generatePaymentRequest(
        amount,
        recipient,
        `Payment for ${req.path}`
      );

      return res.status(402).json({
        error: 'Payment Required',
        payment: {
          amount,
          recipient,
          currency: 'USDC',
          network: facilitator['config'].network,
          request: paymentRequest
        }
      });
    }

    // Verify payment and lock insurance
    const result = await facilitator.processPaymentWithInsurance(paymentHeader);

    if (!result.paymentValid) {
      return res.status(400).json({
        error: 'Invalid payment',
        details: result.error
      });
    }

    // Add payment info to request for downstream use
    req.payment = {
      valid: true,
      transactionHash: result.transactionHash,
      insuranceLocked: result.insuranceLocked,
      insuranceTxHash: result.insuranceTxHash
    };

    next();
  };
}

// ============ Usage Example ============

if (require.main === module) {
  // Example: Create facilitator instance
  const facilitator = new CoinbaseFacilitatorV3({
    network: 'base-sepolia',
    insuranceAddress: process.env.INSURANCE_V3_ADDRESS
  });

  // Example: Express server with X402 middleware
  const express = require('express');
  const app = express();

  // Apply payment middleware to protected routes
  app.use('/api/paid', createX402Middleware(facilitator));

  app.get('/api/paid/data', async (req: any, res: any) => {
    // This route requires payment
    res.json({
      message: 'Payment verified!',
      payment: req.payment,
      data: 'Your premium content here'
    });
  });

  app.get('/api/provider/status/:address', async (req: any, res: any) => {
    try {
      const status = await facilitator.checkProviderStatus(req.params.address);
      res.json(status);
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  });

  const PORT = process.env.PORT || 3000;
  app.listen(PORT, () => {
    console.log(`X402 Facilitator Service running on port ${PORT}`);
    console.log(`Network: ${facilitator['config'].network}`);
    console.log(`Insurance Contract: ${facilitator['config'].insuranceAddress}`);
  });
}