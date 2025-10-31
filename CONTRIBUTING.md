# Contributing to X402 Refund System

Thank you for your interest in contributing! This document provides guidelines for contributing to the project.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/your-username/X402.git`
3. Create a feature branch: `git checkout -b feature/your-feature-name`
4. Make your changes
5. Test thoroughly
6. Submit a pull request

## Development Setup

See [SETUP.md](SETUP.md) for detailed setup instructions.

Quick start:
```bash
pnpm install
cd contracts && forge install
```

## Code Style

### Solidity
- Follow [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- Use NatSpec comments for all public functions
- Maximum line length: 120 characters
- Use descriptive variable names

### TypeScript
- Use TypeScript strict mode
- Follow ESLint rules (if configured)
- Use async/await over promises
- Add JSDoc comments for public APIs

## Testing

### Smart Contracts
```bash
cd contracts
forge test -vvv
```

All contract changes must include tests.

### Services
```bash
cd services
pnpm typecheck
```

## Pull Request Guidelines

1. **Title**: Use descriptive titles
   - Good: "Add multi-token support to BondedEscrow"
   - Bad: "Fix bug"

2. **Description**: Include:
   - What changed
   - Why it changed
   - How to test
   - Any breaking changes

3. **Commits**:
   - Use conventional commits format
   - Examples:
     - `feat: add timeout-based refunds`
     - `fix: prevent signature replay attack`
     - `docs: update API documentation`
     - `test: add edge cases for claimRefund`

4. **Tests**: Include tests for new features

5. **Documentation**: Update relevant docs

## Feature Proposals

For major changes:

1. Open an issue first to discuss
2. Describe the problem you're solving
3. Propose your solution
4. Wait for maintainer feedback

## Bug Reports

Include:
- Clear description
- Steps to reproduce
- Expected vs actual behavior
- Environment details (OS, Node version, etc.)
- Logs/screenshots if applicable

## Security Issues

**Do not** open public issues for security vulnerabilities.

Instead:
- Email maintainers privately
- Include detailed description
- Provide proof of concept if possible

## Areas for Contribution

### High Priority
- [ ] Contract security audits
- [ ] Comprehensive test coverage
- [ ] Multi-chain support
- [ ] Error handling improvements
- [ ] Documentation improvements

### Medium Priority
- [ ] Multi-token support (ETH, DAI)
- [ ] Timeout-based refunds
- [ ] Admin dashboard
- [ ] Monitoring/alerting
- [ ] Rate limiting

### Low Priority
- [ ] UI for escrow management
- [ ] GraphQL API
- [ ] Subgraph integration
- [ ] SDK development

## Code Review Process

1. Maintainer reviews within 3-5 days
2. Address feedback
3. Re-request review
4. Merge after approval

## Release Process

1. Update version numbers
2. Update CHANGELOG.md
3. Tag release
4. Deploy to testnet first
5. Announce in community channels

## Community

- Be respectful and inclusive
- Follow [Code of Conduct](CODE_OF_CONDUCT.md) (if exists)
- Help others in issues/discussions
- Share knowledge and learnings

## Questions?

- Open a discussion on GitHub
- Check existing issues
- Review documentation

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to making decentralized refunds better!
