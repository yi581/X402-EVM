// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "../test/BondedEscrow.t.sol";
import "../src/BondedEscrow.sol";

contract DeployAll is Script {
    function run() external {
        // Use Anvil's first default account
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy MockUSDC
        MockUSDC usdc = new MockUSDC();
        console.log("MockUSDC deployed at:", address(usdc));
        
        // Use second Anvil account as seller
        address seller = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        
        // Deploy BondedEscrow with 10 USDC min bond
        uint256 minBond = 10_000_000; // 10 USDC (6 decimals)
        BondedEscrow escrow = new BondedEscrow(
            address(usdc),
            seller,
            minBond
        );
        
        console.log("");
        console.log("========================================");
        console.log("Deployment Complete!");
        console.log("========================================");
        console.log("MockUSDC:", address(usdc));
        console.log("BondedEscrow:", address(escrow));
        console.log("Seller Address:", seller);
        console.log("Min Bond:", minBond, "(10 USDC)");
        console.log("========================================");
        
        // Mint some USDC to test accounts
        address account1 = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // Anvil account 0
        address account2 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // Anvil account 1
        address account3 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // Anvil account 2
        
        usdc.mint(account1, 1000_000_000); // 1000 USDC
        usdc.mint(account2, 1000_000_000); // 1000 USDC
        usdc.mint(account3, 1000_000_000); // 1000 USDC
        
        console.log("Minted 1000 USDC to:", account1);
        console.log("Minted 1000 USDC to:", account2);
        console.log("Minted 1000 USDC to:", account3);
        
        vm.stopBroadcast();
    }
}
