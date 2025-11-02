// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "../src/X402InsuranceV3.sol";

/**
 * @title DeployInsuranceV3
 * @notice 部署X402InsuranceV3合约的脚本
 * @dev 使用方法：
 * forge script script/DeployInsuranceV3.s.sol:DeployInsuranceV3 \
 *   --rpc-url $RPC_URL \
 *   --broadcast \
 *   --verify
 */
contract DeployInsuranceV3 is Script {
    function setUp() public {}

    function run() public {
        // 从环境变量读取配置
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        address platformTreasury = vm.envAddress("PLATFORM_TREASURY");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("========================================");
        console.log("Deploying X402InsuranceV3...");
        console.log("========================================");
        console.log("USDC Address:", usdcAddress);
        console.log("Platform Treasury:", platformTreasury);

        // 开始广播交易
        vm.startBroadcast(deployerPrivateKey);

        // 部署合约
        X402InsuranceV3 insurance = new X402InsuranceV3(
            usdcAddress,
            platformTreasury
        );

        console.log("========================================");
        console.log("X402InsuranceV3 deployed at:", address(insurance));
        console.log("========================================");

        // 输出关键信息
        console.log("\nContract Configuration:");
        console.log("- USDC Token:", address(insurance.usdcToken()));
        console.log("- Platform Treasury:", insurance.platformTreasury());
        console.log("- Lock Period:", insurance.LOCK_PERIOD(), "seconds (24 hours)");
        console.log("- Penalty Rate:", insurance.PENALTY_RATE(), "basis points (2%)");
        console.log("- Min Pool Balance:", insurance.MIN_POOL_BALANCE() / 10**6, "USDC");

        console.log("\nProvider Tiers:");
        console.log("- Bronze: 100-500 USDC");
        console.log("- Silver: 500-1000 USDC");
        console.log("- Gold: 1000-5000 USDC");
        console.log("- Platinum: 5000+ USDC");

        console.log("\nNext Steps:");
        console.log("1. Save the contract address");
        console.log("2. Update services/abi/X402InsuranceV3.json");
        console.log("3. Configure backend services");
        console.log("4. Register providers");

        vm.stopBroadcast();
    }
}