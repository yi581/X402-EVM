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

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSURANCE="0xa7079939207526d2108005a1CbBD9fa2F35bd42F"
USDC="0x036CbD53842c5426634e7929541eC2318f3dCF7e"
RPC="https://sepolia.base.org"
PROVIDER="0x5dE57AAB23591E14d47c88dE24b7edC4Ad243839"
PROVIDER_KEY="0xdc150082f348843bcf845686cd769fa0db6c823f62e6030aadc538c64980ba31"  # ⚠️ TESTNET ONLY
CLIENT="0xDf1f5C7ADECfbaD3B0F5aD4522DbB089F0a6e253"
CLIENT_KEY="0x4c9a6781a7ed5ec084963790c52f8865172514d4478774eb0dcce9ffe08886ab"  # ⚠️ TESTNET ONLY
REQUEST="0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
PAYMENT="1000000"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}完整成功流程: 用户花 1 USDC 买服务${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 检查初始余额
echo -e "${YELLOW}初始状态:${NC}"
CLIENT_USDC=$(~/.foundry/bin/cast call $USDC "balanceOf(address)(uint256)" $CLIENT --rpc-url $RPC)
PROVIDER_USDC=$(~/.foundry/bin/cast call $USDC "balanceOf(address)(uint256)" $PROVIDER --rpc-url $RPC)
PROVIDER_BOND=$(~/.foundry/bin/cast call $INSURANCE "providerBond(address)(uint256)" $PROVIDER --rpc-url $RPC)
LOCKED=$(~/.foundry/bin/cast call $INSURANCE "lockedBond(address)(uint256)" $PROVIDER --rpc-url $RPC)

echo "  客户 USDC: $CLIENT_USDC"
echo "  商家 USDC: $PROVIDER_USDC"
echo "  商家 Bond: $PROVIDER_BOND (Locked: $LOCKED)"
echo ""

# 阶段 1: x402 支付
echo -e "${YELLOW}[1/4] x402 支付 - 客户付 1 USDC 给商家${NC}"
echo "客户 transfer 1 USDC 给商家..."
~/.foundry/bin/cast send $USDC \
  "transfer(address,uint256)" \
  $PROVIDER \
  $PAYMENT \
  --private-key $CLIENT_KEY \
  --rpc-url $RPC

CLIENT_AFTER_PAY=$(~/.foundry/bin/cast call $USDC "balanceOf(address)(uint256)" $CLIENT --rpc-url $RPC)
PROVIDER_AFTER_PAY=$(~/.foundry/bin/cast call $USDC "balanceOf(address)(uint256)" $PROVIDER --rpc-url $RPC)
echo -e "${GREEN}✅ x402 支付完成${NC}"
echo "  客户剩余: $CLIENT_AFTER_PAY"
echo "  商家收到: $PROVIDER_AFTER_PAY"
echo ""

# 阶段 2: 购买保险
echo -e "${YELLOW}[2/4] 购买保险 - 客户零费用${NC}"
~/.foundry/bin/cast send $INSURANCE \
  "purchaseInsurance(bytes32,address,uint256,uint256)" \
  $REQUEST \
  $PROVIDER \
  $PAYMENT \
  5 \
  --private-key $CLIENT_KEY \
  --rpc-url $RPC

LOCKED_AFTER=$(~/.foundry/bin/cast call $INSURANCE "lockedBond(address)(uint256)" $PROVIDER --rpc-url $RPC)
echo -e "${GREEN}✅ 保险购买成功 (客户零费用!)${NC}"
echo "  商家 Bond 锁定: $LOCKED_AFTER (1.02 USDC)"
echo ""

# 阶段 3: 生成签名并确认
echo -e "${YELLOW}[3/4] 商家确认服务 (EIP-712)${NC}"
cd /Users/panda/Documents/ibnk/code/X402
cat > temp.js << 'EOF'
const { ethers } = require('ethers');
(async () => {
  const wallet = new ethers.Wallet('0xdc150082f348843bcf845686cd769fa0db6c823f62e6030aadc538c64980ba31');
  const sig = await wallet.signTypedData(
    { name: 'X402InsuranceV2', version: '1', chainId: 84532, verifyingContract: '0xa7079939207526d2108005a1CbBD9fa2F35bd42F' },
    { ServiceConfirmation: [{ name: 'requestCommitment', type: 'bytes32' }] },
    { requestCommitment: '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' }
  );
  console.log(sig);
})();
EOF
SIG=$(node temp.js)
rm temp.js

~/.foundry/bin/cast send $INSURANCE \
  "confirmService(bytes32,bytes)" \
  $REQUEST \
  $SIG \
  --private-key $PROVIDER_KEY \
  --rpc-url $RPC

LOCKED_FINAL=$(~/.foundry/bin/cast call $INSURANCE "lockedBond(address)(uint256)" $PROVIDER --rpc-url $RPC)
echo -e "${GREEN}✅ 服务确认成功${NC}"
echo "  商家 Bond 解锁: $LOCKED_FINAL (恢复为 0)"
echo ""

# 最终对账
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}[4/4] 最终对账${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

CLIENT_FINAL=$(~/.foundry/bin/cast call $USDC "balanceOf(address)(uint256)" $CLIENT --rpc-url $RPC)
PROVIDER_FINAL=$(~/.foundry/bin/cast call $USDC "balanceOf(address)(uint256)" $PROVIDER --rpc-url $RPC)
BOND_FINAL=$(~/.foundry/bin/cast call $INSURANCE "providerBond(address)(uint256)" $PROVIDER --rpc-url $RPC)

echo -e "${YELLOW}客户:${NC}"
echo "  初始 USDC: $CLIENT_USDC"
echo "  x402 支付: -1 USDC"
echo "  保险费: 0 USDC ✅"
echo "  最终: $CLIENT_FINAL"
echo "  获得服务: ✅"
echo ""

echo -e "${YELLOW}商家:${NC}"
echo "  初始 USDC: $PROVIDER_USDC"
echo "  x402 收入: +1 USDC"
echo "  最终 USDC: $PROVIDER_FINAL"
echo "  Bond: $BOND_FINAL (无变化)"
echo "  净收入: +1 USDC ✅"
echo ""

echo -e "${GREEN}✅ 完整成功流程测试完成！${NC}"
echo ""
echo "BaseScan 查看客户交易:"
echo "https://sepolia.basescan.org/address/$CLIENT#tokentxns"
