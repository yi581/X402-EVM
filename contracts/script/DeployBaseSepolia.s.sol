// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "../src/BondedEscrow.sol";

/**
 * @title DeployBaseSepolia
 * @notice Deployment script for Base Sepolia testnet
 * @dev Uses existing USDC contract on Base Sepolia
 */
contract DeployBaseSepolia is Script {
    // Base Sepolia USDC (official address)
    address constant USDC_ADDRESS = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    // Seller address (Server wallet)
    address constant SELLER_ADDRESS = 0x11a04550Cb4e281E3a62a6e4f37F4E8B480b0DAf;

    // Minimum bond: 5 USDC (6 decimals)
    // This allows deploying with just 10 USDC (5 for bond + 5 buffer)
    uint256 constant MIN_BOND = 5_000_000;

    function run() external {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("========================================");
        console.log("Base Sepolia Deployment");
        console.log("========================================");
        console.log("Deployer:", deployer);
        console.log("USDC Address:", USDC_ADDRESS);
        console.log("Seller Address:", SELLER_ADDRESS);
        console.log("Min Bond:", MIN_BOND, "(10 USDC)");
        console.log("========================================\n");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy BondedEscrow contract
        BondedEscrow escrow = new BondedEscrow(
            USDC_ADDRESS,
            SELLER_ADDRESS,
            MIN_BOND
        );

        vm.stopBroadcast();

        console.log("\n========================================");
        console.log("Deployment Complete!");
        console.log("========================================");
        console.log("BondedEscrow:", address(escrow));
        console.log("Owner:", escrow.owner());
        console.log("Seller:", escrow.sellerAddress());
        console.log("Token:", address(escrow.token()));
        console.log("Min Bond:", escrow.minBond());
        console.log("========================================\n");

        console.log("Next Steps:");
        console.log("1. Update services/.env:");
        console.log("   BOND_ESCROW_ADDRESS=%s", address(escrow));
        console.log("\n2. Approve USDC for BondedEscrow:");
        console.log("   cast send %s \"approve(address,uint256)\" %s 8000000 --rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY", USDC_ADDRESS, address(escrow));
        console.log("\n3. Deposit bond:");
        console.log("   cast send %s \"deposit(uint256)\" 8000000 --rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY", address(escrow));
        console.log("\n4. Verify bond:");
        console.log("   cast call %s \"getBondBalance()\" --rpc-url $RPC_URL", address(escrow));
        console.log("========================================\n");
    }
}
