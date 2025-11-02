/**
 * X402 Insurance V8 JavaScript SDK
 * 即插即用的前端SDK
 */

import { ethers } from 'ethers';

// 合约地址和ABI
const CONTRACT_ADDRESS = '0x72486eF40BB3729298369d608de85c612adb223e';
const USDC_ADDRESS = '0x036CbD53842c5426634e7929541eC2318f3dCF7e';
const RPC_URL = 'https://sepolia.base.org';

// 简化的ABI
const INSURANCE_ABI = [
  'function registerOrReactivate(uint256 amount)',
  'function depositAdditional(uint256 amount)',
  'function withdraw(uint256 amount)',
  'function withdrawAllAndDeactivate()',
  'function initiateClaim(bytes32 commitment, address provider, uint256 amount, uint8 reason)',
  'function executeClaim(bytes32 commitment)',
  'function disputeClaim(bytes32 commitment, string memory evidence)',
  'function getProviderInfo(address provider) view returns (bool isActive, uint256 poolBalance, uint256 totalLocked, uint256 successfulServices, uint256 failedServices, uint8 tier, uint256 registeredAt)',
  'function getClaimInfo(bytes32 commitment) view returns (address client, address provider, uint256 requestedAmount, uint256 paidAmount, uint256 pendingAmount, uint256 initiatedAt, uint256 disputeDeadline, uint8 reason, uint8 status)',
  'function getProviderPendingCompensations(address provider) view returns (bytes32[] memory commitments, uint256[] memory amounts, uint256 totalAmount)',
  'function canAcceptService(address provider, uint256 serviceAmount) view returns (bool canAccept, string memory reason)',
  'function totalProviderPools() view returns (uint256)',
  'function emergencyPool() view returns (uint256)',
  'function platformInsuranceFund() view returns (uint256)',
  'function totalPendingCompensations() view returns (uint256)',
  'function MIN_POOL_BALANCE() view returns (uint256)',
  'function PENALTY_RATE() view returns (uint256)',
  'function MAX_EXPOSURE_RATIO() view returns (uint256)',
  'event ProviderRegistered(address indexed provider, uint256 amount)',
  'event ClaimInitiated(bytes32 indexed commitment, address indexed client, address indexed provider, uint256 amount)',
  'event ClaimExecuted(bytes32 indexed commitment, uint256 paidAmount, uint256 pendingAmount)',
  'event CompensationPaid(bytes32 indexed commitment, address indexed client, uint256 amount)'
];

const USDC_ABI = [
  'function approve(address spender, uint256 amount) returns (bool)',
  'function balanceOf(address owner) view returns (uint256)',
  'function allowance(address owner, address spender) view returns (uint256)'
];

// 索赔原因枚举
const ClaimReason = {
  NOT_DELIVERED: 0,
  SERVICE_TIMEOUT: 1,
  PARTIAL_DELIVERY: 2
};

// 索赔状态枚举
const ClaimStatus = {
  INITIATED: 0,
  DISPUTED: 1,
  EXECUTED: 2,
  REJECTED: 3,
  PARTIAL: 4
};

class X402InsuranceSDK {
  constructor(signerOrProvider) {
    if (signerOrProvider) {
      this.provider = signerOrProvider.provider || signerOrProvider;
      this.signer = signerOrProvider.provider ? signerOrProvider : null;
    } else {
      this.provider = new ethers.JsonRpcProvider(RPC_URL);
      this.signer = null;
    }

    this.contract = new ethers.Contract(
      CONTRACT_ADDRESS,
      INSURANCE_ABI,
      this.signer || this.provider
    );

    this.usdcContract = new ethers.Contract(
      USDC_ADDRESS,
      USDC_ABI,
      this.signer || this.provider
    );
  }

  // ==================== 连接钱包 ====================

  /**
   * 连接MetaMask钱包
   */
  static async connectWallet() {
    if (typeof window === 'undefined' || !window.ethereum) {
      throw new Error('MetaMask not installed');
    }

    await window.ethereum.request({ method: 'eth_requestAccounts' });

    const provider = new ethers.BrowserProvider(window.ethereum);
    const signer = await provider.getSigner();

    // 切换到Base Sepolia网络
    try {
      await window.ethereum.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: '0x14a34' }] // 84532 in hex
      });
    } catch (error) {
      if (error.code === 4902) {
        await X402InsuranceSDK.addBaseSepoliaNetwork();
      }
    }

    return new X402InsuranceSDK(signer);
  }

  /**
   * 添加Base Sepolia网络到MetaMask
   */
  static async addBaseSepoliaNetwork() {
    await window.ethereum.request({
      method: 'wallet_addEthereumChain',
      params: [{
        chainId: '0x14a34',
        chainName: 'Base Sepolia',
        nativeCurrency: {
          name: 'Ethereum',
          symbol: 'ETH',
          decimals: 18
        },
        rpcUrls: ['https://sepolia.base.org'],
        blockExplorerUrls: ['https://sepolia.basescan.org']
      }]
    });
  }

  // ==================== Provider功能 ====================

  /**
   * 注册或重新激活Provider
   * @param {string} amount - USDC金额（如 "100"）
   */
  async registerProvider(amount) {
    if (!this.signer) throw new Error('Wallet not connected');

    const parsedAmount = ethers.parseUnits(amount.toString(), 6);

    // 检查并授权USDC
    await this.approveUSDC(parsedAmount);

    // 注册Provider
    const tx = await this.contract.registerOrReactivate(parsedAmount);
    await tx.wait();

    return tx.hash;
  }

  /**
   * 追加保险金
   * @param {string} amount - USDC金额
   */
  async depositAdditional(amount) {
    if (!this.signer) throw new Error('Wallet not connected');

    const parsedAmount = ethers.parseUnits(amount.toString(), 6);
    await this.approveUSDC(parsedAmount);

    const tx = await this.contract.depositAdditional(parsedAmount);
    await tx.wait();

    return tx.hash;
  }

  /**
   * 提取资金
   * @param {string} amount - USDC金额
   */
  async withdraw(amount) {
    if (!this.signer) throw new Error('Wallet not connected');

    const parsedAmount = ethers.parseUnits(amount.toString(), 6);
    const tx = await this.contract.withdraw(parsedAmount);
    await tx.wait();

    return tx.hash;
  }

  /**
   * 提取全部并停用
   */
  async withdrawAll() {
    if (!this.signer) throw new Error('Wallet not connected');

    const tx = await this.contract.withdrawAllAndDeactivate();
    await tx.wait();

    return tx.hash;
  }

  // ==================== 索赔功能 ====================

  /**
   * 发起索赔
   * @param {Object} params
   * @param {string} params.provider - Provider地址
   * @param {string} params.amount - 索赔金额
   * @param {number} params.reason - 索赔原因（0-2）
   */
  async initiateClaim({ provider, amount, reason = 0 }) {
    if (!this.signer) throw new Error('Wallet not connected');

    const commitment = ethers.keccak256(
      ethers.toUtf8Bytes(`claim-${Date.now()}-${Math.random()}`)
    );
    const parsedAmount = ethers.parseUnits(amount.toString(), 6);

    const tx = await this.contract.initiateClaim(
      commitment,
      provider,
      parsedAmount,
      reason
    );
    await tx.wait();

    // 获取索赔详情
    const claimInfo = await this.getClaimInfo(commitment);

    return {
      commitment,
      txHash: tx.hash,
      ...claimInfo
    };
  }

  /**
   * 执行索赔（争议期后）
   * @param {string} commitment - 索赔ID
   */
  async executeClaim(commitment) {
    if (!this.signer) throw new Error('Wallet not connected');

    const tx = await this.contract.executeClaim(commitment);
    await tx.wait();

    return tx.hash;
  }

  /**
   * 争议索赔
   * @param {string} commitment - 索赔ID
   * @param {string} evidence - 证据说明
   */
  async disputeClaim(commitment, evidence) {
    if (!this.signer) throw new Error('Wallet not connected');

    const tx = await this.contract.disputeClaim(commitment, evidence);
    await tx.wait();

    return tx.hash;
  }

  // ==================== 查询功能 ====================

  /**
   * 获取Provider信息
   * @param {string} address - Provider地址
   */
  async getProviderInfo(address) {
    const info = await this.contract.getProviderInfo(address);
    const pending = await this.contract.getProviderPendingCompensations(address);

    return {
      isActive: info.isActive,
      poolBalance: ethers.formatUnits(info.poolBalance, 6),
      totalLocked: ethers.formatUnits(info.totalLocked, 6),
      availableBalance: ethers.formatUnits(
        info.poolBalance > info.totalLocked ?
          info.poolBalance - info.totalLocked : 0n,
        6
      ),
      successfulServices: Number(info.successfulServices),
      failedServices: Number(info.failedServices),
      tier: Number(info.tier),
      registeredAt: new Date(Number(info.registeredAt) * 1000),
      pendingCompensations: {
        count: pending.commitments.length,
        total: ethers.formatUnits(pending.totalAmount, 6),
        commitments: pending.commitments,
        amounts: pending.amounts.map(a => ethers.formatUnits(a, 6))
      }
    };
  }

  /**
   * 获取索赔信息
   * @param {string} commitment - 索赔ID
   */
  async getClaimInfo(commitment) {
    const info = await this.contract.getClaimInfo(commitment);

    const requestedAmount = info.requestedAmount;
    const paidAmount = info.paidAmount;
    const pendingAmount = info.pendingAmount;

    return {
      client: info.client,
      provider: info.provider,
      requestedAmount: ethers.formatUnits(requestedAmount, 6),
      paidAmount: ethers.formatUnits(paidAmount, 6),
      pendingAmount: ethers.formatUnits(pendingAmount, 6),
      initiatedAt: new Date(Number(info.initiatedAt) * 1000),
      disputeDeadline: new Date(Number(info.disputeDeadline) * 1000),
      reason: Number(info.reason),
      status: Number(info.status),
      paymentRatio: requestedAmount > 0n ?
        Number((paidAmount * 100n) / requestedAmount) : 0
    };
  }

  /**
   * 获取全局统计
   */
  async getGlobalStats() {
    const [totalPools, emergency, platform, pending] = await Promise.all([
      this.contract.totalProviderPools(),
      this.contract.emergencyPool(),
      this.contract.platformInsuranceFund(),
      this.contract.totalPendingCompensations()
    ]);

    const total = totalPools + emergency + platform;

    return {
      totalProviderPools: ethers.formatUnits(totalPools, 6),
      emergencyPool: ethers.formatUnits(emergency, 6),
      platformInsuranceFund: ethers.formatUnits(platform, 6),
      totalPendingCompensations: ethers.formatUnits(pending, 6),
      totalValue: ethers.formatUnits(total, 6)
    };
  }

  /**
   * 检查服务接受能力
   * @param {string} provider - Provider地址
   * @param {string} amount - 服务金额
   */
  async canAcceptService(provider, amount) {
    const parsedAmount = ethers.parseUnits(amount.toString(), 6);
    const result = await this.contract.canAcceptService(provider, parsedAmount);

    return {
      canAccept: result.canAccept,
      reason: result.reason
    };
  }

  /**
   * 获取合约常量
   */
  async getConstants() {
    const [minBalance, penaltyRate, maxExposure] = await Promise.all([
      this.contract.MIN_POOL_BALANCE(),
      this.contract.PENALTY_RATE(),
      this.contract.MAX_EXPOSURE_RATIO()
    ]);

    return {
      minPoolBalance: ethers.formatUnits(minBalance, 6),
      penaltyRate: Number(penaltyRate) / 100,
      maxExposureRatio: Number(maxExposure) / 100
    };
  }

  // ==================== 事件监听 ====================

  /**
   * 监听Provider注册事件
   */
  onProviderRegistered(callback) {
    return this.contract.on('ProviderRegistered', (provider, amount) => {
      callback({
        provider,
        amount: ethers.formatUnits(amount, 6)
      });
    });
  }

  /**
   * 监听索赔发起事件
   */
  onClaimInitiated(callback) {
    return this.contract.on('ClaimInitiated', (commitment, client, provider, amount) => {
      callback({
        commitment,
        client,
        provider,
        amount: ethers.formatUnits(amount, 6)
      });
    });
  }

  /**
   * 监听索赔执行事件
   */
  onClaimExecuted(callback) {
    return this.contract.on('ClaimExecuted', (commitment, paidAmount, pendingAmount) => {
      callback({
        commitment,
        paidAmount: ethers.formatUnits(paidAmount, 6),
        pendingAmount: ethers.formatUnits(pendingAmount, 6)
      });
    });
  }

  /**
   * 监听补偿支付事件
   */
  onCompensationPaid(callback) {
    return this.contract.on('CompensationPaid', (commitment, client, amount) => {
      callback({
        commitment,
        client,
        amount: ethers.formatUnits(amount, 6)
      });
    });
  }

  // ==================== 工具函数 ====================

  /**
   * 授权USDC
   */
  async approveUSDC(amount) {
    const allowance = await this.usdcContract.allowance(
      await this.signer.getAddress(),
      CONTRACT_ADDRESS
    );

    if (allowance < amount) {
      const tx = await this.usdcContract.approve(CONTRACT_ADDRESS, amount * 2n);
      await tx.wait();
    }
  }

  /**
   * 获取USDC余额
   */
  async getUSDCBalance(address) {
    const balance = await this.usdcContract.balanceOf(address);
    return ethers.formatUnits(balance, 6);
  }

  /**
   * 生成commitment
   */
  static generateCommitment(prefix = 'claim') {
    return ethers.keccak256(
      ethers.toUtf8Bytes(`${prefix}-${Date.now()}-${Math.random()}`)
    );
  }

  /**
   * 计算争议期
   */
  static getDisputePeriod(amount) {
    const parsedAmount = ethers.parseUnits(amount.toString(), 6);
    if (parsedAmount <= ethers.parseUnits('10', 6)) return 60;      // 1分钟
    if (parsedAmount <= ethers.parseUnits('100', 6)) return 300;    // 5分钟
    if (parsedAmount <= ethers.parseUnits('1000', 6)) return 900;   // 15分钟
    return 1800; // 30分钟
  }

  /**
   * 获取当前账户地址
   */
  async getAddress() {
    if (!this.signer) return null;
    return await this.signer.getAddress();
  }
}

// 导出
export default X402InsuranceSDK;
export { ClaimReason, ClaimStatus, CONTRACT_ADDRESS, USDC_ADDRESS };