// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "../src/X402Insurance.sol";

/**
 * @title DeployInsurance
 * @notice 部署 X402Insurance 合约
 *
 * Usage:
 * forge script script/DeployInsurance.s.sol:DeployInsurance \
 *   --rpc-url $RPC_URL \
 *   --broadcast \
 *   --verify
 */
contract DeployInsurance is Script {
    function run() external {
        // 从环境变量读取配置
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        address platformTreasury = vm.envAddress("PLATFORM_TREASURY");
        uint256 platformFeeRate = vm.envOr("INSURANCE_FEE_RATE", uint256(1000)); // 默认 10%
        uint256 defaultTimeout = vm.envOr("DEFAULT_TIMEOUT", uint256(5)); // 默认 5 分钟

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // 部署 X402Insurance
        X402Insurance insurance = new X402Insurance(
            usdcAddress,
            platformTreasury,
            platformFeeRate,
            defaultTimeout
        );

        console.log("============================================================");
        console.log("X402Insurance deployed successfully!");
        console.log("============================================================");
        console.log("");
        console.log("Contract Address:", address(insurance));
        console.log("USDC Address:", usdcAddress);
        console.log("Platform Treasury:", platformTreasury);
        console.log("Platform Fee Rate (bp):", platformFeeRate);
        console.log("Default Timeout (min):", defaultTimeout);
        console.log("");
        console.log("============================================================");
        console.log("Next steps:");
        console.log("1. Add X402_INSURANCE_ADDRESS to .env");
        console.log("2. Service providers deposit bond: insurance.depositBond()");
        console.log("3. Clients can purchase insurance on x402 payments");
        console.log("4. Update services/.env with insurance address");
        console.log("============================================================");

        vm.stopBroadcast();
    }
}
