// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "../src/EscrowFactory.sol";

/**
 * @title DeployFactory
 * @notice 部署 EscrowFactory 合约脚本
 *
 * Usage:
 * forge script script/DeployFactory.s.sol:DeployFactory \
 *   --rpc-url $RPC_URL \
 *   --broadcast \
 *   --verify
 */
contract DeployFactory is Script {
    function run() external {
        // 从环境变量读取配置
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        address platformTreasury = vm.envAddress("PLATFORM_TREASURY");
        uint256 defaultFeeRate = vm.envOr("DEFAULT_FEE_RATE", uint256(200)); // 默认 2%
        uint256 defaultMinBond = vm.envOr("DEFAULT_MIN_BOND", uint256(100_000_000)); // 默认 100 USDC

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // 部署 EscrowFactory
        EscrowFactory factory = new EscrowFactory(
            usdcAddress,
            platformTreasury,
            defaultFeeRate,
            defaultMinBond
        );

        console.log("============================================================");
        console.log("EscrowFactory deployed successfully!");
        console.log("============================================================");
        console.log("");
        console.log("Contract Address:", address(factory));
        console.log("USDC Address:", usdcAddress);
        console.log("Platform Treasury:", platformTreasury);
        console.log("Default Fee Rate (bp):", defaultFeeRate);
        console.log("Default Min Bond:", defaultMinBond);
        console.log("");
        console.log("============================================================");
        console.log("Next steps:");
        console.log("1. Add ESCROW_FACTORY_ADDRESS to .env");
        console.log("2. Service providers can now call factory.createEscrow()");
        console.log("3. Update services/.env with factory address");
        console.log("============================================================");

        vm.stopBroadcast();
    }
}
