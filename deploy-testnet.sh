#!/bin/bash

# X402 Insurance V3 - Base Sepolia Testnet Deployment
# =====================================================

echo "========================================="
echo "X402 Insurance V3 - Testnet Deployment"
echo "========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if .env exists
if [ ! -f .env ]; then
    echo -e "${RED}❌ .env file not found!${NC}"
    echo "Please copy .env.example to .env and configure it."
    exit 1
fi

# Source environment variables
source .env

# Check required variables
echo "📋 Checking configuration..."
echo ""

if [ -z "$DEPLOYER_PRIVATE_KEY" ] || [ "$DEPLOYER_PRIVATE_KEY" == "0x_YOUR_PRIVATE_KEY_HERE" ]; then
    echo -e "${RED}❌ DEPLOYER_PRIVATE_KEY not configured!${NC}"
    echo ""
    echo "Please:"
    echo "1. Create a wallet for deployment"
    echo "2. Get test ETH from: https://www.alchemy.com/faucets/base-sepolia"
    echo "3. Add your private key to .env"
    exit 1
fi

if [ -z "$PLATFORM_TREASURY" ] || [ "$PLATFORM_TREASURY" == "0x_YOUR_DEPLOYER_ADDRESS" ]; then
    echo -e "${YELLOW}⚠️  PLATFORM_TREASURY not set, using deployer address${NC}"
    # Extract address from private key using cast
    PLATFORM_TREASURY=$(cast wallet address $DEPLOYER_PRIVATE_KEY)
    echo "Treasury address: $PLATFORM_TREASURY"
fi

# Set network
export NETWORK="base-sepolia"
export RPC_URL="https://sepolia.base.org"
export CHAIN_ID=84532
export USDC_ADDRESS="0x036CbD53842c5426634e7929541eC2318f3dCF7e"

echo -e "${GREEN}✅ Configuration OK${NC}"
echo ""
echo "Network: Base Sepolia"
echo "RPC URL: $RPC_URL"
echo "USDC: $USDC_ADDRESS"
echo "Treasury: $PLATFORM_TREASURY"
echo ""

# Check balance
echo "💰 Checking deployer balance..."
DEPLOYER_ADDRESS=$(cast wallet address $DEPLOYER_PRIVATE_KEY)
BALANCE=$(cast balance $DEPLOYER_ADDRESS --rpc-url $RPC_URL)
BALANCE_ETH=$(echo "scale=4; $BALANCE / 1000000000000000000" | bc)

echo "Deployer: $DEPLOYER_ADDRESS"
echo "Balance: $BALANCE_ETH ETH"

if (( $(echo "$BALANCE_ETH < 0.0005" | bc -l) )); then
    echo -e "${RED}❌ Insufficient ETH balance!${NC}"
    echo "You need at least 0.0005 ETH for deployment."
    echo "Get test ETH from: https://www.alchemy.com/faucets/base-sepolia"
    exit 1
fi

echo -e "${GREEN}✅ Balance sufficient${NC}"
echo ""

# Deploy contracts
echo "🚀 Deploying X402InsuranceV3..."
echo "--------------------------------"

cd contracts

# Export variables for Foundry script
export PRIVATE_KEY=$DEPLOYER_PRIVATE_KEY
export USDC_ADDRESS=$USDC_ADDRESS
export PLATFORM_TREASURY=$PLATFORM_TREASURY

# Run deployment
forge script script/DeployInsuranceV3.s.sol:DeployInsuranceV3 \
    --rpc-url $RPC_URL \
    --broadcast \
    --legacy \
    -vvv

# Check if deployment was successful
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Deployment failed!${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ Deployment successful!${NC}"
echo ""

# Extract deployed address from broadcast files
BROADCAST_FILE="broadcast/DeployInsuranceV3.s.sol/$CHAIN_ID/run-latest.json"
if [ -f "$BROADCAST_FILE" ]; then
    INSURANCE_ADDRESS=$(cat $BROADCAST_FILE | jq -r '.transactions[0].contractAddress')

    if [ ! -z "$INSURANCE_ADDRESS" ] && [ "$INSURANCE_ADDRESS" != "null" ]; then
        echo "📝 Contract deployed at: $INSURANCE_ADDRESS"
        echo ""

        # Update .env file
        echo "Updating .env file..."
        if grep -q "INSURANCE_V3_ADDRESS=" ../.env; then
            sed -i.bak "s/INSURANCE_V3_ADDRESS=.*/INSURANCE_V3_ADDRESS=$INSURANCE_ADDRESS/" ../.env
        else
            echo "INSURANCE_V3_ADDRESS=$INSURANCE_ADDRESS" >> ../.env
        fi

        echo -e "${GREEN}✅ Updated INSURANCE_V3_ADDRESS in .env${NC}"
    fi
fi

cd ..

echo ""
echo "========================================="
echo "🎉 Deployment Complete!"
echo "========================================="
echo ""
echo "Contract Address: $INSURANCE_ADDRESS"
echo "Explorer: https://sepolia.basescan.org/address/$INSURANCE_ADDRESS"
echo ""
echo "📝 Next Steps:"
echo "1. Verify contract on Basescan:"
echo "   forge verify-contract --chain-id 84532 $INSURANCE_ADDRESS X402InsuranceV3"
echo ""
echo "2. Register test providers:"
echo "   ./scripts/register-test-providers.sh"
echo ""
echo "3. Start services:"
echo "   npm run services:start"
echo ""
echo "4. Test the system:"
echo "   npm run test:e2e"
echo ""
echo "✨ Your X402 Insurance system is ready on Base Sepolia!"