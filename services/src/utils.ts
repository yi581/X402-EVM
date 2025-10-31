/**
 * Shared utilities for X402 refund system
 */

import { keccak256, encodeAbiParameters, parseAbiParameters } from 'viem';

/**
 * Calculate request commitment hash
 *
 * This is a unique identifier for each API request, used to prevent double-refunds.
 *
 * @param method HTTP method (e.g., "GET")
 * @param url Full request URL (e.g., "http://localhost:3000/fail")
 * @param xpay x-payment header value (hex string)
 * @param window Time window parameter (e.g., "60")
 * @returns bytes32 commitment hash
 */
export function calculateRequestCommitment(
  method: string,
  url: string,
  xpay: string,
  window: string
): `0x${string}` {
  const encoded = encodeAbiParameters(
    parseAbiParameters('string, string, string, string'),
    [method, url, xpay, window]
  );

  return keccak256(encoded);
}

/**
 * Format error message for display
 */
export function formatError(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }
  return String(error);
}

/**
 * Sleep utility for delays
 */
export function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}
