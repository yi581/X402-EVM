# X402 Insurance Layer - EVM Implementation

> Zero-Fee Insurance for X402 Payments

Smart contract implementation of X402 Insurance Protocol on Base Sepolia testnet.

## Features

- **Zero Insurance Fees** - Clients pay nothing for insurance coverage
- **Instant Claims** - Immediate claim processing with proportional compensation
- **Delayed Compensation** - Automatic compensation tracking and distribution
- **Provider Tiers** - Bronze/Silver/Gold tier system
- **Three-Layer Pool** - Provider Pool → Emergency Pool → Platform Fund
- **Dispute Mechanism** - Time-based dispute periods for fair resolution
- **Multi-Provider Support** - Support for individual and contract providers

---

## Deployed Contracts

### Base Sepolia Testnet

| Contract | Address | Explorer |
|----------|---------|----------|
| **InsuranceV8** | `0x72486eF40BB3729298369d608de85c612adb223e` | [View](https://sepolia.basescan.org/address/0x72486eF40BB3729298369d608de85c612adb223e) |
| **ProviderFactory** | `0xbed30550aB282bED6A6ED57F23E9C99FAd8b7b76` | [View](https://sepolia.basescan.org/address/0xbed30550aB282bED6A6ED57F23E9C99FAd8b7b76) |
| **USDC (Test)** | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` | [View](https://sepolia.basescan.org/address/0x036CbD53842c5426634e7929541eC2318f3dCF7e) |

**Network**: Base Sepolia
**Chain ID**: 84532
**RPC**: https://sepolia.base.org

---

## Quick Start

### Prerequisites

```bash
# Install Node.js 18+
nvm install 18
nvm use 18

# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Installation

```bash
# Clone repository
git clone https://github.com/yourusername/X402-EVM.git
cd X402-EVM

# Install dependencies
npm install

# Install Forge dependencies
cd contracts
forge install
```

### Configuration

```bash
# Copy environment file
cp .env.example .env
```

Edit `.env`:
```bash
PRIVATE_KEY=your_private_key
RPC_URL=https://sepolia.base.org
INSURANCE_V8_ADDRESS=0x72486eF40BB3729298369d608de85c612adb223e
USDC_ADDRESS=0x036CbD53842c5426634e7929541eC2318f3dCF7e
```

---

## Provider Onboarding

X402 Insurance supports **3 ways** to become a provider:

### Method 1: Direct Wallet Registration (Simplest)

```javascript
const { ethers } = require('ethers');

// Approve USDC
await usdc.approve(insuranceAddress, amount);

// Register as provider
await insurance.registerOrReactivate(amount);
```

**Best for**: Individuals, small projects, quick testing

### Method 2: ProviderFactory (Recommended)

```javascript
// Approve USDC
await usdc.approve(factoryAddress, amount);

// Create provider contract
const tx = await factory.createProvider(amount);
const receipt = await tx.wait();

// Get your provider contract address
const event = receipt.logs.find(log => log.eventName === 'ProviderCreated');
const providerAddress = event.args.providerContract;
```

**Best for**: Projects wanting automation, no business contract modifications needed

**Advantages**:
- Automatic provider contract deployment
- Auto-registration to Insurance V8
- Can implement automated claim handling
- No manual contract deployment required

### Method 3: Business Contract Integration (Advanced)

```solidity
contract YourBusinessContract {
    function enableInsurance(uint256 amount) external onlyOwner {
        IERC20(USDC).approve(INSURANCE_V8, amount);
        IInsurance(INSURANCE_V8).registerOrReactivate(amount);
    }

    function handleClaim(bytes32 claimId, bytes32 orderId) external {
        if (orders[orderId].delivered) {
            IInsurance(INSURANCE_V8).disputeClaim(claimId, "Order delivered");
        }
    }
}
```

**Best for**: Deep integration needs, custom business logic

See [SIMPLE_PROVIDER_ONBOARDING.md](docs/SIMPLE_PROVIDER_ONBOARDING.md) for detailed guide.

---

## Client Usage

### Initiate Claim

```javascript
const commitment = ethers.keccak256(ethers.toUtf8Bytes('claim-' + Date.now()));

await insurance.initiateClaim(
    commitment,
    providerAddress,
    ethers.parseUnits('10', 6), // 10 USDC
    0 // ClaimReason.NOT_DELIVERED
);
```

### Execute Claim

```javascript
// Wait for dispute period to pass
await new Promise(resolve => setTimeout(resolve, 65000)); // 1 min for small amounts

// Execute claim
await insurance.executeClaim(commitment);

// Check result
const claimInfo = await insurance.getClaimInfo(commitment);
console.log('Paid:', ethers.formatUnits(claimInfo.paidAmount, 6), 'USDC');
console.log('Pending:', ethers.formatUnits(claimInfo.pendingAmount, 6), 'USDC');
```

---

## Core Features

### Insurance V8 Capabilities

- **Instant Claims** - Clients can initiate claims immediately
- **Dispute Periods** - Provider has time to dispute unfair claims
- **Proportional Payment** - Pays proportionally when funds are insufficient
- **Delayed Compensation** - Automatically tracks unpaid amounts
- **Auto Compensation** - Automatic compensation when provider refills
- **Three-Tier Pools** - Provider Pool → Emergency Pool → Platform Fund
- **Provider Tiers** - Bronze (10 USDC), Silver (100 USDC), Gold (1000 USDC)

### Dispute Period Rules

| Claim Amount | Dispute Period |
|--------------|----------------|
| ≤ 10 USDC | 1 minute |
| ≤ 100 USDC | 5 minutes |
| ≤ 1000 USDC | 15 minutes |
| > 1000 USDC | 30 minutes |

---

## Testing

### Run Tests

```bash
cd contracts
forge test -vvv
```

### Run Specific Test

```bash
forge test --match-test test_ProportionalPayment -vvv
```

### Test on Base Sepolia

```bash
# Test provider factory
node scripts/test-provider-factory.js

# Test complete flow
node scripts/test-factory-complete-flow.js

# Test provider recharge
node scripts/test-provider-recharge.js
```

---

## Documentation

### Core Documentation
- [DEPLOYMENT_COMPLETE.md](DEPLOYMENT_COMPLETE.md) - Complete deployment guide
- [SIMPLE_PROVIDER_ONBOARDING.md](docs/SIMPLE_PROVIDER_ONBOARDING.md) - Provider onboarding (3 methods)
- [FRONTEND_INTEGRATION_GUIDE.md](docs/FRONTEND_INTEGRATION_GUIDE.md) - Complete API documentation
- [FACTORY_TEST_REPORT.md](FACTORY_TEST_REPORT.md) - Real testnet test results

### Integration Guides
- [BUSINESS_CONTRACT_INSURANCE_INTEGRATION.md](docs/BUSINESS_CONTRACT_INSURANCE_INTEGRATION.md) - Business contract integration
- [CONTRACT_PROVIDER_GUIDE.md](docs/CONTRACT_PROVIDER_GUIDE.md) - Smart contract provider guide
- [CONTRACT_PROVIDER_SOLUTION.md](docs/CONTRACT_PROVIDER_SOLUTION.md) - Technical solution details

### SDK and Tools
- JavaScript SDK: `/frontend/sdk/X402InsuranceSDK.js`
- Simple Provider SDK: `/frontend/sdk/X402ProviderSimpleSDK.js`
- TypeScript Types: `/frontend/types/insurance.ts`
- Contract ABIs: `/frontend/abi/`

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│              X402 Insurance Layer               │
└─────────────────────────────────────────────────┘
                      │
        ┌─────────────┼─────────────┐
        │             │             │
   ┌────▼────┐   ┌────▼────┐  ┌────▼────┐
   │Insurance│   │Provider │  │ Client  │
   │   V8    │   │ Factory │  │   SDK   │
   └─────────┘   └─────────┘  └─────────┘
        │             │             │
   ┌────▼─────────────▼─────────────▼────┐
   │        Base Sepolia Testnet         │
   └─────────────────────────────────────┘
```

---

## Smart Contracts

### X402InsuranceV8.sol

Main insurance contract with delayed compensation mechanism.

**Key Functions:**
- `registerOrReactivate(uint256 amount)` - Register/reactivate as provider
- `depositAdditional(uint256 amount)` - Add funds to provider pool
- `withdraw(uint256 amount)` - Withdraw available funds
- `initiateClaim(...)` - Client initiates claim
- `executeClaim(bytes32 commitment)` - Execute claim after dispute period
- `disputeClaim(bytes32 commitment, string memory evidence)` - Provider disputes claim

### ProviderFactory.sol

One-click provider deployment factory.

**Key Functions:**
- `createProvider(uint256 initialDeposit)` - Deploy new provider contract
- `getUserProviders(address user)` - Get user's provider contracts
- `getAllProviders()` - Get all deployed providers

### ProviderContractInterface.sol

Simple provider contract template.

**Key Functions:**
- `depositInsurance(uint256 amount)` - Deposit to insurance pool
- `withdrawFromInsurance(uint256 amount)` - Withdraw from pool

---

## Gas Costs

| Operation | Gas (approx) | Estimated Cost (Base L2) |
|-----------|--------------|-------------------------|
| Register Provider | ~95,000 | ~$0.001 |
| Create via Factory | ~840,000 | ~$0.01 |
| Initiate Claim | ~80,000 | ~$0.0008 |
| Execute Claim | ~105,000 | ~$0.001 |
| Dispute Claim | ~50,000 | ~$0.0005 |

*Costs on Base Sepolia. Actual costs may vary.*

---

## Security

### Audit Status
**NOT AUDITED** - Testnet only, do not use in production

### Security Features
- Non-reentrant functions
- Strict balance management
- Event logging for all operations
- Dispute mechanism
- Emergency pause capability
- Tiered access control

### Responsible Disclosure
Found a security issue? Please report privately:
- Email: security@[your-domain].com
- **DO NOT** open public issues for vulnerabilities

See [SECURITY.md](SECURITY.md) for details.

---

## Contributing

Contributions welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md)

---

## License

**GPL-3.0** - GNU General Public License v3.0

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

See the [LICENSE](LICENSE) file for details.

---

## Support

- GitHub Issues: https://github.com/yourusername/X402-EVM/issues
- Documentation: `/docs` directory
- Examples: `/contracts/src/examples`

---

**Built with**
Solidity · Foundry · OpenZeppelin · Ethers.js · Base L2
