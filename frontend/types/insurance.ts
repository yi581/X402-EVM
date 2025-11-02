/**
 * X402 Insurance V8 TypeScript 类型定义
 */

import { BigNumberish } from 'ethers';

// ==================== 枚举类型 ====================

export enum ClaimReason {
  NOT_DELIVERED = 0,      // 未交付
  SERVICE_TIMEOUT = 1,    // 服务超时
  PARTIAL_DELIVERY = 2    // 部分交付
}

export enum ClaimStatus {
  INITIATED = 0,    // 已发起
  DISPUTED = 1,     // 有争议
  EXECUTED = 2,     // 已执行
  REJECTED = 3,     // 已拒绝
  PARTIAL = 4       // 部分支付
}

export enum ProviderTier {
  BRONZE = 1,
  SILVER = 2,
  GOLD = 3
}

// ==================== 数据结构 ====================

export interface ProviderData {
  isActive: boolean;
  poolBalance: bigint;
  totalLocked: bigint;
  successfulServices: bigint;
  failedServices: bigint;
  tier: ProviderTier;
  registeredAt: bigint;
}

export interface ClaimInfo {
  client: string;
  provider: string;
  requestedAmount: bigint;
  paidAmount: bigint;
  pendingAmount: bigint;
  initiatedAt: bigint;
  disputeDeadline: bigint;
  reason: ClaimReason;
  status: ClaimStatus;
}

export interface PendingCompensation {
  commitment: string;
  client: string;
  amount: bigint;
  createdAt: bigint;
  isPaid: boolean;
}

export interface PendingCompensations {
  commitments: string[];
  amounts: bigint[];
  totalAmount: bigint;
}

export interface ServiceCapacity {
  canAccept: boolean;
  reason: string;
}

export interface GlobalStats {
  totalProviderPools: bigint;
  emergencyPool: bigint;
  platformInsuranceFund: bigint;
  totalPendingCompensations: bigint;
}

// ==================== 格式化后的数据类型 ====================

export interface FormattedProviderInfo {
  isActive: boolean;
  poolBalance: string;          // 格式化后的USDC金额
  totalLocked: string;
  availableBalance: string;
  successfulServices: number;
  failedServices: number;
  tier: ProviderTier;
  registeredAt: Date;
  riskScore?: number;           // 计算出的风险评分
}

export interface FormattedClaimInfo {
  commitment: string;
  client: string;
  provider: string;
  requestedAmount: string;      // 格式化后的USDC金额
  paidAmount: string;
  pendingAmount: string;
  initiatedAt: Date;
  disputeDeadline: Date;
  reason: ClaimReason;
  status: ClaimStatus;
  paymentRatio: number;         // 支付比例 (0-100)
}

export interface FormattedPendingCompensations {
  commitments: string[];
  amounts: string[];            // 格式化后的USDC金额数组
  totalAmount: string;
  count: number;
}

export interface FormattedGlobalStats {
  totalProviderPools: string;
  emergencyPool: string;
  platformInsuranceFund: string;
  totalPendingCompensations: string;
  totalValue: string;           // 总锁仓价值
}

// ==================== 事件类型 ====================

export interface ProviderRegisteredEvent {
  provider: string;
  amount: bigint;
  blockNumber: number;
  transactionHash: string;
}

export interface ClaimInitiatedEvent {
  commitment: string;
  client: string;
  provider: string;
  amount: bigint;
  blockNumber: number;
  transactionHash: string;
}

export interface ClaimExecutedEvent {
  commitment: string;
  paidAmount: bigint;
  pendingAmount: bigint;
  blockNumber: number;
  transactionHash: string;
}

export interface CompensationPaidEvent {
  commitment: string;
  client: string;
  amount: bigint;
  blockNumber: number;
  transactionHash: string;
}

// ==================== 交易参数类型 ====================

export interface RegisterProviderParams {
  amount: BigNumberish;
}

export interface InitiateClaimParams {
  commitment?: string;           // 可选，不提供则自动生成
  provider: string;
  amount: BigNumberish;
  reason: ClaimReason;
}

export interface DisputeClaimParams {
  commitment: string;
  evidence: string;
}

// ==================== API响应类型 ====================

export interface ProvidersListResponse {
  providers: FormattedProviderInfo[];
  total: number;
  page?: number;
  limit?: number;
}

export interface ClaimsListResponse {
  claims: FormattedClaimInfo[];
  pagination: {
    total: number;
    page: number;
    limit: number;
    hasNext: boolean;
    hasPrev: boolean;
  };
}

export interface ProviderDetailsResponse {
  info: FormattedProviderInfo;
  claims: FormattedClaimInfo[];
  pendingCompensations: FormattedPendingCompensations;
  statistics: {
    totalClaims: number;
    totalPaid: string;
    totalPending: string;
    successRate: number;
  };
}

// ==================== 错误类型 ====================

export class InsuranceError extends Error {
  constructor(
    message: string,
    public code?: string,
    public data?: any
  ) {
    super(message);
    this.name = 'InsuranceError';
  }
}

export interface TransactionError {
  reason?: string;
  code?: string;
  method?: string;
  transaction?: any;
  receipt?: any;
}

// ==================== 工具函数类型 ====================

export interface InsuranceUtils {
  formatUsdc(amount: bigint): string;
  parseUsdc(amount: string | number): bigint;
  generateCommitment(prefix?: string): string;
  calculateRiskScore(provider: ProviderData): number;
  getDisputePeriod(amount: bigint): number;
  formatTimestamp(timestamp: bigint): Date;
}

// ==================== React Hook 返回类型 ====================

export interface UseInsuranceReturn {
  // 状态
  isConnected: boolean;
  isLoading: boolean;
  error: Error | null;
  account: string | null;

  // Provider功能
  registerProvider: (amount: string) => Promise<string>;
  depositAdditional: (amount: string) => Promise<string>;
  withdraw: (amount: string) => Promise<string>;
  withdrawAll: () => Promise<string>;

  // 索赔功能
  initiateClaim: (params: InitiateClaimParams) => Promise<{
    commitment: string;
    txHash: string;
    paidAmount: string;
    pendingAmount: string;
    status: ClaimStatus;
  }>;
  executeClaim: (commitment: string) => Promise<string>;
  disputeClaim: (params: DisputeClaimParams) => Promise<string>;

  // 查询功能
  getProviderInfo: (address: string) => Promise<FormattedProviderInfo>;
  getClaimInfo: (commitment: string) => Promise<FormattedClaimInfo>;
  getPendingCompensations: (provider: string) => Promise<FormattedPendingCompensations>;
  getGlobalStats: () => Promise<FormattedGlobalStats>;
  canAcceptService: (provider: string, amount: string) => Promise<ServiceCapacity>;

  // 工具函数
  connect: () => Promise<void>;
  disconnect: () => void;
  switchNetwork: () => Promise<void>;
}