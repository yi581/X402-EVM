// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "../src/BondedEscrow.sol";

/**
 * @title DeployBondedEscrow
 * @notice Deployment script for BondedEscrow contract
 *
 * Usage:
 *   forge script script/Deploy.s.sol:DeployBondedEscrow --rpc-url $RPC_URL --broadcast
 *
 * Environment variables required:
 *   - PRIVATE_KEY: Deployer private key
 *   - USDC_ADDRESS: USDC token contract address
 *   - SELLER_ADDRESS: Service provider's signing address
 *   - MIN_BOND: Minimum bond amount (in wei)
 */
contract DeployBondedEscrow is Script {
    function run() external {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        address sellerAddress = vm.envAddress("SELLER_ADDRESS");
        uint256 minBond = vm.envUint("MIN_BOND");

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy BondedEscrow
        BondedEscrow escrow = new BondedEscrow(
            usdcAddress,
            sellerAddress,
            minBond
        );

        console.log("========================================");
        console.log("BondedEscrow Deployed!");
        console.log("========================================");
        console.log("Contract Address:", address(escrow));
        console.log("Owner:", escrow.owner());
        console.log("Token (USDC):", address(escrow.token()));
        console.log("Seller Address:", escrow.sellerAddress());
        console.log("Min Bond:", escrow.minBond());
        console.log("========================================");
        console.log("");
        console.log("Next steps:");
        console.log("1. Update BOND_ESCROW_ADDRESS in services/.env");
        console.log("2. Approve USDC: cast send %s 'approve(address,uint256)' %s <amount> --private-key $PRIVATE_KEY", usdcAddress, address(escrow));
        console.log("3. Deposit bond: cast send %s 'deposit(uint256)' <amount> --private-key $PRIVATE_KEY", address(escrow));
        console.log("========================================");

        vm.stopBroadcast();
    }
}
