# Security Policy

## Reporting a Vulnerability

We take security seriously. If you discover a security vulnerability in the X402 Insurance Protocol, please help us protect our users by following responsible disclosure practices.

### How to Report

**DO NOT** create a public GitHub issue for security vulnerabilities.

Instead, please email:
- **Email**: security@[your-domain].com
- **Subject**: "Security Vulnerability: X402 Insurance Protocol"

### What to Include

1. **Description**: Detailed explanation of the vulnerability
2. **Impact**: Potential consequences and severity
3. **Steps to Reproduce**: Clear instructions to verify the issue
4. **Proof of Concept**: Code or transaction examples (if applicable)
5. **Suggested Fix**: Optional but appreciated
6. **Your Contact**: How we can reach you for follow-up

### Response Timeline

- **Acknowledgment**: Within 48 hours
- **Initial Assessment**: Within 7 days
- **Fix Development**: Depends on severity (1-30 days)
- **Disclosure**: After fix deployment (coordinated disclosure)

### Severity Classification

| Severity | Description | Bounty Range |
|----------|-------------|--------------|
| **Critical** | Funds can be stolen, protocol broken | TBD |
| **High** | Economic attacks, griefing, DoS | TBD |
| **Medium** | Business logic flaws, edge cases | TBD |
| **Low** | Informational, best practice improvements | Recognition |

### Scope

#### In Scope

- Smart contracts in `contracts/src/`
- Economic model exploits
- Signature verification bypass
- Bond manipulation
- Access control issues
- Reentrancy attacks
- Integer overflow/underflow
- Logic errors

#### Out of Scope

- Off-chain services (future development)
- Test scripts
- Documentation typos
- Already known issues
- Issues in third-party dependencies (report to them directly)

### Bug Bounty Program

**Status**: Not yet active (pending audit & mainnet launch)

We plan to launch a bug bounty program after:
1. Professional security audit
2. Mainnet deployment
3. TVL reaches $100k+

### Known Limitations

The following are known and considered acceptable risks:

1. **No Audit**: Contracts have NOT been audited
2. **Testnet Only**: Not intended for mainnet production use yet
3. **Bond Exhaustion**: Providers can run out of bond
4. **Timeout Accuracy**: Block timestamp dependency
5. **Gas Price Volatility**: EIP-712 confirmation costs vary

### Security Best Practices for Users

#### For Service Providers

- Monitor bond levels regularly
- Use hardware wallets for private keys
- Never share private keys
- Set appropriate `minProviderBond` thresholds
- Test on testnet before mainnet

#### For Clients

- Verify contract addresses before interaction
- Start with small test payments
- Monitor timeout periods
- Keep transaction receipts
- Use reputable providers

#### For Platform Operators

- Use multisig for `platformTreasury`
- Implement monitoring and alerts
- Regular security reviews
- Incident response plan
- Regular backups of critical data

### Security Audits

**Current Status**: ⚠️ NOT AUDITED

**Planned Audits**:
- [ ] Internal review
- [ ] Community review
- [ ] Professional audit (planned)
- [ ] Formal verification (future)

### Hall of Fame

Security researchers who responsibly disclose vulnerabilities will be recognized here:

- TBD (be the first!)

### Disclaimer

This protocol is experimental and provided "as is" without warranties. Users assume all risks including but not limited to:

- Smart contract bugs
- Economic exploits  
- Network failures
- Loss of funds
- Regulatory risks

**DO NOT** use this protocol with funds you cannot afford to lose.

### Contact

For non-security issues:
- GitHub Issues: https://github.com/your-username/X402/issues
- Email: team@[your-domain].com

---

Thank you for helping keep X402 Insurance Protocol secure!
