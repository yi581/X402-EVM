# 成为 X402 Insurance Provider - 超简单指南

## 🎯 3种方式，选最适合你的

### 方式 1：普通钱包地址（最简单！）⭐

**适合：个人、小团队**

```javascript
// 只需 2 行代码！

// 1. 授权 USDC
await usdc.approve(insuranceV8Address, ethers.parseUnits('100', 6));

// 2. 注册
await insuranceV8.registerOrReactivate(ethers.parseUnits('100', 6));

// 完成！你的钱包地址现在就是 Provider！
```

**优点：**
- ✅ 超级简单
- ✅ 无需部署合约
- ✅ 立即生效

**缺点：**
- ❌ 需要手动处理索赔
- ❌ 无法自动化

---

### 方式 2：使用工厂合约（推荐！）⭐⭐⭐

**适合：想要自动化的项目**

```javascript
// 只需 2 步！

// 1. 授权 USDC
await usdc.approve(factoryAddress, ethers.parseUnits('100', 6));

// 2. 一键创建 Provider 合约
const tx = await factory.createProvider(ethers.parseUnits('100', 6));
const receipt = await tx.wait();

// 从事件获取你的 Provider 合约地址
const event = receipt.logs.find(log => log.eventName === 'ProviderCreated');
const yourProviderContract = event.args.providerContract;

console.log('你的 Provider 合约:', yourProviderContract);
```

**优点：**
- ✅ 一键完成部署+注册
- ✅ 支持自动化索赔处理
- ✅ 可以自定义逻辑

**工厂合约地址：**
```
Base Sepolia: 0xbed30550aB282bED6A6ED57F23E9C99FAd8b7b76
```

---

### 方式 3：使用前端 SDK（最用户友好！）⭐⭐⭐⭐

**适合：前端集成**

```javascript
import X402ProviderSimpleSDK from '@x402/provider-sdk';

// 1. 连接钱包
const sdk = await X402ProviderSimpleSDK.connect();

// 2. 一键成为 Provider（带进度提示）
const provider = await sdk.becomeProvider('100', (step, message) => {
  console.log(`步骤 ${step}/4: ${message}`);
});

console.log('成功！Provider 地址:', provider.address);
```

**React 使用：**

```jsx
import { useX402Provider } from '@x402/provider-sdk';

function BecomeProviderPage() {
  const { connect, becomeProvider, loading, progress, error } = useX402Provider();
  const [amount, setAmount] = useState('100');

  const handleBecomeProvider = async () => {
    await connect();
    const provider = await becomeProvider(amount);
    alert(`成功！Provider: ${provider.address}`);
  };

  return (
    <div>
      <h2>成为 X402 Insurance Provider</h2>

      <input
        type="number"
        value={amount}
        onChange={(e) => setAmount(e.target.value)}
        placeholder="保险金金额 (USDC)"
      />

      <button onClick={handleBecomeProvider} disabled={loading}>
        {loading ? `${progress.message}` : '一键成为 Provider'}
      </button>

      {error && <p className="error">{error}</p>}
    </div>
  );
}
```

---

## 📊 对比表

| 特性 | 方式1：钱包地址 | 方式2：工厂合约 | 方式3：SDK |
|------|----------------|----------------|-----------|
| 简单程度 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| 自动化 | ❌ | ✅ | ✅ |
| Gas费 | 最低 | 中等 | 中等 |
| 适合场景 | 个人测试 | 智能合约项目 | 前端应用 |
| 需要部署 | ❌ | ❌ | ❌ |
| 步骤数 | 2步 | 2步 | 2步 |

---

## 🚀 完整示例

### 示例 1：使用纯 JavaScript

```javascript
const { ethers } = require('ethers');

async function becomeProvider() {
  // 连接钱包
  const provider = new ethers.JsonRpcProvider('https://sepolia.base.org');
  const wallet = new ethers.Wallet(YOUR_PRIVATE_KEY, provider);

  // 合约地址
  const FACTORY = '0x...'; // 工厂合约地址
  const USDC = '0x036CbD53842c5426634e7929541eC2318f3dCF7e';

  // 合约实例
  const usdc = new ethers.Contract(
    USDC,
    ['function approve(address,uint256) returns (bool)'],
    wallet
  );

  const factory = new ethers.Contract(
    FACTORY,
    ['function createProvider(uint256) returns (address)'],
    wallet
  );

  // 1. 授权
  console.log('授权 USDC...');
  const amount = ethers.parseUnits('100', 6);
  await usdc.approve(FACTORY, amount);

  // 2. 创建 Provider
  console.log('创建 Provider...');
  const tx = await factory.createProvider(amount);
  const receipt = await tx.wait();

  console.log('成功！交易哈希:', tx.hash);
}

becomeProvider();
```

### 示例 2：使用 Web3Modal + React

```jsx
import { Web3Provider } from '@ethersproject/providers';
import { useWeb3Modal } from '@web3modal/react';

function ProviderOnboarding() {
  const { open, isConnected, provider } = useWeb3Modal();
  const [status, setStatus] = useState('');

  const handleBecomeProvider = async () => {
    if (!isConnected) {
      await open();
      return;
    }

    const ethersProvider = new Web3Provider(provider);
    const signer = ethersProvider.getSigner();

    // 使用 SDK
    const sdk = new X402ProviderSimpleSDK(signer);

    setStatus('处理中...');

    try {
      const result = await sdk.becomeProvider('100', (step, msg) => {
        setStatus(`步骤 ${step}/4: ${msg}`);
      });

      setStatus(`成功！Provider: ${result.address}`);
    } catch (error) {
      setStatus(`错误: ${error.message}`);
    }
  };

  return (
    <div>
      <button onClick={handleBecomeProvider}>
        {isConnected ? '成为 Provider' : '连接钱包'}
      </button>
      {status && <p>{status}</p>}
    </div>
  );
}
```

---

## 💰 费用估算

| 操作 | Gas 费用（估算） | USDC 要求 |
|------|------------------|-----------|
| 方式1：直接注册 | ~50,000 gas | 最低 10 USDC |
| 方式2：工厂合约 | ~200,000 gas | 最低 10 USDC |
| 方式3：SDK（工厂） | ~200,000 gas | 最低 10 USDC |

**Base Sepolia 测试网 Gas 费几乎为 0**

---

## 🎓 FAQ

### Q: 我需要多少 USDC？
**A:** 最低 10 USDC，推荐 100 USDC 起步。

### Q: 可以随时退出吗？
**A:** 可以！调用 `withdraw()` 或 `withdrawAllAndDeactivate()`。

### Q: 钱包地址和合约地址有什么区别？
**A:**
- **钱包地址（EOA）**：简单，但需要手动操作
- **合约地址**：可以自动化处理索赔，更灵活

### Q: 我应该选哪种方式？
**A:**
- 只是测试 → **方式1**
- 需要自动化 → **方式2**
- 做前端应用 → **方式3**

### Q: 工厂合约安全吗？
**A:** 是的！
- ✅ 开源代码
- ✅ 你拥有创建的 Provider 合约完全控制权
- ✅ 可以随时提取资金

---

## 📞 需要帮助？

- 文档：[完整文档](/docs)
- 示例代码：[examples/](/examples)
- Discord：[加入社区](#)
- GitHub：[提交 Issue](#)

---

## 🎉 下一步

成为 Provider 后，你可以：

1. **查看状态**
   ```javascript
   const info = await insurance.getProviderInfo(yourAddress);
   console.log('保险池余额:', ethers.formatUnits(info.poolBalance, 6));
   ```

2. **处理索赔**
   ```javascript
   // 如果是合约 Provider
   await providerContract.disputeClaim(commitment, "服务已交付");
   ```

3. **追加保险金**
   ```javascript
   await providerContract.depositInsurance(ethers.parseUnits('50', 6));
   ```

4. **提取资金**
   ```javascript
   await providerContract.withdrawInsurance(ethers.parseUnits('20', 6));
   ```

---

## 🔗 合约地址

| 合约 | Base Sepolia 地址 |
|------|-------------------|
| Insurance V8 | `0x72486eF40BB3729298369d608de85c612adb223e` |
| USDC | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` |
| ProviderFactory | `0xbed30550aB282bED6A6ED57F23E9C99FAd8b7b76` |

---

**准备好了吗？选择你喜欢的方式，立即成为 X402 Insurance Provider！** 🚀
