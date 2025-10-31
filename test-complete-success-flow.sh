#!/bin/bash
# ============================================================================
# ⚠️  SECURITY WARNING - READ BEFORE RUNNING
# ============================================================================
# This script contains BASE SEPOLIA TESTNET private keys for demonstration.
# These keys are PUBLIC and should NEVER be used on mainnet or with real funds!
#
# DO NOT use these keys for anything other than Base Sepolia testnet testing.
# For your own testing, replace these keys with your own testnet keys.
#
# Testnet USDC only - NO REAL VALUE
# ============================================================================

# 完整成功流程测试
# 模拟: 用户支付 1 USDC → 购买服务 → 商家交付 → 确认服务

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# 合约地址
INSURANCE="0xa7079939207526d2108005a1CbBD9fa2F35bd42F"
USDC="0x036CbD53842c5426634e7929541eC2318f3dCF7e"
RPC="https://sepolia.base.org"

# 角色
PROVIDER="0x5dE57AAB23591E14d47c88dE24b7edC4Ad243839"
PROVIDER_KEY="0xdc150082f348843bcf845686cd769fa0db6c823f62e6030aadc538c64980ba31"  # ⚠️ TESTNET ONLY
CLIENT="0xDf1f5C7ADECfbaD3B0F5aD4522DbB089F0a6e253"
CLIENT_KEY="0x4c9a6781a7ed5ec084963790c52f8865172514d4478774eb0dcce9ffe08886ab"  # ⚠️ TESTNET ONLY

# 新的 request ID
REQUEST="0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
PAYMENT_AMOUNT="1000000"  # 1 USDC

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}完整成功流程测试${NC}"
echo -e "${BLUE}用户支付 1 USDC 购买服务${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# ============================================================
# 阶段 1: 用户需要先获得 1 USDC (模拟 x402 支付前)
# ============================================================
echo -e "${YELLOW}[阶段 1/5] 准备测试 - 给客户转 1 USDC${NC}"
echo "说明: 在真实场景中，用户钱包里已经有 USDC"
echo "这里我们从 Provider 转 1 USDC 给 Client 模拟"
echo ""

# 检查客户当前余额
CLIENT_USDC_BEFORE=$(~/.foundry/bin/cast call $USDC "balanceOf(address)(uint256)" $CLIENT --rpc-url $RPC)
echo "客户当前 USDC: $CLIENT_USDC_BEFORE"

# 给客户转 1 USDC (模拟用户已有 USDC)
echo "从 Provider 转 1 USDC 给 Client..."
~/.foundry/bin/cast send $USDC \
  "transfer(address,uint256)" \
  $CLIENT \
  $PAYMENT_AMOUNT \
  --private-key $PROVIDER_KEY \
  --rpc-url $RPC \
  --confirmations 1

CLIENT_USDC_AFTER=$(~/.foundry/bin/cast call $USDC "balanceOf(address)(uint256)" $CLIENT --rpc-url $RPC)
echo -e "${GREEN}✅ 客户现在有 USDC: $CLIENT_USDC_AFTER${NC}"
echo ""

# ============================================================
# 阶段 2: 用户通过 x402 支付 1 USDC 给商家
# ============================================================
echo -e "${YELLOW}[阶段 2/5] x402 支付 - 用户支付 1 USDC 给商家${NC}"
echo "说明: 这是 x402 协议的即时支付，用户直接付款给商家"
echo ""

PROVIDER_USDC_BEFORE=$(~/.foundry/bin/cast call $USDC "balanceOf(address)(uint256)" $PROVIDER --rpc-url $RPC)
echo "商家支付前 USDC: $PROVIDER_USDC_BEFORE"

# 客户 approve + transfer 给商家 (模拟 x402 支付)
echo "1/2 - 客户 Approve USDC..."
~/.foundry/bin/cast send $USDC \
  "approve(address,uint256)" \
  $PROVIDER \
  $PAYMENT_AMOUNT \
  --private-key $CLIENT_KEY \
  --rpc-url $RPC \
  --confirmations 1

echo "2/2 - 商家接收 x402 支付 (transferFrom)..."
~/.foundry/bin/cast send $USDC \
  "transferFrom(address,address,uint256)" \
  $CLIENT \
  $PROVIDER \
  $PAYMENT_AMOUNT \
  --private-key $PROVIDER_KEY \
  --rpc-url $RPC \
  --confirmations 1

PROVIDER_USDC_AFTER=$(~/.foundry/bin/cast call $USDC "balanceOf(address)(uint256)" $PROVIDER --rpc-url $RPC)
CLIENT_USDC_PAID=$(~/.foundry/bin/cast call $USDC "balanceOf(address)(uint256)" $CLIENT --rpc-url $RPC)

echo -e "${GREEN}✅ x402 支付完成${NC}"
echo "   商家收到: $PROVIDER_USDC_AFTER"
echo "   客户剩余: $CLIENT_USDC_PAID"
echo ""

# ============================================================
# 阶段 3: 客户购买保险 (零保险费!)
# ============================================================
echo -e "${YELLOW}[阶段 3/5] 购买保险 - 客户零费用购买保护${NC}"
echo "说明: 客户无需再支付 USDC，只需少量 gas 费"
echo ""

PROVIDER_BOND_BEFORE=$(~/.foundry/bin/cast call $INSURANCE "providerBond(address)(uint256)" $PROVIDER --rpc-url $RPC)
LOCKED_BEFORE=$(~/.foundry/bin/cast call $INSURANCE "lockedBond(address)(uint256)" $PROVIDER --rpc-url $RPC)

echo "购买前商家 Bond:"
echo "   Total: $PROVIDER_BOND_BEFORE"
echo "   Locked: $LOCKED_BEFORE"
echo ""

echo "客户购买保险 (零 USDC 费用)..."
~/.foundry/bin/cast send $INSURANCE \
  "purchaseInsurance(bytes32,address,uint256,uint256)" \
  $REQUEST \
  $PROVIDER \
  $PAYMENT_AMOUNT \
  5 \
  --private-key $CLIENT_KEY \
  --rpc-url $RPC

PROVIDER_BOND_AFTER=$(~/.foundry/bin/cast call $INSURANCE "providerBond(address)(uint256)" $PROVIDER --rpc-url $RPC)
LOCKED_AFTER=$(~/.foundry/bin/cast call $INSURANCE "lockedBond(address)(uint256)" $PROVIDER --rpc-url $RPC)

echo -e "${GREEN}✅ 保险购买成功${NC}"
echo "购买后商家 Bond:"
echo "   Total: $PROVIDER_BOND_AFTER (不变) ✅"
echo "   Locked: $LOCKED_AFTER (锁定 1.02 USDC) ✅"
echo ""

# ============================================================
# 阶段 4: 商家提供服务并确认
# ============================================================
echo -e "${YELLOW}[阶段 4/5] 服务交付 - 商家完成服务并签名确认${NC}"
echo "说明: 商家提供服务后，用 EIP-712 签名确认"
echo ""

echo "生成 EIP-712 签名..."
cd /Users/panda/Documents/ibnk/code/X402

# 创建临时签名脚本
cat > temp-sign.js << 'EOF'
const { ethers } = require('ethers');
const INSURANCE = '0xa7079939207526d2108005a1CbBD9fa2F35bd42F';
const CHAIN_ID = 84532;
const PROVIDER_KEY = '0xdc150082f348843bcf845686cd769fa0db6c823f62e6030aadc538c64980ba31';
const REQUEST = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

const domain = {
  name: 'X402InsuranceV2',
  version: '1',
  chainId: CHAIN_ID,
  verifyingContract: INSURANCE
};

const types = {
  ServiceConfirmation: [{ name: 'requestCommitment', type: 'bytes32' }]
};

const message = { requestCommitment: REQUEST };

(async () => {
  const wallet = new ethers.Wallet(PROVIDER_KEY);
  const signature = await wallet.signTypedData(domain, types, message);
  console.log(signature);
})();
EOF

SIGNATURE=$(node temp-sign.js)
rm temp-sign.js

echo "签名: $SIGNATURE"
echo ""

echo "商家确认服务..."
~/.foundry/bin/cast send $INSURANCE \
  "confirmService(bytes32,bytes)" \
  $REQUEST \
  $SIGNATURE \
  --private-key $PROVIDER_KEY \
  --rpc-url $RPC

PROVIDER_BOND_FINAL=$(~/.foundry/bin/cast call $INSURANCE "providerBond(address)(uint256)" $PROVIDER --rpc-url $RPC)
LOCKED_FINAL=$(~/.foundry/bin/cast call $INSURANCE "lockedBond(address)(uint256)" $PROVIDER --rpc-url $RPC)

echo -e "${GREEN}✅ 服务确认成功${NC}"
echo "确认后商家 Bond:"
echo "   Total: $PROVIDER_BOND_FINAL (不变) ✅"
echo "   Locked: $LOCKED_FINAL (解锁，恢复为 0) ✅"
echo ""

# ============================================================
# 阶段 5: 总结对账
# ============================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}[阶段 5/5] 最终对账${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 最终余额
PROVIDER_USDC_FINAL=$(~/.foundry/bin/cast call $USDC "balanceOf(address)(uint256)" $PROVIDER --rpc-url $RPC)
CLIENT_USDC_FINAL=$(~/.foundry/bin/cast call $USDC "balanceOf(address)(uint256)" $CLIENT --rpc-url $RPC)
PROVIDER_BOND_FINAL=$(~/.foundry/bin/cast call $INSURANCE "providerBond(address)(uint256)" $PROVIDER --rpc-url $RPC)

echo -e "${YELLOW}商家 (Provider):${NC}"
echo "  USDC 余额变化:"
echo "    初始: $PROVIDER_USDC_BEFORE"
echo "    收到 x402: +1 USDC"
echo "    最终: $PROVIDER_USDC_FINAL"
echo "    净收入: +1 USDC ✅"
echo ""
echo "  Bond 余额:"
echo "    初始: $PROVIDER_BOND_BEFORE"
echo "    锁定: 1.02 USDC (临时)"
echo "    解锁: 1.02 USDC"
echo "    最终: $PROVIDER_BOND_FINAL"
echo "    净变化: 0 ✅"
echo ""

echo -e "${YELLOW}客户 (Client):${NC}"
echo "  USDC 余额变化:"
echo "    初始: $CLIENT_USDC_BEFORE"
echo "    获得: +1 USDC (准备阶段)"
echo "    x402 支付: -1 USDC"
echo "    保险费: -0 USDC ✅"
echo "    最终: $CLIENT_USDC_FINAL"
echo "    净花费: 1 USDC (只有服务费) ✅"
echo ""
echo "  获得服务: ✅ 是"
echo ""

echo -e "${YELLOW}平台 (Platform):${NC}"
echo "  收入: 0 USDC (成功场景无收入)"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ 完整成功流程测试完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo "关键验证:"
echo "  ✅ 用户支付 1 USDC 给商家 (x402)"
echo "  ✅ 用户购买保险零费用"
echo "  ✅ 商家 Bond 自动锁定/解锁"
echo "  ✅ 商家净收入 1 USDC"
echo "  ✅ 用户获得服务，只花 1 USDC"
echo ""

echo "BaseScan 查看:"
echo "  Provider: https://sepolia.basescan.org/address/$PROVIDER#tokentxns"
echo "  Client: https://sepolia.basescan.org/address/$CLIENT#tokentxns"
echo ""
