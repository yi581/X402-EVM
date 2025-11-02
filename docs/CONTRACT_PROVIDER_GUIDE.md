# 合约Provider集成指南

## 概述

当Provider是智能合约而不是普通钱包地址时，需要特殊的实现方式。本指南提供了完整的解决方案。

## 为什么需要合约Provider？

1. **自动化操作** - 无需人工干预，自动处理索赔和补偿
2. **批量管理** - 一个合约可以管理多个服务
3. **复杂逻辑** - 实现条件判断、自动验证等高级功能
4. **资金池管理** - 更灵活的资金管理策略

## 核心问题与解决方案

### 问题1: 合约无法直接调用需要msg.sender的函数
**解决方案**: 合约实现特定接口，通过合约调用的方式注册

### 问题2: USDC授权问题
**解决方案**: 合约内部管理USDC授权逻辑

### 问题3: 自动化处理索赔
**解决方案**: 实现回调接口，接收索赔通知并自动处理

## 实现方案

### 方案1: 简单Provider合约

```solidity
// SimpleProviderContract.sol
contract SimpleProviderContract {
    address constant INSURANCE_V8 = 0x72486eF40BB3729298369d608de85c612adb223e;
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    address public owner;

    constructor() {
        owner = msg.sender;
    }

    // 注册为Provider
    function registerAsProvider(uint256 amount) external {
        require(msg.sender == owner, "Only owner");

        // 授权USDC
        IERC20(USDC).approve(INSURANCE_V8, amount);

        // 调用注册
        IInsurance(INSURANCE_V8).registerOrReactivate(amount);
    }

    // 处理索赔争议
    function handleDispute(bytes32 commitment, string memory evidence) external {
        require(msg.sender == owner, "Only owner");
        IInsurance(INSURANCE_V8).disputeClaim(commitment, evidence);
    }
}
```

### 方案2: 自动化Provider合约

```solidity
// AutomatedProviderContract.sol
contract AutomatedProviderContract {
    // ... 常量定义 ...

    // 自动补充阈值
    uint256 public autoRefillThreshold = 50 * 10**6; // 50 USDC
    uint256 public autoRefillAmount = 100 * 10**6;   // 100 USDC

    // 自动检查并补充保险金
    function checkAndRefill() public {
        (bool isActive, uint256 poolBalance,,,,,) =
            IInsurance(INSURANCE_V8).getProviderInfo(address(this));

        if (isActive && poolBalance < autoRefillThreshold) {
            // 自动补充
            IERC20(USDC).approve(INSURANCE_V8, autoRefillAmount);
            IInsurance(INSURANCE_V8).depositAdditional(autoRefillAmount);
        }
    }

    // 接收索赔通知（需要V8支持）
    function onClaimNotification(
        bytes32 commitment,
        address client,
        uint256 amount,
        uint8 reason
    ) external returns (bool) {
        require(msg.sender == INSURANCE_V8, "Only insurance");

        // 自动验证逻辑
        if (amount <= 10 * 10**6) { // 小额自动接受
            return true;
        }

        // 大额需要验证
        return validateService(commitment, client);
    }
}
```

## 部署步骤

### 1. 部署Provider合约

```javascript
// deploy-provider-contract.js
const { ethers } = require('ethers');

async function deployProviderContract() {
    const provider = new ethers.JsonRpcProvider('https://sepolia.base.org');
    const deployer = new ethers.Wallet(PRIVATE_KEY, provider);

    // 部署合约
    const factory = new ethers.ContractFactory(ABI, BYTECODE, deployer);
    const contract = await factory.deploy(INSURANCE_V8_ADDRESS);
    await contract.waitForDeployment();

    console.log('Provider合约部署到:', await contract.getAddress());

    return contract;
}
```

### 2. 注册Provider合约

```javascript
async function registerProviderContract(contractAddress) {
    const providerContract = new ethers.Contract(
        contractAddress,
        PROVIDER_CONTRACT_ABI,
        signer
    );

    // 1. 转入USDC到合约
    const usdc = new ethers.Contract(USDC_ADDRESS, USDC_ABI, signer);
    await usdc.transfer(contractAddress, ethers.parseUnits('100', 6));

    // 2. 调用注册函数
    const tx = await providerContract.registerAsProvider(
        ethers.parseUnits('100', 6)
    );
    await tx.wait();

    console.log('Provider合约注册成功');
}
```

### 3. 查询合约状态

```javascript
async function checkContractProvider(contractAddress) {
    const insurance = new ethers.Contract(
        INSURANCE_V8_ADDRESS,
        INSURANCE_ABI,
        provider
    );

    const info = await insurance.getProviderInfo(contractAddress);
    console.log('合约Provider信息:', {
        isActive: info.isActive,
        poolBalance: ethers.formatUnits(info.poolBalance, 6),
        totalLocked: ethers.formatUnits(info.totalLocked, 6)
    });
}
```

## 前端集成

### SDK扩展支持合约Provider

```javascript
// X402InsuranceSDK扩展
class X402InsuranceSDK {
    // ... 原有代码 ...

    /**
     * 注册合约Provider
     * @param {string} contractAddress - Provider合约地址
     * @param {string} amount - USDC金额
     */
    async registerContractProvider(contractAddress, amount) {
        // 检查是否是合约
        const code = await this.provider.getCode(contractAddress);
        if (code === '0x') {
            throw new Error('Address is not a contract');
        }

        // 获取Provider合约实例
        const providerContract = new ethers.Contract(
            contractAddress,
            PROVIDER_CONTRACT_ABI,
            this.signer
        );

        // 检查是否支持Provider接口
        try {
            const interfaceId = await providerContract.supportsProviderInterface();
            if (interfaceId !== '0x12345678') {
                throw new Error('Contract does not support Provider interface');
            }
        } catch (error) {
            throw new Error('Invalid Provider contract');
        }

        // 转入USDC
        const parsedAmount = ethers.parseUnits(amount.toString(), 6);
        const usdcTx = await this.usdcContract.transfer(contractAddress, parsedAmount);
        await usdcTx.wait();

        // 调用合约的注册函数
        const registerTx = await providerContract.registerAsProvider(parsedAmount);
        await registerTx.wait();

        return {
            contractAddress,
            txHash: registerTx.hash
        };
    }

    /**
     * 获取合约Provider信息
     */
    async getContractProviderInfo(contractAddress) {
        // 获取基础信息
        const info = await this.getProviderInfo(contractAddress);

        // 检查是否是合约
        const code = await this.provider.getCode(contractAddress);
        info.isContract = code !== '0x';

        // 如果是合约，获取额外信息
        if (info.isContract) {
            try {
                const providerContract = new ethers.Contract(
                    contractAddress,
                    PROVIDER_CONTRACT_ABI,
                    this.provider
                );

                // 获取自动化参数（如果支持）
                if (providerContract.autoRefillThreshold) {
                    info.autoRefillThreshold = ethers.formatUnits(
                        await providerContract.autoRefillThreshold(),
                        6
                    );
                    info.autoRefillAmount = ethers.formatUnits(
                        await providerContract.autoRefillAmount(),
                        6
                    );
                }

                // 获取合约Owner
                if (providerContract.owner) {
                    info.contractOwner = await providerContract.owner();
                }
            } catch (error) {
                // 合约可能不支持这些功能
            }
        }

        return info;
    }
}
```

## 高级功能

### 1. 批量服务管理

```solidity
contract BatchServiceProvider {
    struct Service {
        bytes32 id;
        address client;
        uint256 amount;
        bool completed;
    }

    mapping(bytes32 => Service) public services;

    // 批量处理索赔
    function batchHandleClaims(bytes32[] memory commitments) external {
        for (uint i = 0; i < commitments.length; i++) {
            // 验证每个服务
            if (services[commitments[i]].completed) {
                // 争议已完成的服务
                IInsurance(INSURANCE_V8).disputeClaim(
                    commitments[i],
                    "Service completed"
                );
            }
        }
    }
}
```

### 2. 跨链Provider

```solidity
contract CrossChainProvider {
    // 支持多链部署
    mapping(uint256 => address) public insuranceContracts;

    function registerOnChain(uint256 chainId, uint256 amount) external {
        address insurance = insuranceContracts[chainId];
        require(insurance != address(0), "Chain not supported");

        // 跨链消息或其他机制
        // ...
    }
}
```

### 3. DAO管理的Provider

```solidity
contract DAOProvider {
    address public governance;

    // 通过DAO投票决定是否争议
    function proposeDispute(bytes32 commitment) external {
        // 创建提案
        // ...
    }

    function executeDispute(bytes32 commitment) external {
        require(msg.sender == governance, "Only governance");
        IInsurance(INSURANCE_V8).disputeClaim(commitment, "DAO decision");
    }
}
```

## 安全考虑

1. **权限管理** - 确保只有授权地址可以调用关键函数
2. **重入保护** - 使用ReentrancyGuard防止重入攻击
3. **余额检查** - 操作前检查USDC余额
4. **升级机制** - 考虑使用代理模式支持升级
5. **紧急暂停** - 实现紧急暂停功能

## 测试示例

```javascript
// test-contract-provider.js
const { ethers } = require('ethers');

async function testContractProvider() {
    // 1. 部署Provider合约
    const providerContract = await deployProviderContract();
    const contractAddress = await providerContract.getAddress();

    // 2. 发送USDC到合约
    const usdc = new ethers.Contract(USDC_ADDRESS, USDC_ABI, signer);
    await usdc.transfer(contractAddress, ethers.parseUnits('100', 6));

    // 3. 注册为Provider
    await providerContract.registerAsProvider(ethers.parseUnits('100', 6));

    // 4. 验证注册
    const insurance = new ethers.Contract(INSURANCE_V8, INSURANCE_ABI, provider);
    const info = await insurance.getProviderInfo(contractAddress);

    console.log('合约Provider注册成功:', {
        address: contractAddress,
        isActive: info.isActive,
        poolBalance: ethers.formatUnits(info.poolBalance, 6)
    });

    // 5. 测试索赔处理
    // 客户发起索赔
    const commitment = ethers.keccak256(ethers.toUtf8Bytes('test-claim'));
    await insurance.connect(clientSigner).initiateClaim(
        commitment,
        contractAddress,
        ethers.parseUnits('5', 6),
        0
    );

    // Provider合约自动处理或手动争议
    await providerContract.handleDispute(commitment, "Service delivered");
}

testContractProvider().catch(console.error);
```

## 常见问题

### Q: 合约Provider和EOA Provider有什么区别？

A: 主要区别：
- 合约Provider可以实现自动化逻辑
- 合约Provider需要通过合约调用注册
- 合约Provider可以集成复杂的业务逻辑
- 合约Provider的gas费用通常更高

### Q: 如何升级Provider合约？

A: 建议使用代理模式：
```solidity
contract ProviderProxy {
    address public implementation;

    function upgrade(address newImplementation) external onlyOwner {
        implementation = newImplementation;
    }

    fallback() external payable {
        // Delegate call to implementation
    }
}
```

### Q: 合约Provider如何处理多个服务？

A: 可以在合约中维护服务映射：
```solidity
mapping(bytes32 => ServiceInfo) public services;
mapping(address => bytes32[]) public clientServices;
```

### Q: 如何确保合约Provider的安全性？

A: 关键安全措施：
1. 使用多签或时间锁
2. 实现紧急暂停功能
3. 限制每日提取额度
4. 添加白名单机制
5. 定期审计合约代码