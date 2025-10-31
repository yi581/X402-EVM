// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/X402Insurance.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockUSDC
 * @notice Mock USDC token for testing
 */
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        _mint(msg.sender, 1_000_000 * 10**6); // 1M USDC
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title X402InsuranceTest
 * @notice Comprehensive tests for X402Insurance contract
 */
contract X402InsuranceTest is Test {
    X402Insurance public insurance;
    MockUSDC public usdc;

    address public platformTreasury = address(0x1);
    address public provider = address(0x2);
    address public client = address(0x3);
    address public otherProvider = address(0x4);

    uint256 public platformFeeRate = 1000; // 10%
    uint256 public defaultTimeout = 5; // 5 minutes

    uint256 public providerPrivateKey = 0xA11CE;
    uint256 public clientPrivateKey = 0xB0B;

    event BondDeposited(address indexed provider, uint256 amount);
    event BondWithdrawn(address indexed provider, uint256 amount);
    event InsurancePurchased(
        bytes32 indexed requestCommitment,
        address indexed client,
        address indexed provider,
        uint256 paymentAmount,
        uint256 insuranceFee,
        uint256 deadline
    );
    event ServiceConfirmed(
        bytes32 indexed requestCommitment,
        address indexed provider,
        uint256 insuranceReward
    );
    event InsuranceClaimed(
        bytes32 indexed requestCommitment,
        address indexed client,
        uint256 compensationAmount
    );
    event PlatformFeeCollected(bytes32 indexed requestCommitment, uint256 amount);
    event MinBondUpdated(address indexed provider, uint256 oldBond, uint256 newBond);

    function setUp() public {
        // Deploy mock USDC
        usdc = new MockUSDC();

        // Deploy insurance contract
        insurance = new X402Insurance(
            address(usdc),
            platformTreasury,
            platformFeeRate,
            defaultTimeout
        );

        // Setup accounts
        provider = vm.addr(providerPrivateKey);
        client = vm.addr(clientPrivateKey);

        // Fund accounts
        usdc.mint(provider, 10_000 * 10**6); // 10,000 USDC
        usdc.mint(client, 10_000 * 10**6);    // 10,000 USDC
    }

    // =============================================================
    //                      BOND MANAGEMENT TESTS
    // =============================================================

    function test_DepositBond() public {
        uint256 bondAmount = 1000 * 10**6; // 1000 USDC

        vm.startPrank(provider);
        usdc.approve(address(insurance), bondAmount);

        vm.expectEmit(true, false, false, true);
        emit BondDeposited(provider, bondAmount);

        insurance.depositBond(bondAmount);
        vm.stopPrank();

        assertEq(insurance.providerBond(provider), bondAmount);
    }

    function test_RevertWhen_DepositZeroAmount() public {
        vm.startPrank(provider);
        vm.expectRevert(X402Insurance.InvalidAmount.selector);
        insurance.depositBond(0);
        vm.stopPrank();
    }

    function test_WithdrawBond() public {
        uint256 bondAmount = 1000 * 10**6; // 1000 USDC

        // Deposit bond
        vm.startPrank(provider);
        usdc.approve(address(insurance), bondAmount);
        insurance.depositBond(bondAmount);

        // Withdraw bond
        uint256 withdrawAmount = 500 * 10**6; // 500 USDC

        vm.expectEmit(true, false, false, true);
        emit BondWithdrawn(provider, withdrawAmount);

        insurance.withdrawBond(withdrawAmount);
        vm.stopPrank();

        assertEq(insurance.providerBond(provider), bondAmount - withdrawAmount);
    }

    function test_RevertWhen_WithdrawBelowMinBond() public {
        uint256 bondAmount = 1000 * 10**6; // 1000 USDC
        uint256 minBond = 800 * 10**6;     // 800 USDC

        // Set min bond
        vm.prank(platformTreasury);
        insurance.setMinProviderBond(provider, minBond);

        // Deposit bond
        vm.startPrank(provider);
        usdc.approve(address(insurance), bondAmount);
        insurance.depositBond(bondAmount);

        // Try to withdraw too much
        uint256 withdrawAmount = 300 * 10**6; // Would leave 700 USDC < 800 min

        vm.expectRevert(X402Insurance.InsufficientBond.selector);
        insurance.withdrawBond(withdrawAmount);
        vm.stopPrank();
    }

    function test_SetMinProviderBond() public {
        uint256 minBond = 500 * 10**6; // 500 USDC

        vm.prank(platformTreasury);

        vm.expectEmit(true, false, false, true);
        emit MinBondUpdated(provider, 0, minBond);

        insurance.setMinProviderBond(provider, minBond);

        assertEq(insurance.minProviderBond(provider), minBond);
    }

    function test_RevertWhen_NonTreasurySetMinBond() public {
        vm.prank(provider);
        vm.expectRevert(X402Insurance.Unauthorized.selector);
        insurance.setMinProviderBond(provider, 500 * 10**6);
    }

    function test_IsProviderHealthy() public {
        uint256 bondAmount = 1000 * 10**6; // 1000 USDC
        uint256 minBond = 800 * 10**6;     // 800 USDC

        // Set min bond
        vm.prank(platformTreasury);
        insurance.setMinProviderBond(provider, minBond);

        // Provider not healthy yet
        assertFalse(insurance.isProviderHealthy(provider));

        // Deposit bond
        vm.startPrank(provider);
        usdc.approve(address(insurance), bondAmount);
        insurance.depositBond(bondAmount);
        vm.stopPrank();

        // Provider now healthy
        assertTrue(insurance.isProviderHealthy(provider));
    }

    // =============================================================
    //                      INSURANCE PURCHASE TESTS
    // =============================================================

    function test_PurchaseInsurance() public {
        bytes32 requestCommitment = keccak256("test-request-1");
        uint256 paymentAmount = 100 * 10**6;  // 100 USDC
        uint256 insuranceFee = 1 * 10**6;     // 1 USDC (1%)
        uint256 timeoutMinutes = 10;

        // Provider deposits bond
        vm.startPrank(provider);
        usdc.approve(address(insurance), paymentAmount);
        insurance.depositBond(paymentAmount);
        vm.stopPrank();

        // Client purchases insurance
        vm.startPrank(client);
        usdc.approve(address(insurance), insuranceFee);

        vm.expectEmit(true, true, true, false);
        emit InsurancePurchased(
            requestCommitment,
            client,
            provider,
            paymentAmount,
            insuranceFee,
            0 // deadline - will be set by block.timestamp
        );

        insurance.purchaseInsurance(
            requestCommitment,
            provider,
            paymentAmount,
            insuranceFee,
            timeoutMinutes
        );
        vm.stopPrank();

        // Verify claim created
        (
            address claimClient,
            address claimProvider,
            uint256 claimPaymentAmount,
            uint256 claimInsuranceFee,
            uint256 claimDeadline,
            X402Insurance.ClaimStatus status
        ) = insurance.claims(requestCommitment);

        assertEq(claimClient, client);
        assertEq(claimProvider, provider);
        assertEq(claimPaymentAmount, paymentAmount);
        assertEq(claimInsuranceFee, insuranceFee);
        assertTrue(claimDeadline > block.timestamp);
        assertEq(uint(status), uint(X402Insurance.ClaimStatus.Pending));
    }

    function test_RevertWhen_PurchaseWithZeroFee() public {
        bytes32 requestCommitment = keccak256("test-request");

        vm.prank(client);
        vm.expectRevert(X402Insurance.InvalidAmount.selector);
        insurance.purchaseInsurance(requestCommitment, provider, 100 * 10**6, 0, 10);
    }

    function test_RevertWhen_PurchaseWithZeroAddress() public {
        bytes32 requestCommitment = keccak256("test-request");

        vm.prank(client);
        vm.expectRevert(X402Insurance.ZeroAddress.selector);
        insurance.purchaseInsurance(
            requestCommitment,
            address(0),
            100 * 10**6,
            1 * 10**6,
            10
        );
    }

    function test_RevertWhen_PurchaseWithInsufficientBond() public {
        bytes32 requestCommitment = keccak256("test-request");
        uint256 paymentAmount = 100 * 10**6;
        uint256 insuranceFee = 1 * 10**6;

        // Provider has no bond

        vm.startPrank(client);
        usdc.approve(address(insurance), insuranceFee);

        vm.expectRevert(X402Insurance.InsufficientBond.selector);
        insurance.purchaseInsurance(
            requestCommitment,
            provider,
            paymentAmount,
            insuranceFee,
            10
        );
        vm.stopPrank();
    }

    function test_RevertWhen_PurchaseDuplicateCommitment() public {
        bytes32 requestCommitment = keccak256("test-request");
        uint256 paymentAmount = 100 * 10**6;
        uint256 insuranceFee = 1 * 10**6;

        // Provider deposits bond
        vm.startPrank(provider);
        usdc.approve(address(insurance), paymentAmount);
        insurance.depositBond(paymentAmount);
        vm.stopPrank();

        // First purchase
        vm.startPrank(client);
        usdc.approve(address(insurance), insuranceFee * 2);
        insurance.purchaseInsurance(
            requestCommitment,
            provider,
            paymentAmount,
            insuranceFee,
            10
        );

        // Second purchase with same commitment
        vm.expectRevert(X402Insurance.AlreadySettled.selector);
        insurance.purchaseInsurance(
            requestCommitment,
            provider,
            paymentAmount,
            insuranceFee,
            10
        );
        vm.stopPrank();
    }

    // =============================================================
    //                      SERVICE CONFIRMATION TESTS
    // =============================================================

    function test_ConfirmService() public {
        bytes32 requestCommitment = keccak256("test-request");
        uint256 paymentAmount = 100 * 10**6;
        uint256 insuranceFee = 10 * 10**6; // 10 USDC

        // Setup: Provider deposits bond, client purchases insurance
        vm.startPrank(provider);
        usdc.approve(address(insurance), paymentAmount);
        insurance.depositBond(paymentAmount);
        vm.stopPrank();

        vm.startPrank(client);
        usdc.approve(address(insurance), insuranceFee);
        insurance.purchaseInsurance(
            requestCommitment,
            provider,
            paymentAmount,
            insuranceFee,
            10
        );
        vm.stopPrank();

        // Create signature
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("ServiceConfirmation(bytes32 requestCommitment)"),
                requestCommitment
            )
        );
        bytes32 digest = insurance.domainSeparator();
        // For testing, we'll use a simple approach
        // In production, proper EIP-712 signing is required

        // Provider confirms service
        bytes memory signature = _signConfirmation(providerPrivateKey, requestCommitment);

        uint256 platformBalanceBefore = usdc.balanceOf(platformTreasury);
        uint256 providerBalanceBefore = usdc.balanceOf(provider);

        vm.expectEmit(true, true, false, true);
        emit ServiceConfirmed(requestCommitment, provider, insuranceFee * 9 / 10);

        insurance.confirmService(requestCommitment, signature);

        // Verify balances
        uint256 expectedPlatformFee = insuranceFee * platformFeeRate / 10000;
        uint256 expectedProviderReward = insuranceFee - expectedPlatformFee;

        assertEq(
            usdc.balanceOf(platformTreasury),
            platformBalanceBefore + expectedPlatformFee
        );
        assertEq(
            usdc.balanceOf(provider),
            providerBalanceBefore + expectedProviderReward
        );

        // Verify claim status updated
        (,,,,, X402Insurance.ClaimStatus status) = insurance.claims(requestCommitment);
        assertEq(uint(status), uint(X402Insurance.ClaimStatus.Confirmed));
    }

    function test_RevertWhen_ConfirmAlreadySettled() public {
        bytes32 requestCommitment = keccak256("test-request");
        uint256 paymentAmount = 100 * 10**6;
        uint256 insuranceFee = 10 * 10**6;

        // Setup
        vm.startPrank(provider);
        usdc.approve(address(insurance), paymentAmount);
        insurance.depositBond(paymentAmount);
        vm.stopPrank();

        vm.startPrank(client);
        usdc.approve(address(insurance), insuranceFee);
        insurance.purchaseInsurance(
            requestCommitment,
            provider,
            paymentAmount,
            insuranceFee,
            10
        );
        vm.stopPrank();

        // First confirmation
        bytes memory signature = _signConfirmation(providerPrivateKey, requestCommitment);
        insurance.confirmService(requestCommitment, signature);

        // Second confirmation
        vm.expectRevert(X402Insurance.AlreadySettled.selector);
        insurance.confirmService(requestCommitment, signature);
    }

    function test_RevertWhen_ConfirmWithInvalidSignature() public {
        bytes32 requestCommitment = keccak256("test-request");
        uint256 paymentAmount = 100 * 10**6;
        uint256 insuranceFee = 10 * 10**6;

        // Setup
        vm.startPrank(provider);
        usdc.approve(address(insurance), paymentAmount);
        insurance.depositBond(paymentAmount);
        vm.stopPrank();

        vm.startPrank(client);
        usdc.approve(address(insurance), insuranceFee);
        insurance.purchaseInsurance(
            requestCommitment,
            provider,
            paymentAmount,
            insuranceFee,
            10
        );
        vm.stopPrank();

        // Use wrong private key
        bytes memory wrongSignature = _signConfirmation(clientPrivateKey, requestCommitment);

        vm.expectRevert(X402Insurance.InvalidSignature.selector);
        insurance.confirmService(requestCommitment, wrongSignature);
    }

    // =============================================================
    //                      INSURANCE CLAIM TESTS
    // =============================================================

    function test_ClaimInsurance() public {
        bytes32 requestCommitment = keccak256("test-request");
        uint256 paymentAmount = 100 * 10**6;
        uint256 insuranceFee = 10 * 10**6;
        uint256 timeoutMinutes = 1;

        // Setup
        vm.startPrank(provider);
        usdc.approve(address(insurance), paymentAmount);
        insurance.depositBond(paymentAmount);
        vm.stopPrank();

        vm.startPrank(client);
        usdc.approve(address(insurance), insuranceFee);
        insurance.purchaseInsurance(
            requestCommitment,
            provider,
            paymentAmount,
            insuranceFee,
            timeoutMinutes
        );
        vm.stopPrank();

        // Fast forward past timeout
        vm.warp(block.timestamp + timeoutMinutes * 1 minutes + 1);

        // Claim insurance
        uint256 clientBalanceBefore = usdc.balanceOf(client);
        uint256 providerBondBefore = insurance.providerBond(provider);

        vm.prank(client);
        vm.expectEmit(true, true, false, true);
        emit InsuranceClaimed(requestCommitment, client, paymentAmount);

        insurance.claimInsurance(requestCommitment);

        // Verify balances
        assertEq(
            usdc.balanceOf(client),
            clientBalanceBefore + paymentAmount + insuranceFee
        );
        assertEq(
            insurance.providerBond(provider),
            providerBondBefore - paymentAmount
        );

        // Verify claim status
        (,,,,, X402Insurance.ClaimStatus status) = insurance.claims(requestCommitment);
        assertEq(uint(status), uint(X402Insurance.ClaimStatus.Claimed));
    }

    function test_RevertWhen_ClaimByNonClient() public {
        bytes32 requestCommitment = keccak256("test-request");
        uint256 paymentAmount = 100 * 10**6;
        uint256 insuranceFee = 10 * 10**6;

        // Setup
        vm.startPrank(provider);
        usdc.approve(address(insurance), paymentAmount);
        insurance.depositBond(paymentAmount);
        vm.stopPrank();

        vm.startPrank(client);
        usdc.approve(address(insurance), insuranceFee);
        insurance.purchaseInsurance(
            requestCommitment,
            provider,
            paymentAmount,
            insuranceFee,
            1
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 2 minutes);

        // Try to claim by non-client
        vm.prank(otherProvider);
        vm.expectRevert(X402Insurance.Unauthorized.selector);
        insurance.claimInsurance(requestCommitment);
    }

    function test_RevertWhen_ClaimBeforeTimeout() public {
        bytes32 requestCommitment = keccak256("test-request");
        uint256 paymentAmount = 100 * 10**6;
        uint256 insuranceFee = 10 * 10**6;

        // Setup
        vm.startPrank(provider);
        usdc.approve(address(insurance), paymentAmount);
        insurance.depositBond(paymentAmount);
        vm.stopPrank();

        vm.startPrank(client);
        usdc.approve(address(insurance), insuranceFee);
        insurance.purchaseInsurance(
            requestCommitment,
            provider,
            paymentAmount,
            insuranceFee,
            10
        );
        vm.stopPrank();

        // Try to claim before timeout
        vm.prank(client);
        vm.expectRevert(X402Insurance.NotExpired.selector);
        insurance.claimInsurance(requestCommitment);
    }

    // =============================================================
    //                      QUERY FUNCTION TESTS
    // =============================================================

    function test_GetClaimDetails() public {
        bytes32 requestCommitment = keccak256("test-request");
        uint256 paymentAmount = 100 * 10**6;
        uint256 insuranceFee = 10 * 10**6;
        uint256 timeoutMinutes = 5;

        // Setup
        vm.startPrank(provider);
        usdc.approve(address(insurance), paymentAmount);
        insurance.depositBond(paymentAmount);
        vm.stopPrank();

        vm.startPrank(client);
        usdc.approve(address(insurance), insuranceFee);
        insurance.purchaseInsurance(
            requestCommitment,
            provider,
            paymentAmount,
            insuranceFee,
            timeoutMinutes
        );
        vm.stopPrank();

        (
            address returnedClient,
            address returnedProvider,
            uint256 returnedPayment,
            uint256 returnedFee,
            uint256 returnedDeadline,
            X402Insurance.ClaimStatus returnedStatus,
            uint256 timeLeft
        ) = insurance.getClaimDetails(requestCommitment);

        assertEq(returnedClient, client);
        assertEq(returnedProvider, provider);
        assertEq(returnedPayment, paymentAmount);
        assertEq(returnedFee, insuranceFee);
        assertTrue(returnedDeadline > block.timestamp);
        assertEq(uint(returnedStatus), uint(X402Insurance.ClaimStatus.Pending));
        assertTrue(timeLeft > 0);
    }

    function test_CanClaimInsurance() public {
        bytes32 requestCommitment = keccak256("test-request");
        uint256 paymentAmount = 100 * 10**6;
        uint256 insuranceFee = 10 * 10**6;
        uint256 timeoutMinutes = 1;

        // Setup
        vm.startPrank(provider);
        usdc.approve(address(insurance), paymentAmount);
        insurance.depositBond(paymentAmount);
        vm.stopPrank();

        vm.startPrank(client);
        usdc.approve(address(insurance), insuranceFee);
        insurance.purchaseInsurance(
            requestCommitment,
            provider,
            paymentAmount,
            insuranceFee,
            timeoutMinutes
        );
        vm.stopPrank();

        // Before timeout
        assertFalse(insurance.canClaimInsurance(requestCommitment));

        // After timeout
        vm.warp(block.timestamp + timeoutMinutes * 1 minutes + 1);
        assertTrue(insurance.canClaimInsurance(requestCommitment));
    }

    function test_GetProviderStats() public {
        uint256 bondAmount = 1000 * 10**6;
        uint256 minBond = 500 * 10**6;

        vm.prank(platformTreasury);
        insurance.setMinProviderBond(provider, minBond);

        vm.startPrank(provider);
        usdc.approve(address(insurance), bondAmount);
        insurance.depositBond(bondAmount);
        vm.stopPrank();

        (
            uint256 bondBalance,
            uint256 returnedMinBond,
            bool isHealthy
        ) = insurance.getProviderStats(provider);

        assertEq(bondBalance, bondAmount);
        assertEq(returnedMinBond, minBond);
        assertTrue(isHealthy);
    }

    // =============================================================
    //                      PLATFORM MANAGEMENT TESTS
    // =============================================================

    function test_SetPlatformFeeRate() public {
        uint256 newRate = 500; // 5%

        vm.prank(platformTreasury);
        insurance.setPlatformFeeRate(newRate);

        assertEq(insurance.platformFeeRate(), newRate);
    }

    function test_SetDefaultTimeout() public {
        uint256 newTimeout = 10; // 10 minutes

        vm.prank(platformTreasury);
        insurance.setDefaultTimeout(newTimeout);

        assertEq(insurance.defaultTimeout(), newTimeout);
    }

    function test_SetPlatformTreasury() public {
        address newTreasury = address(0x999);

        vm.prank(platformTreasury);
        insurance.setPlatformTreasury(newTreasury);

        assertEq(insurance.platformTreasury(), newTreasury);
    }

    function test_RevertWhen_SetTreasuryToZeroAddress() public {
        vm.prank(platformTreasury);
        vm.expectRevert(X402Insurance.ZeroAddress.selector);
        insurance.setPlatformTreasury(address(0));
    }

    // =============================================================
    //                      HELPER FUNCTIONS
    // =============================================================

    function _signConfirmation(
        uint256 privateKey,
        bytes32 requestCommitment
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("ServiceConfirmation(bytes32 requestCommitment)"),
                requestCommitment
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                insurance.domainSeparator(),
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
