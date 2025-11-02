#!/bin/bash

# Start Provider Registry API Service
# 启动Provider注册表API服务

echo "========================================="
echo "Starting Provider Registry API"
echo "========================================="
echo ""

# 检查环境变量
if [ ! -f ../.env ]; then
    echo "⚠️  Creating .env file from example..."
    cp ../.env.example ../.env
    echo "Please configure .env file with your settings"
fi

# 加载环境变量
source ../.env

# 设置默认值
export REGISTRY_PORT=${REGISTRY_PORT:-3005}
export BASE_SEPOLIA_RPC_URL=${BASE_SEPOLIA_RPC_URL:-"https://sepolia.base.org"}

echo "Configuration:"
echo "  Registry Port: $REGISTRY_PORT"
echo "  RPC URL: $BASE_SEPOLIA_RPC_URL"
echo ""

# 编译TypeScript
echo "Compiling TypeScript..."
npx tsc src/provider-registry-api.ts --outDir dist --module commonjs --target es2020 --esModuleInterop --skipLibCheck

# 启动服务
echo "Starting service..."
node dist/provider-registry-api.js