#!/bin/bash

# X402InsuranceV2 - Next Steps for Full Testing
# 下一步完整测试指南

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Contract info
INSURANCE="0xa7079939207526d2108005a1CbBD9fa2F35bd42F"
USDC="0x036CbD53842c5426634e7929541eC2318f3dCF7e"
RPC="https://sepolia.base.org"
PROVIDER="0x5dE57AAB23591E14d47c88dE24b7edC4Ad243839"
DEPLOYER_KEY="0xdc150082f348843bcf845686cd769fa0db6c823f62e6030aadc538c64980ba31"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}X402InsuranceV2 - 下一步测试${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Check USDC balance
echo -e "${YELLOW}Step 1: 检查 USDC 余额${NC}"
USDC_BALANCE=$(~/.foundry/bin/cast call $USDC "balanceOf(address)(uint256)" $PROVIDER --rpc-url $RPC)
echo "当前 USDC 余额: $USDC_BALANCE"

if [ "$USDC_BALANCE" = "0" ]; then
    echo -e "${YELLOW}⚠️  还没有 USDC！${NC}"
    echo ""
    echo "请按照以下步骤获取测试 USDC:"
    echo ""
    echo "方式 1: Circle USDC Faucet (推荐)"
    echo "  1. 访问: https://faucet.circle.com/"
    echo "  2. 选择网络: Base Sepolia"
    echo "  3. 输入地址: $PROVIDER"
    echo "  4. 领取 USDC"
    echo ""
    echo "方式 2: Aave Faucet"
    echo "  1. 访问: https://staging.aave.com/faucet/"
    echo "  2. 选择网络: Base Sepolia"
    echo "  3. 连接钱包或输入地址"
    echo "  4. 领取 USDC"
    echo ""
    echo "获取 USDC 后，重新运行此脚本"
    exit 0
fi

echo -e "${GREEN}✅ 有 USDC，可以继续测试${NC}"
echo ""

# Step 2: Deposit Bond
echo -e "${YELLOW}Step 2: 存入 Bond${NC}"
echo "准备存入 1000 USDC 作为服务商保证金"
echo ""
read -p "是否继续? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

DEPOSIT_AMOUNT="1000000000"  # 1000 USDC

echo "1/2 - Approving USDC..."
~/.foundry/bin/cast send $USDC \
  "approve(address,uint256)" \
  $INSURANCE \
  $DEPOSIT_AMOUNT \
  --private-key $DEPLOYER_KEY \
  --rpc-url $RPC \
  --confirmations 1

echo "2/2 - Depositing Bond..."
~/.foundry/bin/cast send $INSURANCE \
  "depositBond(uint256)" \
  $DEPOSIT_AMOUNT \
  --private-key $DEPLOYER_KEY \
  --rpc-url $RPC \
  --confirmations 1

# Verify deposit
NEW_BOND=$(~/.foundry/bin/cast call $INSURANCE "providerBond(address)(uint256)" $PROVIDER --rpc-url $RPC)
echo -e "${GREEN}✅ Bond 存入成功！${NC}"
echo "新的 Bond 余额: $NEW_BOND (应该是 1000000000)"
echo ""

# Step 3: Set min bond
echo -e "${YELLOW}Step 3: 设置最低 Bond 要求${NC}"
echo "设置 500 USDC 作为最低保证金要求"
echo ""

MIN_BOND="500000000"  # 500 USDC

~/.foundry/bin/cast send $INSURANCE \
  "setMinProviderBond(address,uint256)" \
  $PROVIDER \
  $MIN_BOND \
  --private-key $DEPLOYER_KEY \
  --rpc-url $RPC \
  --confirmations 1

# Verify setting
SET_MIN=$(~/.foundry/bin/cast call $INSURANCE "minProviderBond(address)(uint256)" $PROVIDER --rpc-url $RPC)
echo -e "${GREEN}✅ 最低要求设置成功！${NC}"
echo "最低 Bond: $SET_MIN (应该是 500000000)"
echo ""

# Step 4: Check provider stats
echo -e "${YELLOW}Step 4: 查看服务商完整统计${NC}"
STATS=$(~/.foundry/bin/cast call $INSURANCE \
  "getProviderStats(address)(uint256,uint256,uint256,uint256,bool,bool)" \
  $PROVIDER \
  --rpc-url $RPC)

echo "服务商统计:"
echo "$STATS"
echo ""

# Step 5: Ready for testing
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✅ 准备就绪！${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "现在可以测试完整流程:"
echo ""
echo "1. 客户购买保险 (零费用!)"
echo "   需要客户钱包地址和私钥"
echo ""
echo "2. 服务商确认服务 (成功场景)"
echo "   需要 EIP-712 签名"
echo "   参考: X402_INSURANCE_V2_GUIDE.md"
echo ""
echo "3. 客户申领保险 (失败场景)"
echo "   等待超时后申领"
echo "   验证 Bond 扣除和补偿"
echo ""
echo "完整测试文档: CONTRACT_TEST_REPORT.md"
echo "集成指南: X402_INSURANCE_V2_GUIDE.md"
echo ""
echo "BaseScan: https://sepolia.basescan.org/address/$INSURANCE"
echo ""
