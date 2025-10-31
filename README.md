# x402: BNTR Protocol - EVM Implementation

> Refund, Rewired — Autonomous Trust for the Micropayment Age

Smart contract implementation for Ethereum, Base, Optimism, Arbitrum, and other EVM chains.

## 🌟 Features

- **Zero Insurance Fees**: Clients pay only for services
- **Provider Bonds**: Automatic compensation from provider collateral
- **Time-Based Liquidation**: 7-day grace period for underfunded providers
- **EIP-712 Signatures**: Gas-efficient service confirmation
- **Multi-Chain**: Deploy on any EVM-compatible chain

---

## 🏗️ Architecture

```
contracts/
├── src/
│   ├── X402InsuranceV2.sol     # Main insurance contract
│   ├── BondedEscrow.sol        # Basic escrow (V1)
│   ├── BondedEscrowV2.sol      # Enhanced escrow with timeout
│   └── EscrowFactory.sol       # Factory for creating escrows
├── test/
│   └── X402InsuranceV2.t.sol   # Comprehensive tests
└── script/
    └── DeployInsuranceV2.s.sol # Deployment script
```

---

## 🚀 Quick Start

### Prerequisites

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install Node.js 18+
nvm install 18
nvm use 18
```

### 1. Install Dependencies

```bash
cd contracts
forge install
```

### 2. Configure Environment

```bash
cp .env.example .env
```

Edit `.env`:
```bash
PRIVATE_KEY=your_testnet_private_key
RPC_URL=https://sepolia.base.org
USDC_ADDRESS=0x036CbD53842c5426634e7929541eC2318f3dCF7e  # Base Sepolia
PLATFORM_TREASURY=your_treasury_address
PLATFORM_PENALTY_RATE=200  # 2%
DEFAULT_TIMEOUT=5          # minutes
```

### 3. Run Tests

```bash
forge test -vvv
```

### 4. Deploy Contract

```bash
forge script script/DeployInsuranceV2.s.sol:DeployInsuranceV2 \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

---

## 📝 Smart Contracts

### X402InsuranceV2.sol

Main insurance contract with zero-fee model.

**Key Functions:**
- `depositBond(uint256 amount)` - Provider deposits collateral
- `withdrawBond(uint256 amount)` - Provider withdraws (must maintain min)
- `purchaseInsurance()` - Client locks protection (no fee!)
- `confirmService()` - Provider confirms delivery
- `claimInsurance()` - Client claims compensation after timeout
- `warnProvider()` - Trigger liquidation warning
- `liquidateProvider()` - Liquidate underfunded provider

**Features:**
- ✅ Zero insurance fees for clients
- ✅ 2% penalty on failures
- ✅ 7-day liquidation grace period
- ✅ EIP-712 signature verification
- ✅ Multi-provider support

---

## 🧪 Testing

### Run All Tests
```bash
forge test -vvv
```

### Run Specific Test
```bash
forge test --match-test test_ClaimInsurance -vvv
```

### Gas Report
```bash
forge test --gas-report
```

### Coverage
```bash
forge coverage
```

---

## 🔄 Integration Example

### 1. Provider Deposits Bond

```javascript
import { ethers } from 'ethers';

const insurance = new ethers.Contract(INSURANCE_ADDRESS, ABI, signer);
const usdc = new ethers.Contract(USDC_ADDRESS, ERC20_ABI, signer);

// Approve
await usdc.approve(INSURANCE_ADDRESS, ethers.parseUnits("1000", 6));

// Deposit 1000 USDC
await insurance.depositBond(ethers.parseUnits("1000", 6));
```

### 2. Client Purchases Insurance

```javascript
// After x402 payment completes
const requestCommitment = ethers.keccak256(
  ethers.AbiCoder.defaultAbiCoder().encode(
    ['string', 'string', 'string', 'string'],
    [method, url, xpay, window]
  )
);

await insurance.purchaseInsurance(
  requestCommitment,
  providerAddress,
  ethers.parseUnits("1", 6),  // 1 USDC payment
  5  // 5 minute timeout
);
```

### 3. Provider Confirms Service

```javascript
const domain = {
  name: 'X402InsuranceV2',
  version: '1',
  chainId: 84532,
  verifyingContract: INSURANCE_ADDRESS
};

const types = {
  ServiceConfirmation: [
    { name: 'requestCommitment', type: 'bytes32' }
  ]
};

const value = { requestCommitment };

const signature = await signer.signTypedData(domain, types, value);

await insurance.confirmService(requestCommitment, signature);
```

### 4. Client Claims (if timeout)

```javascript
// Wait for timeout period
await insurance.claimInsurance(requestCommitment);
```

---

## 🧾 On-Chain Test Scripts

Test the full flow on Base Sepolia:

```bash
# Test success scenario
bash test-success-simple.sh

# Test failure + claim scenario
bash test-complete-success-flow.sh
```

---

## 🔐 Security

### Audit Status
⚠️ **NOT AUDITED** - For testnet use only

### Known Considerations
1. **Reentrancy**: Protected via OpenZeppelin SafeERC20
2. **EIP-712 Signatures**: Requires proper key management
3. **Bond Management**: Providers must monitor levels
4. **Liquidation**: 7-day grace period is configurable

### Responsible Disclosure
Found a security issue? Email: security@[your-domain].com

Do NOT open public issues for vulnerabilities.

---

## 📊 Gas Costs

| Function | Gas (approx) |
|----------|--------------|
| depositBond | ~90k |
| purchaseInsurance | ~220k |
| confirmService | ~230k |
| claimInsurance | ~270k |
| liquidateProvider | ~170k |

*Costs on Base Sepolia. May vary by chain and network conditions.*

---

## 🌐 Supported Networks

- ✅ **Base** (Mainnet & Sepolia)
- ✅ **Ethereum** (Mainnet & Sepolia)
- ✅ **Optimism**
- ✅ **Arbitrum**
- ✅ Any EVM-compatible chain

---

## 📚 Additional Resources

- [Business Model](../docs/BUSINESS_MODEL.md)
- [X402 Insurance V2 Guide](../docs/X402_INSURANCE_V2_GUIDE.md)
- [Security Audit Report](../../SECURITY_AUDIT_REPORT.md)
- [Scenario Comparison](../../SCENARIO_COMPARISON.md)

---

## 📄 License

**GPL-3.0** - GNU General Public License v3.0

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

See the [LICENSE](LICENSE) file for details.

---

## 🤝 Contributing

Contributions welcome! Please see [CONTRIBUTING.md](../../CONTRIBUTING.md)

---

**Built with**
Solidity · Foundry · OpenZeppelin · EIP-712 · Base
