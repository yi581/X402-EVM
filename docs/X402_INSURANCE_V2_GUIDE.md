# X402 Insurance V2 - 零保险费模式

## 🎯 核心理念

**客户不需要支付额外保险费，由服务商 Bond 提供完全保护。**

## 📊 经济模型对比

### V1 模型（客户付保险费）

```
客户支付：
  - 服务费：$0.10 → 服务商（x402）
  - 保险费：$0.001 → Insurance 合约

成功：服务商获得保险费奖励 90%
失败：客户全额退款，服务商 bond 被扣除
```

### V2 模型（零保险费）⭐ 推荐

```
客户支付：
  - 服务费：$0.10 → 服务商（x402）
  - 保险费：$0 （无！）

服务商 Bond：
  - 初始：$1000
  - 接单时：临时锁定 $0.102（支付额 + 2%罚金）
  - 剩余可用：$897.98

成功：解锁 $0.102，服务商赚 $0.10 ✅
失败：
  - 赔付客户：$0.10
  - 平台罚金：$0.002（2%）
  - 服务商净收入：$0.10 - $0.102 = -$0.002 ⚠️
```

## 🔄 完整流程

### 1. 准备阶段

```solidity
// 服务商存入保证金
insurance.depositBond(1000 * 10^6); // 1000 USDC

// 平台设置最低保证金（可选）
insurance.setMinProviderBond(provider, 500 * 10^6); // 500 USDC

// 状态：
providerBond[provider] = 1000 USDC
lockedBond[provider] = 0
minProviderBond[provider] = 500 USDC
```

### 2. 客户请求服务

```typescript
// 客户发起 x402 请求
const response = await client.get('/api/service');

// 背后发生的事情：
// 1. x402 立即结算：0.10 USDC → 服务商 ✅
// 2. Insurance 合约自动锁定 bond：
//    - 锁定金额：0.10 + 0.002 = 0.102 USDC
//    - 用于保护客户和支付罚金
```

```solidity
// 客户调用（通常由前端自动完成）
insurance.purchaseInsurance(
    requestCommitment,  // 请求标识
    provider,           // 服务商地址
    0.10e6,            // 支付金额（x402已结算）
    5                  // 5分钟超时
);

// 效果：
providerBond[provider] = 1000  // 不变
lockedBond[provider] = 0.102   // 锁定
availableBond = 999.898        // 剩余可用
```

### 3a. 成功场景 - 服务商确认

```typescript
// 服务商提供服务成功后签名确认
const signature = await signServiceConfirmation(
  providerWallet,
  requestCommitment
);

await insurance.confirmService(requestCommitment, signature);
```

```solidity
// 合约内部：
lockedBond[provider] -= 0.102  // 解锁
status = ClaimStatus.Confirmed

// 结果：
// - 客户：花费 $0.10，获得服务 ✅
// - 服务商：赚 $0.10，bond 无损 ✅
// - 平台：无收入
```

### 3b. 失败场景 - 客户申领保险

```typescript
// 等待超时（5分钟）
await sleep(5 * 60 * 1000);

// 客户申领保险
await insurance.claimInsurance(requestCommitment);
```

```solidity
// 合约内部：
// 1. 解锁并扣除 bond
lockedBond[provider] -= 0.102
providerBond[provider] -= 0.102  // 永久扣除！

// 2. 分配资金
usdc.transfer(client, 0.10)       // 赔付客户
usdc.transfer(platform, 0.002)    // 罚金给平台

status = ClaimStatus.Claimed

// 结果：
// - 客户：退款 $0.10，零损失 ✅
// - 服务商：x402收入 $0.10 - bond损失 $0.102 = -$0.002 ⚠️
// - 平台：罚金收入 $0.002 💰
```

## 💡 Bond 健康管理

### 健康状态检查

```solidity
function isProviderHealthy(address provider) public view returns (bool) {
    if (isLiquidated[provider]) return false;

    uint256 totalBond = providerBond[provider];
    uint256 locked = lockedBond[provider];
    uint256 available = totalBond - locked;
    uint256 minBond = minProviderBond[provider];

    return available >= minBond;
}
```

### 状态转换

```
┌─────────────────────────────────────────────┐
│           健康状态（Healthy）                │
│  - available bond >= min bond              │
│  - 可以接受新订单                          │
│  - 正常运营                                │
└─────────────────────────────────────────────┘
                    ↓
         （失败订单过多，bond耗尽）
                    ↓
┌─────────────────────────────────────────────┐
│          不健康状态（Unhealthy）             │
│  - available bond < min bond               │
│  - 不能接受新订单 ⚠️                       │
│  - 需要充值 bond                           │
└─────────────────────────────────────────────┘
                    ↓
            （充值 bond）
                    ↓
         恢复健康状态 ✅

                    或
                    ↓
          （平台清算）
                    ↓
┌─────────────────────────────────────────────┐
│            清算状态（Liquidated）            │
│  - 服务商被清算                            │
│  - 剩余 bond 归平台                        │
│  - 永久不可用 ❌                           │
└─────────────────────────────────────────────┘
```

## 🔧 代码集成

### 服务商集成

```typescript
import { ethers } from 'ethers';
import X402InsuranceV2ABI from './abi/X402InsuranceV2.json';

// 1. 存入保证金
const insurance = new ethers.Contract(
  INSURANCE_V2_ADDRESS,
  X402InsuranceV2ABI,
  providerWallet
);

const bondAmount = ethers.parseUnits('1000', 6); // 1000 USDC
await usdc.approve(INSURANCE_V2_ADDRESS, bondAmount);
await insurance.depositBond(bondAmount);

// 2. 定期检查健康状态
setInterval(async () => {
  const stats = await insurance.getProviderStats(providerAddress);

  console.log(`Total Bond: ${ethers.formatUnits(stats.totalBond, 6)} USDC`);
  console.log(`Locked: ${ethers.formatUnits(stats.lockedAmount, 6)} USDC`);
  console.log(`Available: ${ethers.formatUnits(stats.availableBond, 6)} USDC`);
  console.log(`Min Required: ${ethers.formatUnits(stats.minBond, 6)} USDC`);
  console.log(`Is Healthy: ${stats.isHealthy}`);

  if (!stats.isHealthy) {
    console.warn('⚠️ Bond不健康！需要充值！');
    // 发送告警...
  }
}, 60000); // 每分钟检查

// 3. 服务成功后确认
app.get('/api/service',
  paymentMiddleware(...),
  async (req, res) => {
    try {
      const result = await processService(req);

      // 成功！确认服务
      const requestCommitment = calculateCommitment(req);
      const signature = await signServiceConfirmation(
        providerWallet,
        requestCommitment
      );

      await insurance.confirmService(requestCommitment, signature);

      res.json({ success: true, data: result });
    } catch (error) {
      // 失败，客户可申领保险
      res.status(500).json({
        error: error.message,
        canClaimInsurance: true
      });
    }
  }
);
```

### 客户端集成

```typescript
import { ethers } from 'ethers';
import X402InsuranceV2ABI from './abi/X402InsuranceV2.json';

// 1. 检查服务商健康状态
const insurance = new ethers.Contract(
  INSURANCE_V2_ADDRESS,
  X402InsuranceV2ABI,
  clientWallet
);

const stats = await insurance.getProviderStats(providerAddress);

if (!stats.isHealthy) {
  console.warn('⚠️ 服务商 bond 不健康，建议选择其他服务商');
}

// 2. 发起 x402 请求（正常流程）
const response = await client.get('/api/service');

// 3. 购买保险（客户无需付费！）
const requestCommitment = calculateCommitment(request);

await insurance.purchaseInsurance(
  requestCommitment,
  providerAddress,
  ethers.parseUnits('0.10', 6),  // 支付金额
  5  // 5分钟超时
);

// 注意：客户不需要 approve USDC，因为不需要付保险费！

// 4. 如果服务失败，等待超时后申领
if (response.status !== 200) {
  await sleep(5 * 60 * 1000); // 等待5分钟

  const canClaim = await insurance.canClaimInsurance(requestCommitment);

  if (canClaim) {
    const tx = await insurance.claimInsurance(requestCommitment);
    await tx.wait();

    console.log('✅ 保险赔付成功，已全额退款！');
  }
}
```

## 📈 经济分析

### 服务商视角

```
假设：
- 月交易量：1000笔
- 单价：$0.10/笔
- 成功率：98%
- 失败率：2%

收入计算：
- 成功交易：980笔 × $0.10 = $98
- 失败交易 x402收入：20笔 × $0.10 = $2
- 失败交易 bond损失：20笔 × $0.102 = -$2.04
- 月净收入：$98 + $2 - $2.04 = $97.96

平台罚金：
- 失败交易罚金：20笔 × $0.002 = $0.04

结论：
- 服务商因失败订单略微亏损（$0.04）
- 强烈激励提供优质服务！
- 成功率越高，收入越接近 $100
```

### 客户视角

```
单次交易：
- 支付：$0.10（只付服务费）✅
- 保险费：$0（无！）✅
- 服务成功：获得服务，花费 $0.10
- 服务失败：全额退款，花费 $0

风险：零！✅
额外成本：零！✅
```

### 平台视角

```
收入来源：
- 仅从失败交易收取2%罚金
- 月收入 = 失败交易数 × 平均订单额 × 2%
- 例如：20笔 × $0.10 × 2% = $0.04/月

特点：
- 不影响客户体验（客户无需付费）
- 激励服务商提供优质服务
- 从失败中获利，形成"惩罚性"商业模式
```

## 🚨 重要特性

### 1. Bond 锁定机制

```
每笔订单锁定金额 = 服务费 × 1.02

例如：
服务费 $0.10
锁定金额 $0.102（包含2%罚金预留）

目的：
- 确保有足够资金赔付客户
- 确保有足够资金支付罚金
- 防止服务商恶意接单
```

### 2. 健康阈值

```solidity
// 查询保护成本
(uint256 totalLock, uint256 penalty) =
    insurance.getProtectionCost(paymentAmount);

// 检查服务商是否能接单
require(
    availableBond >= minBond,
    "Provider unhealthy"
);

// 建议：
// - minBond设为预期月交易量的20%
// - 例如：月1000笔×$0.10 = $100，minBond = $20
```

### 3. 清算机制

```solidity
// 平台管理员可清算服务商
insurance.liquidateProvider(badProvider);

// 条件：
// - 只有在无待处理订单时（lockedBond == 0）
// - 剩余 bond 归平台

// 用途：
// - 清理不活跃服务商
// - 处罚长期违规服务商
// - 回收闲置资金
```

## ⚖️ V1 vs V2 对比

| 特性 | V1（收保险费） | V2（零保险费）⭐ |
|------|---------------|----------------|
| 客户支付 | 服务费 + 1%保险费 | 只付服务费 ✅ |
| 客户体验 | 需要额外USDC | 无额外成本 ✅ |
| 服务商激励 | 成功赚奖励 | 失败有罚金 ⚠️ |
| 平台收入 | 10%保险费 | 2%罚金（仅失败） |
| Bond 管理 | 简单 | 需要监控健康度 |
| 适用场景 | 高价值服务 | 所有场景 ✅ |

## 🎯 最佳实践

### 服务商

1. **充足的 Bond**
   - 建议至少为月交易量的20-30%
   - 留有buffer应对波动

2. **实时监控**
   - 监控 `lockedBond` 占比
   - `lockedBond / totalBond > 70%` 时考虑补充

3. **质量优先**
   - 每次失败损失 > 服务费收入
   - 强烈激励提供优质服务

### 客户

1. **选择健康服务商**
   - 检查 `isProviderHealthy()`
   - 避免使用不健康的服务商

2. **保留凭证**
   - 保存 `requestCommitment`
   - 失败时用于申领保险

3. **及时申领**
   - 超时后尽快申领
   - 避免服务商 bond 被其他订单耗尽

### 平台

1. **合理设置阈值**
   - `minBond` 根据服务商历史表现调整
   - `platformPenaltyRate` 平衡惩罚与激励

2. **定期清理**
   - 清算长期不活跃服务商
   - 回收闲置资金

3. **数据分析**
   - 跟踪服务商成功率
   - 优化 bond 要求

## 📦 部署脚本

```solidity
// script/DeployInsuranceV2.s.sol
forge script script/DeployInsuranceV2.s.sol:DeployInsuranceV2 \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify \
  -vvvv
```

### 环境变量

```bash
# .env
USDC_ADDRESS=0x036CbD53842c5426634e7929541eC2318f3dCF7e  # Base Sepolia
PLATFORM_TREASURY=0x...
PLATFORM_PENALTY_RATE=200  # 2% (basis points)
DEFAULT_TIMEOUT=5          # 5 minutes
```

## 🔐 安全考虑

1. **Bond 充足性**
   - 平台需监控服务商 bond 健康度
   - 设置合理的最低 bond 要求

2. **清算时机**
   - 只有在无待处理订单时清算
   - 避免影响正在进行的交易

3. **签名验证**
   - 使用 EIP-712 标准签名
   - 防止服务商伪造确认

4. **Gas 优化**
   - Bond 锁定/解锁操作高效
   - 批量操作支持（如需要）

## 🎉 总结

X402 Insurance V2 实现了：

✅ **客户零成本保护** - 无需额外付费
✅ **x402 完全兼容** - 即时结算不受影响
✅ **强激励机制** - 服务商自动优化服务质量
✅ **惩罚性收入** - 平台从失败中获利
✅ **可持续运营** - Bond 机制确保系统健康

这是最优雅的 x402 + Insurance 混合模型！🚀
