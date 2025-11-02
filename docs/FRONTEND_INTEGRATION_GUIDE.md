# X402 Insurance V8 前端集成文档

## 目录
1. [快速开始](#快速开始)
2. [环境配置](#环境配置)
3. [智能合约接口](#智能合约接口)
4. [API接口文档](#api接口文档)
5. [前端功能模块](#前端功能模块)
6. [代码示例](#代码示例)
7. [UI/UX建议](#uiux建议)

---

## 快速开始

### 安装依赖
```bash
npm install ethers@6 axios
# 或
yarn add ethers@6 axios
```

### 基础配置
```javascript
// config/contracts.js
export const CONTRACTS = {
  BASE_SEPOLIA: {
    INSURANCE_V8: '0x72486eF40BB3729298369d608de85c612adb223e',
    USDC: '0x036CbD53842c5426634e7929541eC2318f3dCF7e'
  }
};

export const RPC_URLS = {
  BASE_SEPOLIA: 'https://sepolia.base.org'
};
```

---

## 环境配置

### 网络信息
| 参数 | 值 |
|------|-----|
| 网络名称 | Base Sepolia |
| Chain ID | 84532 |
| RPC URL | https://sepolia.base.org |
| 区块浏览器 | https://sepolia.basescan.org |
| USDC合约 | 0x036CbD53842c5426634e7929541eC2318f3dCF7e |
| Insurance V8 | 0x72486eF40BB3729298369d608de85c612adb223e |

---

## 智能合约接口

### 1. Provider管理

#### 注册/重新激活Provider
```javascript
// ABI
const PROVIDER_ABI = [
  "function registerOrReactivate(uint256 amount)",
  "function depositAdditional(uint256 amount)",
  "function withdraw(uint256 amount)",
  "function withdrawAllAndDeactivate()"
];

// 使用示例
async function registerProvider(amount) {
  const insurance = new ethers.Contract(INSURANCE_ADDRESS, PROVIDER_ABI, signer);

  // 1. 先授权USDC
  const usdc = new ethers.Contract(USDC_ADDRESS, USDC_ABI, signer);
  await usdc.approve(INSURANCE_ADDRESS, amount);

  // 2. 注册Provider
  const tx = await insurance.registerOrReactivate(amount);
  await tx.wait();

  return tx.hash;
}
```

#### 查询Provider信息
```javascript
// ABI
const QUERY_ABI = [
  "function getProviderInfo(address provider) view returns (bool isActive, uint256 poolBalance, uint256 totalLocked, uint256 successfulServices, uint256 failedServices, uint8 tier, uint256 registeredAt)"
];

// 返回数据结构
interface ProviderInfo {
  isActive: boolean;           // 是否激活
  poolBalance: string;          // 池余额 (USDC, 6位小数)
  totalLocked: string;          // 锁定金额
  successfulServices: number;   // 成功服务次数
  failedServices: number;       // 失败服务次数
  tier: number;                 // 等级 (1-3)
  registeredAt: number;         // 注册时间戳
}
```

### 2. 索赔管理

#### 发起索赔
```javascript
// ABI
const CLAIM_ABI = [
  "function initiateClaim(bytes32 commitment, address provider, uint256 amount, uint8 reason)",
  "function executeClaim(bytes32 commitment)",
  "function disputeClaim(bytes32 commitment, string memory evidence)"
];

// 索赔原因枚举
enum ClaimReason {
  NOT_DELIVERED = 0,      // 未交付
  SERVICE_TIMEOUT = 1,    // 服务超时
  PARTIAL_DELIVERY = 2    // 部分交付
}

// 发起索赔示例
async function initiateClaim(provider, amount, reason) {
  const commitment = ethers.keccak256(ethers.toUtf8Bytes(`claim-${Date.now()}`));

  const insurance = new ethers.Contract(INSURANCE_ADDRESS, CLAIM_ABI, signer);
  const tx = await insurance.initiateClaim(commitment, provider, amount, reason);
  await tx.wait();

  return { commitment, txHash: tx.hash };
}
```

#### 查询索赔信息
```javascript
// ABI
const CLAIM_QUERY_ABI = [
  "function getClaimInfo(bytes32 commitment) view returns (address client, address provider, uint256 requestedAmount, uint256 paidAmount, uint256 pendingAmount, uint256 initiatedAt, uint256 disputeDeadline, uint8 reason, uint8 status)"
];

// 索赔状态枚举
enum ClaimStatus {
  INITIATED = 0,    // 已发起
  DISPUTED = 1,     // 有争议
  EXECUTED = 2,     // 已执行
  REJECTED = 3,     // 已拒绝
  PARTIAL = 4       // 部分支付
}

// 返回数据结构
interface ClaimInfo {
  client: string;              // 客户地址
  provider: string;            // Provider地址
  requestedAmount: string;     // 请求金额
  paidAmount: string;          // 已支付金额
  pendingAmount: string;       // 待补偿金额
  initiatedAt: number;         // 发起时间戳
  disputeDeadline: number;     // 争议截止时间
  reason: ClaimReason;         // 索赔原因
  status: ClaimStatus;         // 索赔状态
}
```

### 3. 补偿查询

#### 获取Provider待补偿列表
```javascript
// ABI
const COMPENSATION_ABI = [
  "function getProviderPendingCompensations(address provider) view returns (bytes32[] memory commitments, uint256[] memory amounts, uint256 totalAmount)"
];

// 返回数据结构
interface PendingCompensations {
  commitments: string[];       // 待补偿的索赔ID列表
  amounts: string[];           // 各索赔待补偿金额
  totalAmount: string;         // 总待补偿金额
}
```

### 4. 全局状态查询

```javascript
// ABI
const GLOBAL_ABI = [
  "function totalProviderPools() view returns (uint256)",
  "function emergencyPool() view returns (uint256)",
  "function platformInsuranceFund() view returns (uint256)",
  "function totalPendingCompensations() view returns (uint256)",
  "function canAcceptService(address provider, uint256 serviceAmount) view returns (bool canAccept, string memory reason)"
];

// 全局统计数据
interface GlobalStats {
  totalProviderPools: string;      // Provider池总和
  emergencyPool: string;            // 应急池
  platformInsuranceFund: string;    // 平台基金
  totalPendingCompensations: string; // 全局待补偿总额
}
```

---

## API接口文档

### Provider Registry API

基础URL: `http://localhost:3005` (开发环境)

#### 1. 获取所有Provider
```http
GET /api/providers

Response:
{
  "providers": [
    {
      "address": "0x...",
      "isActive": true,
      "poolBalance": "100.0",
      "totalLocked": "20.0",
      "availableBalance": "80.0",
      "successfulServices": 10,
      "failedServices": 1,
      "tier": 2,
      "registeredAt": 1762067070,
      "riskScore": 85
    }
  ],
  "total": 1
}
```

#### 2. 获取单个Provider详情
```http
GET /api/providers/:address

Response:
{
  "provider": {
    "address": "0x...",
    "isActive": true,
    "poolBalance": "100.0",
    "totalLocked": "20.0",
    "claims": [...],
    "pendingCompensations": {...}
  }
}
```

#### 3. 获取索赔历史
```http
GET /api/claims?provider=0x...&client=0x...&status=executed

Response:
{
  "claims": [
    {
      "commitment": "0x...",
      "client": "0x...",
      "provider": "0x...",
      "requestedAmount": "10.0",
      "paidAmount": "10.0",
      "pendingAmount": "0.0",
      "status": "executed",
      "timestamp": 1762067070
    }
  ],
  "pagination": {
    "total": 100,
    "page": 1,
    "limit": 20
  }
}
```

---

## 前端功能模块

### 1. Provider仪表板
```javascript
// components/ProviderDashboard.jsx
import { useState, useEffect } from 'react';
import { ethers } from 'ethers';

function ProviderDashboard({ provider }) {
  const [info, setInfo] = useState(null);
  const [pendingCompensations, setPendingCompensations] = useState(null);

  useEffect(() => {
    loadProviderInfo();
  }, [provider]);

  const loadProviderInfo = async () => {
    const contract = new ethers.Contract(INSURANCE_ADDRESS, ABI, provider);
    const info = await contract.getProviderInfo(provider.address);
    const compensations = await contract.getProviderPendingCompensations(provider.address);

    setInfo({
      isActive: info.isActive,
      poolBalance: ethers.formatUnits(info.poolBalance, 6),
      totalLocked: ethers.formatUnits(info.totalLocked, 6),
      availableBalance: ethers.formatUnits(info.poolBalance - info.totalLocked, 6),
      successfulServices: Number(info.successfulServices),
      failedServices: Number(info.failedServices),
      tier: Number(info.tier)
    });

    setPendingCompensations({
      total: ethers.formatUnits(compensations.totalAmount, 6),
      count: compensations.commitments.length
    });
  };

  return (
    <div className="dashboard">
      <h2>Provider Dashboard</h2>

      {/* 状态卡片 */}
      <div className="status-cards">
        <Card title="池余额" value={`${info?.poolBalance} USDC`} />
        <Card title="可用余额" value={`${info?.availableBalance} USDC`} />
        <Card title="锁定金额" value={`${info?.totalLocked} USDC`} />
        <Card title="待补偿" value={`${pendingCompensations?.total} USDC`} />
      </div>

      {/* 操作按钮 */}
      <div className="actions">
        <button onClick={handleDeposit}>追加保险金</button>
        <button onClick={handleWithdraw}>提取资金</button>
        <button onClick={handleViewClaims}>查看索赔</button>
      </div>
    </div>
  );
}
```

### 2. 客户索赔界面
```javascript
// components/ClaimInterface.jsx
function ClaimInterface({ signer }) {
  const [providers, setProviders] = useState([]);
  const [selectedProvider, setSelectedProvider] = useState('');
  const [amount, setAmount] = useState('');
  const [reason, setReason] = useState(0);

  const handleSubmitClaim = async () => {
    try {
      // 生成commitment
      const commitment = ethers.keccak256(
        ethers.toUtf8Bytes(`claim-${Date.now()}-${Math.random()}`)
      );

      // 发起索赔
      const contract = new ethers.Contract(INSURANCE_ADDRESS, CLAIM_ABI, signer);
      const tx = await contract.initiateClaim(
        commitment,
        selectedProvider,
        ethers.parseUnits(amount, 6),
        reason
      );

      await tx.wait();

      // 查询索赔详情
      const claimInfo = await contract.getClaimInfo(commitment);

      // 显示结果
      if (claimInfo.paidAmount < claimInfo.requestedAmount) {
        alert(`部分支付: ${ethers.formatUnits(claimInfo.paidAmount, 6)} USDC
               待补偿: ${ethers.formatUnits(claimInfo.pendingAmount, 6)} USDC`);
      } else {
        alert(`全额支付: ${ethers.formatUnits(claimInfo.paidAmount, 6)} USDC`);
      }
    } catch (error) {
      console.error('索赔失败:', error);
    }
  };

  return (
    <div className="claim-form">
      <h3>发起索赔</h3>

      <select value={selectedProvider} onChange={e => setSelectedProvider(e.target.value)}>
        <option value="">选择Provider</option>
        {providers.map(p => (
          <option key={p} value={p}>{p}</option>
        ))}
      </select>

      <input
        type="number"
        placeholder="索赔金额 (USDC)"
        value={amount}
        onChange={e => setAmount(e.target.value)}
      />

      <select value={reason} onChange={e => setReason(Number(e.target.value))}>
        <option value={0}>未交付</option>
        <option value={1}>服务超时</option>
        <option value={2}>部分交付</option>
      </select>

      <button onClick={handleSubmitClaim}>提交索赔</button>
    </div>
  );
}
```

### 3. 实时统计展示
```javascript
// components/GlobalStats.jsx
function GlobalStats() {
  const [stats, setStats] = useState({});

  useEffect(() => {
    const interval = setInterval(loadStats, 5000);
    loadStats();
    return () => clearInterval(interval);
  }, []);

  const loadStats = async () => {
    const provider = new ethers.JsonRpcProvider(RPC_URL);
    const contract = new ethers.Contract(INSURANCE_ADDRESS, GLOBAL_ABI, provider);

    const [totalPools, emergencyPool, platformFund, totalPending] = await Promise.all([
      contract.totalProviderPools(),
      contract.emergencyPool(),
      contract.platformInsuranceFund(),
      contract.totalPendingCompensations()
    ]);

    setStats({
      totalPools: ethers.formatUnits(totalPools, 6),
      emergencyPool: ethers.formatUnits(emergencyPool, 6),
      platformFund: ethers.formatUnits(platformFund, 6),
      totalPending: ethers.formatUnits(totalPending, 6),
      totalValue: ethers.formatUnits(totalPools + emergencyPool + platformFund, 6)
    });
  };

  return (
    <div className="global-stats">
      <h3>全网统计</h3>
      <div className="stat-grid">
        <StatCard
          title="总锁仓价值"
          value={`$${stats.totalValue}`}
          trend="+12.5%"
        />
        <StatCard
          title="Provider池"
          value={`$${stats.totalPools}`}
        />
        <StatCard
          title="待补偿总额"
          value={`$${stats.totalPending}`}
          status="warning"
        />
      </div>
    </div>
  );
}
```

---

## 代码示例

### 完整的React Hook示例
```javascript
// hooks/useInsurance.js
import { useState, useEffect, useCallback } from 'react';
import { ethers } from 'ethers';

export function useInsurance() {
  const [provider, setProvider] = useState(null);
  const [signer, setSigner] = useState(null);
  const [contract, setContract] = useState(null);

  // 初始化连接
  const connect = useCallback(async () => {
    if (typeof window.ethereum !== 'undefined') {
      const provider = new ethers.BrowserProvider(window.ethereum);
      const signer = await provider.getSigner();
      const contract = new ethers.Contract(INSURANCE_ADDRESS, FULL_ABI, signer);

      setProvider(provider);
      setSigner(signer);
      setContract(contract);

      return true;
    }
    return false;
  }, []);

  // Provider注册
  const registerProvider = useCallback(async (amount) => {
    if (!contract) return;

    // 授权USDC
    const usdc = new ethers.Contract(USDC_ADDRESS, USDC_ABI, signer);
    const parsedAmount = ethers.parseUnits(amount.toString(), 6);

    const approveTx = await usdc.approve(INSURANCE_ADDRESS, parsedAmount);
    await approveTx.wait();

    // 注册
    const registerTx = await contract.registerOrReactivate(parsedAmount);
    await registerTx.wait();

    return registerTx.hash;
  }, [contract, signer]);

  // 发起索赔
  const initiateClaim = useCallback(async (providerAddress, amount, reason = 0) => {
    if (!contract) return;

    const commitment = ethers.keccak256(
      ethers.toUtf8Bytes(`claim-${Date.now()}-${Math.random()}`)
    );
    const parsedAmount = ethers.parseUnits(amount.toString(), 6);

    const tx = await contract.initiateClaim(
      commitment,
      providerAddress,
      parsedAmount,
      reason
    );
    await tx.wait();

    // 获取索赔详情
    const claimInfo = await contract.getClaimInfo(commitment);

    return {
      commitment,
      txHash: tx.hash,
      paidAmount: ethers.formatUnits(claimInfo.paidAmount, 6),
      pendingAmount: ethers.formatUnits(claimInfo.pendingAmount, 6),
      status: Number(claimInfo.status)
    };
  }, [contract]);

  // 查询Provider信息
  const getProviderInfo = useCallback(async (address) => {
    if (!contract) return null;

    const info = await contract.getProviderInfo(address);
    const pending = await contract.getProviderPendingCompensations(address);

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
      pendingCompensations: {
        count: pending.commitments.length,
        total: ethers.formatUnits(pending.totalAmount, 6)
      }
    };
  }, [contract]);

  return {
    connect,
    registerProvider,
    initiateClaim,
    getProviderInfo,
    isConnected: !!contract
  };
}
```

### Web3Modal集成
```javascript
// utils/web3.js
import { createWeb3Modal, defaultConfig } from '@web3modal/ethers/react';

const projectId = 'YOUR_WALLETCONNECT_PROJECT_ID';

const baseSepolia = {
  chainId: 84532,
  name: 'Base Sepolia',
  currency: 'ETH',
  explorerUrl: 'https://sepolia.basescan.org',
  rpcUrl: 'https://sepolia.base.org'
};

const metadata = {
  name: 'X402 Insurance',
  description: 'Zero-cost insurance for X402 payments',
  url: 'https://x402insurance.com',
  icons: ['https://x402insurance.com/icon.png']
};

createWeb3Modal({
  ethersConfig: defaultConfig({ metadata }),
  chains: [baseSepolia],
  projectId
});
```

---

## UI/UX建议

### 1. 关键信息展示

#### Provider看板
- **醒目展示**：可用余额、待补偿金额
- **风险提示**：当可用余额低于10%时显示警告
- **实时更新**：每5秒刷新一次数据

#### 客户端
- **Provider选择**：显示每个Provider的可用容量和评分
- **预估结果**：在提交前显示预计支付比例
- **状态追踪**：实时显示索赔处理进度

### 2. 交互流程

#### Provider注册流程
1. 连接钱包
2. 输入保险金额（最低10 USDC）
3. 授权USDC
4. 确认注册
5. 显示注册成功和Provider信息

#### 索赔流程
1. 选择Provider
2. 输入索赔金额和原因
3. 预览支付情况（全额/部分）
4. 确认提交
5. 显示结果（已支付/待补偿）
6. 提供争议期倒计时

### 3. 错误处理
```javascript
// utils/errors.js
export function handleContractError(error) {
  if (error.reason === "Insufficient funds across all pools") {
    return "Provider资金不足，索赔将被部分支付";
  }
  if (error.reason === "Provider not active") {
    return "Provider未激活";
  }
  if (error.reason === "Below minimum balance") {
    return "余额低于最低要求（10 USDC）";
  }
  // ... 其他错误处理
  return "交易失败，请重试";
}
```

---

## 测试网络配置

### MetaMask添加Base Sepolia
```javascript
async function addBaseSepoliaToMetaMask() {
  try {
    await window.ethereum.request({
      method: 'wallet_addEthereumChain',
      params: [{
        chainId: '0x14a34', // 84532 in hex
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
  } catch (error) {
    console.error('Failed to add network:', error);
  }
}
```

---

## 部署信息

### 已部署合约
- **X402InsuranceV8**: `0x72486eF40BB3729298369d608de85c612adb223e`
- **部署时间**: 2025-11-02
- **网络**: Base Sepolia
- **验证状态**: 已验证

### 获取测试USDC
1. 访问 Base Sepolia Faucet
2. 或联系开发团队获取测试代币

---

## 联系支持

- GitHub: https://github.com/yourusername/x402-insurance
- Discord: https://discord.gg/x402insurance
- Email: support@x402insurance.com