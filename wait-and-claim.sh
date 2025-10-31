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

# Wait for timeout and claim insurance
# 等待超时并申领保险

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSURANCE="0xa7079939207526d2108005a1CbBD9fa2F35bd42F"
RPC="https://sepolia.base.org"
REQUEST="0xabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd"
CLIENT="0xDf1f5C7ADECfbaD3B0F5aD4522DbB089F0a6e253"
CLIENT_KEY="0x4c9a6781a7ed5ec084963790c52f8865172514d4478774eb0dcce9ffe08886ab"  # ⚠️ TESTNET ONLY
PROVIDER="0x5dE57AAB23591E14d47c88dE24b7edC4Ad243839"
USDC="0x036CbD53842c5426634e7929541eC2318f3dCF7e"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}等待超时并申领保险${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 检查当前状态
echo -e "${YELLOW}[1/4] 检查当前状态${NC}"
CAN_CLAIM=$(~/.foundry/bin/cast call $INSURANCE "canClaimInsurance(bytes32)(bool)" $REQUEST --rpc-url $RPC)
echo "Can Claim Now: $CAN_CLAIM"
echo ""

if [ "$CAN_CLAIM" = "true" ]; then
    echo -e "${GREEN}✅ 已超时，可以立即申领！${NC}"
else
    echo -e "${YELLOW}⏳ 未超时，等待 5 分钟...${NC}"
    echo "开始时间: $(date)"
    echo ""

    # 每 30 秒检查一次
    for i in {1..10}; do
        echo "检查 $i/10 (等待 30 秒...)"
        sleep 30
        CAN_CLAIM=$(~/.foundry/bin/cast call $INSURANCE "canClaimInsurance(bytes32)(bool)" $REQUEST --rpc-url $RPC)
        if [ "$CAN_CLAIM" = "true" ]; then
            echo -e "${GREEN}✅ 超时！可以申领了${NC}"
            break
        fi
    done
    echo ""
fi

# 检查余额（申领前）
echo -e "${YELLOW}[2/4] 申领前状态${NC}"

PROVIDER_BOND_BEFORE=$(~/.foundry/bin/cast call $INSURANCE "providerBond(address)(uint256)" $PROVIDER --rpc-url $RPC)
LOCKED_BEFORE=$(~/.foundry/bin/cast call $INSURANCE "lockedBond(address)(uint256)" $PROVIDER --rpc-url $RPC)
CLIENT_USDC_BEFORE=$(~/.foundry/bin/cast call $USDC "balanceOf(address)(uint256)" $CLIENT --rpc-url $RPC)

echo "Provider Bond: $PROVIDER_BOND_BEFORE"
echo "Locked: $LOCKED_BEFORE"
echo "Client USDC: $CLIENT_USDC_BEFORE"
echo ""

# 申领保险
echo -e "${YELLOW}[3/4] 客户申领保险${NC}"
~/.foundry/bin/cast send $INSURANCE \
  "claimInsurance(bytes32)" \
  $REQUEST \
  --private-key $CLIENT_KEY \
  --rpc-url $RPC

echo -e "${GREEN}✅ 申领成功！${NC}"
echo ""

# 检查余额（申领后）
echo -e "${YELLOW}[4/4] 申领后状态${NC}"

PROVIDER_BOND_AFTER=$(~/.foundry/bin/cast call $INSURANCE "providerBond(address)(uint256)" $PROVIDER --rpc-url $RPC)
LOCKED_AFTER=$(~/.foundry/bin/cast call $INSURANCE "lockedBond(address)(uint256)" $PROVIDER --rpc-url $RPC)
CLIENT_USDC_AFTER=$(~/.foundry/bin/cast call $USDC "balanceOf(address)(uint256)" $CLIENT --rpc-url $RPC)

echo "Provider Bond: $PROVIDER_BOND_AFTER (before: $PROVIDER_BOND_BEFORE)"
echo "Locked: $LOCKED_AFTER (before: $LOCKED_BEFORE)"
echo "Client USDC: $CLIENT_USDC_AFTER (before: $CLIENT_USDC_BEFORE)"
echo ""

# 计算变化
BOND_CHANGE=$((PROVIDER_BOND_BEFORE - PROVIDER_BOND_AFTER))
LOCKED_CHANGE=$((LOCKED_BEFORE - LOCKED_AFTER))
CLIENT_GAIN=$((CLIENT_USDC_AFTER - CLIENT_USDC_BEFORE))

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}结果分析${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo "Provider Bond 减少: $BOND_CHANGE (应该是 2040000 = 2.04 USDC)"
echo "Locked 减少: $LOCKED_CHANGE (应该是 2040000 = 2.04 USDC)"
echo "Client 获得: $CLIENT_GAIN (应该是 2000000 = 2 USDC)"
echo ""

# 验证
if [ "$BOND_CHANGE" = "2040000" ] && [ "$LOCKED_CHANGE" = "2040000" ] && [ "$CLIENT_GAIN" = "2000000" ]; then
    echo -e "${GREEN}✅ 所有验证通过！${NC}"
    echo ""
    echo "经济模型验证:"
    echo "  - 服务商 Bond 扣除: 2.04 USDC (2 + 0.04 罚金) ✅"
    echo "  - 客户获得补偿: 2 USDC ✅"
    echo "  - 平台获得罚金: 0.04 USDC ✅"
else
    echo -e "${YELLOW}⚠️  数值不匹配，请检查${NC}"
fi
echo ""

echo -e "${GREEN}🎉 失败场景测试完成！${NC}"
