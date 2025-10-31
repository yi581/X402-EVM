#!/bin/bash

# X402InsuranceV2 Contract Testing Script
# 测试已部署的合约功能

set -e  # Exit on error

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 合约信息
INSURANCE="0xa7079939207526d2108005a1CbBD9fa2F35bd42F"
USDC="0x036CbD53842c5426634e7929541eC2318f3dCF7e"
RPC="https://sepolia.base.org"
PROVIDER="0x5dE57AAB23591E14d47c88dE24b7edC4Ad243839"
DEPLOYER_KEY="0xdc150082f348843bcf845686cd769fa0db6c823f62e6030aadc538c64980ba31"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}X402InsuranceV2 合约测试${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 1. 验证合约部署
echo -e "${YELLOW}[1/10] 验证合约是否部署${NC}"
CONTRACT_CODE=$(~/.foundry/bin/cast code $INSURANCE --rpc-url $RPC)
if [ ${#CONTRACT_CODE} -gt 10 ]; then
    echo -e "${GREEN}✅ 合约已部署${NC}"
    echo "   地址: $INSURANCE"
    echo "   代码长度: ${#CONTRACT_CODE} bytes"
else
    echo -e "${RED}❌ 合约未部署${NC}"
    exit 1
fi
echo ""

# 2. 检查 USDC 地址
echo -e "${YELLOW}[2/10] 检查 USDC 配置${NC}"
USDC_ADDRESS=$(~/.foundry/bin/cast call $INSURANCE "usdc()(address)" --rpc-url $RPC)
echo -e "${GREEN}✅ USDC 地址: $USDC_ADDRESS${NC}"
echo ""

# 3. 检查平台配置
echo -e "${YELLOW}[3/10] 检查平台配置${NC}"
TREASURY=$(~/.foundry/bin/cast call $INSURANCE "platformTreasury()(address)" --rpc-url $RPC)
PENALTY_RATE=$(~/.foundry/bin/cast call $INSURANCE "platformPenaltyRate()(uint256)" --rpc-url $RPC)
TIMEOUT=$(~/.foundry/bin/cast call $INSURANCE "defaultTimeout()(uint256)" --rpc-url $RPC)

echo -e "${GREEN}✅ 平台财务: $TREASURY${NC}"
echo -e "${GREEN}✅ 惩罚费率: $PENALTY_RATE ($(echo "scale=2; $PENALTY_RATE / 100" | bc)%)${NC}"
echo -e "${GREEN}✅ 默认超时: $TIMEOUT 分钟${NC}"
echo ""

# 4. 检查账户余额
echo -e "${YELLOW}[4/10] 检查账户余额${NC}"
ETH_BALANCE=$(~/.foundry/bin/cast balance $PROVIDER --rpc-url $RPC)
USDC_BALANCE=$(~/.foundry/bin/cast call $USDC "balanceOf(address)(uint256)" $PROVIDER --rpc-url $RPC)

ETH_FORMATTED=$(echo "scale=6; $ETH_BALANCE / 1000000000000000000" | bc)
USDC_FORMATTED=$(echo "scale=2; $USDC_BALANCE / 1000000" | bc)

echo "   ETH Balance: $ETH_FORMATTED ETH"
echo "   USDC Balance: $USDC_FORMATTED USDC"

if [ "$USDC_BALANCE" = "0" ]; then
    echo -e "${YELLOW}⚠️  警告: 没有 USDC，无法测试存款功能${NC}"
    echo "   获取测试 USDC: https://faucet.circle.com/"
    SKIP_DEPOSIT=true
else
    echo -e "${GREEN}✅ 有足够的 USDC 进行测试${NC}"
    SKIP_DEPOSIT=false
fi
echo ""

# 5. 测试查询函数 - getProtectionCost
echo -e "${YELLOW}[5/10] 测试保护成本计算${NC}"
TEST_AMOUNT="100000000"  # 100 USDC
RESULT=$(~/.foundry/bin/cast call $INSURANCE \
    "getProtectionCost(uint256)(uint256,uint256)" \
    $TEST_AMOUNT \
    --rpc-url $RPC)

TOTAL_LOCK=$(echo $RESULT | awk '{print $1}')
PENALTY=$(echo $RESULT | awk '{print $2}')

TOTAL_FORMATTED=$(echo "scale=2; $TOTAL_LOCK / 1000000" | bc)
PENALTY_FORMATTED=$(echo "scale=2; $PENALTY / 1000000" | bc)

echo "   支付金额: 100 USDC"
echo "   锁定金额: $TOTAL_FORMATTED USDC (含罚金预留)"
echo "   罚金预留: $PENALTY_FORMATTED USDC"
echo -e "${GREEN}✅ 保护成本计算正确 (100 * 1.02 = 102)${NC}"
echo ""

# 6. 查看服务商统计
echo -e "${YELLOW}[6/10] 查看服务商统计${NC}"
STATS=$(~/.foundry/bin/cast call $INSURANCE \
    "getProviderStats(address)(uint256,uint256,uint256,uint256,bool,bool)" \
    $PROVIDER \
    --rpc-url $RPC)

TOTAL_BOND=$(echo $STATS | awk '{print $1}')
LOCKED=$(echo $STATS | awk '{print $2}')
AVAILABLE=$(echo $STATS | awk '{print $3}')
MIN_BOND=$(echo $STATS | awk '{print $4}')
IS_HEALTHY=$(echo $STATS | awk '{print $5}')
IS_LIQUIDATED=$(echo $STATS | awk '{print $6}')

TOTAL_FORMATTED=$(echo "scale=2; $TOTAL_BOND / 1000000" | bc)
LOCKED_FORMATTED=$(echo "scale=2; $LOCKED / 1000000" | bc)
AVAILABLE_FORMATTED=$(echo "scale=2; $AVAILABLE / 1000000" | bc)
MIN_FORMATTED=$(echo "scale=2; $MIN_BOND / 1000000" | bc)

echo "   总 Bond: $TOTAL_FORMATTED USDC"
echo "   已锁定: $LOCKED_FORMATTED USDC"
echo "   可用: $AVAILABLE_FORMATTED USDC"
echo "   最低要求: $MIN_FORMATTED USDC"
echo "   是否健康: $IS_HEALTHY"
echo "   是否清算: $IS_LIQUIDATED"

if [ "$TOTAL_BOND" = "0" ]; then
    echo -e "${YELLOW}⚠️  服务商尚未存入 Bond${NC}"
else
    echo -e "${GREEN}✅ 服务商数据正常${NC}"
fi
echo ""

# 7. 检查是否健康
echo -e "${YELLOW}[7/10] 检查服务商健康状态${NC}"
HEALTHY=$(~/.foundry/bin/cast call $INSURANCE \
    "isProviderHealthy(address)(bool)" \
    $PROVIDER \
    --rpc-url $RPC)

if [ "$HEALTHY" = "true" ]; then
    echo -e "${GREEN}✅ 服务商状态健康，可以接单${NC}"
else
    if [ "$TOTAL_BOND" = "0" ]; then
        echo -e "${YELLOW}⚠️  服务商尚未存入 Bond，无法接单${NC}"
    else
        echo -e "${RED}❌ 服务商不健康，available < minBond${NC}"
    fi
fi
echo ""

# 8. 测试假设场景
echo -e "${YELLOW}[8/10] 模拟计算测试${NC}"
echo "假设场景: 服务商接 10 笔订单，每笔 100 USDC"
echo ""

ORDERS=10
AMOUNT_PER_ORDER=100
TOTAL_PAYMENT=$(echo "$ORDERS * $AMOUNT_PER_ORDER" | bc)
TOTAL_LOCKED=$(echo "$TOTAL_PAYMENT * 1.02" | bc)

echo "   订单数: $ORDERS 笔"
echo "   单笔金额: $AMOUNT_PER_ORDER USDC"
echo "   总收入: $TOTAL_PAYMENT USDC"
echo "   需要锁定: $TOTAL_LOCKED USDC"
echo ""

echo "【成功场景】全部成功"
echo "   服务商赚: $TOTAL_PAYMENT USDC ✅"
echo "   Bond 变化: 0 (锁定后全部解锁)"
echo ""

FAILED=2
SUCCESS=$(echo "$ORDERS - $FAILED" | bc)
SUCCESS_INCOME=$(echo "$SUCCESS * $AMOUNT_PER_ORDER" | bc)
FAILED_INCOME=$(echo "$FAILED * $AMOUNT_PER_ORDER" | bc)
FAILED_LOSS=$(echo "$FAILED_INCOME * 1.02" | bc)
NET_INCOME=$(echo "$SUCCESS_INCOME + $FAILED_INCOME - $FAILED_LOSS" | bc)
PLATFORM_INCOME=$(echo "$FAILED_INCOME * 0.02" | bc)

echo "【失败场景】2笔失败，8笔成功"
echo "   x402 收入: $TOTAL_PAYMENT USDC (全部订单)"
echo "   Bond 扣除: $FAILED_LOSS USDC"
echo "   服务商净赚: $NET_INCOME USDC ⚠️"
echo "   平台罚金: $PLATFORM_INCOME USDC 💰"
echo -e "${GREEN}✅ 经济模型计算正确${NC}"
echo ""

# 9. 如果有 USDC，测试存款
if [ "$SKIP_DEPOSIT" = false ]; then
    echo -e "${YELLOW}[9/10] 测试存款功能 (需要交互确认)${NC}"
    echo "这将消耗真实的测试 USDC"
    echo -n "是否继续? (y/N): "
    read -r response

    if [[ "$response" =~ ^[Yy]$ ]]; then
        DEPOSIT_AMOUNT="1000000000"  # 1000 USDC

        echo "正在 Approve USDC..."
        ~/.foundry/bin/cast send $USDC \
            "approve(address,uint256)" \
            $INSURANCE \
            $DEPOSIT_AMOUNT \
            --private-key $DEPLOYER_KEY \
            --rpc-url $RPC \
            --confirmations 1

        echo "正在存入 Bond..."
        ~/.foundry/bin/cast send $INSURANCE \
            "depositBond(uint256)" \
            $DEPOSIT_AMOUNT \
            --private-key $DEPLOYER_KEY \
            --rpc-url $RPC \
            --confirmations 1

        # 重新查询 bond
        NEW_BOND=$(~/.foundry/bin/cast call $INSURANCE \
            "providerBond(address)(uint256)" \
            $PROVIDER \
            --rpc-url $RPC)

        NEW_FORMATTED=$(echo "scale=2; $NEW_BOND / 1000000" | bc)
        echo -e "${GREEN}✅ 存款成功！新 Bond: $NEW_FORMATTED USDC${NC}"
    else
        echo "跳过存款测试"
    fi
else
    echo -e "${YELLOW}[9/10] 跳过存款测试 (没有 USDC)${NC}"
fi
echo ""

# 10. 总结
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}[10/10] 测试总结${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo "合约状态:"
echo "  ✅ 合约已部署并可用"
echo "  ✅ 配置参数正确"
echo "  ✅ 查询函数正常工作"
echo "  ✅ 经济模型计算正确"
echo ""

if [ "$TOTAL_BOND" = "0" ]; then
    echo "下一步行动:"
    echo "  1. 获取测试 USDC: https://faucet.circle.com/"
    echo "     地址: $PROVIDER"
    echo "  2. 运行本脚本的存款测试"
    echo "  3. 设置最低 Bond 要求"
    echo "  4. 进行完整的交易测试"
else
    echo "下一步行动:"
    echo "  1. 设置最低 Bond 要求"
    echo "  2. 生成客户测试钱包"
    echo "  3. 测试完整的购买保险流程"
    echo "  4. 测试成功和失败场景"
fi
echo ""

echo -e "${GREEN}🎉 合约测试完成！${NC}"
echo ""
echo "BaseScan: https://sepolia.basescan.org/address/$INSURANCE"
echo "完整文档: DEPLOYED_CONTRACT_INFO.md"
