// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "../src/X402InsuranceV2.sol";

/**
 * @title DeployInsuranceV2
 * @notice 部署 X402InsuranceV2 合约（零保险费模式）
 *
 * Usage:
 * forge script script/DeployInsuranceV2.s.sol:DeployInsuranceV2 \
 *   --rpc-url $RPC_URL \
 *   --broadcast \
 *   --verify
 */
contract DeployInsuranceV2 is Script {
    function run() external {
        // 从环境变量读取配置
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        address platformTreasury = vm.envAddress("PLATFORM_TREASURY");
        uint256 platformPenaltyRate = vm.envOr("PLATFORM_PENALTY_RATE", uint256(200)); // 默认 2%
        uint256 defaultTimeout = vm.envOr("DEFAULT_TIMEOUT", uint256(5)); // 默认 5 分钟

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // 部署 X402InsuranceV2
        X402InsuranceV2 insurance = new X402InsuranceV2(
            usdcAddress,
            platformTreasury,
            platformPenaltyRate,
            defaultTimeout
        );

        console.log("============================================================");
        console.log("X402InsuranceV2 deployed successfully!");
        console.log("============================================================");
        console.log("");
        console.log("Contract Address:", address(insurance));
        console.log("USDC Address:", usdcAddress);
        console.log("Platform Treasury:", platformTreasury);
        console.log("Platform Penalty Rate (bp):", platformPenaltyRate);
        console.log("Default Timeout (min):", defaultTimeout);
        console.log("");
        console.log("============================================================");
        console.log("Key Features:");
        console.log("- Zero insurance fee for clients");
        console.log("- 2% penalty on failed services");
        console.log("- Bond locking mechanism");
        console.log("- Provider health monitoring");
        console.log("============================================================");
        console.log("");
        console.log("Next steps:");
        console.log("1. Add X402_INSURANCE_V2_ADDRESS to .env");
        console.log("2. Service providers deposit bond: depositBond()");
        console.log("3. Platform sets min bond: setMinProviderBond()");
        console.log("4. Clients can purchase insurance (no fee!)");
        console.log("5. Update services/.env with V2 address");
        console.log("============================================================");

        vm.stopBroadcast();
    }
}
