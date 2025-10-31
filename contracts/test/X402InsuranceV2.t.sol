// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/X402InsuranceV2.sol";
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
 * @title X402InsuranceV2Test
 * @notice 完整测试 V2 保险合约（零保险费 + 惩罚机制）
 */
contract X402InsuranceV2Test is Test {
    X402InsuranceV2 public insurance;
    MockUSDC public usdc;

    address public platformTreasury = address(0x1);
    address public provider = address(0x2);
    address public client = address(0x3);
    address public otherProvider = address(0x4);

    uint256 public platformPenaltyRate = 200; // 2%
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
        uint256 lockedAmount,
        uint256 deadline
    );
    event ServiceConfirmed(
        bytes32 indexed requestCommitment,
        address indexed provider,
        uint256 unlockedAmount
    );
    event InsuranceClaimed(
        bytes32 indexed requestCommitment,
        address indexed client,
        uint256 compensationAmount,
        uint256 penaltyAmount
    );
    event PlatformPenaltyCollected(
        bytes32 indexed requestCommitment,
        uint256 amount
    );
    event ProviderLiquidated(
        address indexed provider,
        uint256 remainingBond
    );

    function setUp() public {
        // Deploy mock USDC
        usdc = new MockUSDC();

        // Deploy insurance contract
        insurance = new X402InsuranceV2(
            address(usdc),
            platformTreasury,
            platformPenaltyRate,
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
        assertEq(insurance.lockedBond(provider), 0);
    }

    function test_RevertWhen_DepositZeroAmount() public {
        vm.startPrank(provider);
        vm.expectRevert(X402InsuranceV2.InvalidAmount.selector);
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

        vm.expectRevert(X402InsuranceV2.InsufficientBond.selector);
        insurance.withdrawBond(withdrawAmount);
        vm.stopPrank();
    }

    function test_RevertWhen_WithdrawLockedBond() public {
        uint256 bondAmount = 1000 * 10**6; // 1000 USDC
        uint256 paymentAmount = 500 * 10**6; // 500 USDC

        // Setup: deposit bond and purchase insurance
        vm.startPrank(provider);
        usdc.approve(address(insurance), bondAmount);
        insurance.depositBond(bondAmount);
        vm.stopPrank();

        bytes32 requestCommitment = keccak256("test-request");

        vm.prank(client);
        insurance.purchaseInsurance(
            requestCommitment,
            provider,
            paymentAmount,
            5
        );

        // Locked bond = 500 * 1.02 = 510 USDC
        // Available = 1000 - 510 = 490 USDC

        // Try to withdraw 500 USDC (more than available)
        vm.startPrank(provider);
        vm.expectRevert(X402InsuranceV2.InsufficientAvailableBond.selector);
        insurance.withdrawBond(500 * 10**6);
        vm.stopPrank();
    }

    function test_IsProviderHealthy() public {
        uint256 bondAmount = 1000 * 10**6; // 1000 USDC
        uint256 minBond = 500 * 10**6;     // 500 USDC

        // Set min bond
        vm.prank(platformTreasury);
        insurance.setMinProviderBond(provider, minBond);

        // Provider not healthy yet (no bond)
        assertFalse(insurance.isProviderHealthy(provider));

        // Deposit bond
        vm.startPrank(provider);
        usdc.approve(address(insurance), bondAmount);
        insurance.depositBond(bondAmount);
        vm.stopPrank();

        // Provider now healthy
        assertTrue(insurance.isProviderHealthy(provider));
    }

    function test_ProviderBecomesUnhealthyAfterLocking() public {
        uint256 bondAmount = 600 * 10**6; // 600 USDC
        uint256 minBond = 500 * 10**6;     // 500 USDC
        uint256 paymentAmount = 200 * 10**6; // 200 USDC

        vm.prank(platformTreasury);
        insurance.setMinProviderBond(provider, minBond);

        vm.startPrank(provider);
        usdc.approve(address(insurance), bondAmount);
        insurance.depositBond(bondAmount);
        vm.stopPrank();

        // Healthy initially
        assertTrue(insurance.isProviderHealthy(provider));

        // Purchase insurance locks 200 * 1.02 = 204 USDC
        // Available = 600 - 204 = 396 < 500 min
        bytes32 requestCommitment = keccak256("test-request");

        vm.prank(client);
        insurance.purchaseInsurance(
            requestCommitment,
            provider,
            paymentAmount,
            5
        );

        // Now unhealthy!
        assertFalse(insurance.isProviderHealthy(provider));
    }

    // =============================================================
    //                      INSURANCE PURCHASE TESTS
    // =============================================================

    function test_PurchaseInsurance() public {
        bytes32 requestCommitment = keccak256("test-request-1");
        uint256 bondAmount = 1000 * 10**6;
        uint256 paymentAmount = 100 * 10**6;  // 100 USDC
        uint256 timeoutMinutes = 10;

        // Provider deposits bond
        vm.startPrank(provider);
        usdc.approve(address(insurance), bondAmount);
        insurance.depositBond(bondAmount);
        vm.stopPrank();

        // Client purchases insurance (no USDC needed!)
        vm.prank(client);

        vm.expectEmit(true, true, true, false);
        emit InsurancePurchased(
            requestCommitment,
            client,
            provider,
            paymentAmount,
            paymentAmount * 102 / 100, // locked = payment * 1.02
            0 // deadline
        );

        insurance.purchaseInsurance(
            requestCommitment,
            provider,
            paymentAmount,
            timeoutMinutes
        );

        // Verify bond locked
        uint256 expectedLocked = paymentAmount * 102 / 100; // 102 USDC
        assertEq(insurance.lockedBond(provider), expectedLocked);
        assertEq(insurance.providerBond(provider), bondAmount);

        // Verify claim created
        (
            address claimClient,
            address claimProvider,
            uint256 claimPaymentAmount,
            uint256 claimDeadline,
            X402InsuranceV2.ClaimStatus status,
        ) = insurance.getClaimDetails(requestCommitment);

        assertEq(claimClient, client);
        assertEq(claimProvider, provider);
        assertEq(claimPaymentAmount, paymentAmount);
        assertTrue(claimDeadline > block.timestamp);
        assertEq(uint(status), uint(X402InsuranceV2.ClaimStatus.Pending));
    }

    function test_RevertWhen_PurchaseFromUnhealthyProvider() public {
        bytes32 requestCommitment = keccak256("test-request");
        uint256 minBond = 500 * 10**6;
        uint256 bondAmount = 400 * 10**6; // Less than min
        uint256 paymentAmount = 100 * 10**6;

        vm.prank(platformTreasury);
        insurance.setMinProviderBond(provider, minBond);

        vm.startPrank(provider);
        usdc.approve(address(insurance), bondAmount);
        insurance.depositBond(bondAmount);
        vm.stopPrank();

        // Provider unhealthy (400 < 500)
        assertFalse(insurance.isProviderHealthy(provider));

        vm.prank(client);
        vm.expectRevert(X402InsuranceV2.ProviderUnhealthy.selector);
        insurance.purchaseInsurance(
            requestCommitment,
            provider,
            paymentAmount,
            10
        );
    }

    function test_GetProtectionCost() public {
        uint256 paymentAmount = 100 * 10**6; // 100 USDC

        (uint256 totalLock, uint256 penalty) =
            insurance.getProtectionCost(paymentAmount);

        uint256 expectedPenalty = paymentAmount * platformPenaltyRate / 10000; // 2 USDC
        uint256 expectedTotal = paymentAmount + expectedPenalty; // 102 USDC

        assertEq(penalty, expectedPenalty);
        assertEq(totalLock, expectedTotal);
    }

    // =============================================================
    //                      SERVICE CONFIRMATION TESTS
    // =============================================================

    function test_ConfirmService() public {
        bytes32 requestCommitment = keccak256("test-request");
        uint256 bondAmount = 1000 * 10**6;
        uint256 paymentAmount = 100 * 10**6; // 100 USDC

        // Setup
        vm.startPrank(provider);
        usdc.approve(address(insurance), bondAmount);
        insurance.depositBond(bondAmount);
        vm.stopPrank();

        vm.prank(client);
        insurance.purchaseInsurance(
            requestCommitment,
            provider,
            paymentAmount,
            10
        );

        uint256 lockedBefore = insurance.lockedBond(provider);
        assertTrue(lockedBefore > 0);

        // Confirm service
        bytes memory signature = _signConfirmation(providerPrivateKey, requestCommitment);

        vm.expectEmit(true, true, false, true);
        emit ServiceConfirmed(requestCommitment, provider, lockedBefore);

        insurance.confirmService(requestCommitment, signature);

        // Verify bond unlocked
        assertEq(insurance.lockedBond(provider), 0);

        // Verify status
        (,,,,X402InsuranceV2.ClaimStatus status,) = insurance.getClaimDetails(requestCommitment);
        assertEq(uint(status), uint(X402InsuranceV2.ClaimStatus.Confirmed));
    }

    function test_RevertWhen_ConfirmWithInvalidSignature() public {
        bytes32 requestCommitment = keccak256("test-request");
        uint256 paymentAmount = 100 * 10**6;

        // Setup
        vm.startPrank(provider);
        usdc.approve(address(insurance), 1000 * 10**6);
        insurance.depositBond(1000 * 10**6);
        vm.stopPrank();

        vm.prank(client);
        insurance.purchaseInsurance(
            requestCommitment,
            provider,
            paymentAmount,
            10
        );

        // Use wrong signer
        bytes memory wrongSignature = _signConfirmation(clientPrivateKey, requestCommitment);

        vm.expectRevert(X402InsuranceV2.InvalidSignature.selector);
        insurance.confirmService(requestCommitment, wrongSignature);
    }

    // =============================================================
    //                      INSURANCE CLAIM TESTS
    // =============================================================

    function test_ClaimInsurance() public {
        bytes32 requestCommitment = keccak256("test-request");
        uint256 bondAmount = 1000 * 10**6;
        uint256 paymentAmount = 100 * 10**6; // 100 USDC
        uint256 timeoutMinutes = 1;

        // Setup
        vm.startPrank(provider);
        usdc.approve(address(insurance), bondAmount);
        insurance.depositBond(bondAmount);
        vm.stopPrank();

        vm.prank(client);
        insurance.purchaseInsurance(
            requestCommitment,
            provider,
            paymentAmount,
            timeoutMinutes
        );

        // Fast forward past timeout
        vm.warp(block.timestamp + timeoutMinutes * 1 minutes + 1);

        // Calculate expected amounts
        uint256 expectedPenalty = paymentAmount * platformPenaltyRate / 10000; // 2 USDC
        uint256 expectedTotal = paymentAmount + expectedPenalty; // 102 USDC

        uint256 clientBalanceBefore = usdc.balanceOf(client);
        uint256 platformBalanceBefore = usdc.balanceOf(platformTreasury);
        uint256 providerBondBefore = insurance.providerBond(provider);

        // Claim insurance
        vm.prank(client);

        vm.expectEmit(true, true, false, true);
        emit InsuranceClaimed(requestCommitment, client, paymentAmount, expectedPenalty);

        insurance.claimInsurance(requestCommitment);

        // Verify client received compensation
        assertEq(
            usdc.balanceOf(client),
            clientBalanceBefore + paymentAmount
        );

        // Verify platform received penalty
        assertEq(
            usdc.balanceOf(platformTreasury),
            platformBalanceBefore + expectedPenalty
        );

        // Verify provider bond deducted
        assertEq(
            insurance.providerBond(provider),
            providerBondBefore - expectedTotal
        );

        // Verify locked bond cleared
        assertEq(insurance.lockedBond(provider), 0);
    }

    function test_ProviderLosesMoneyOnFailure() public {
        bytes32 requestCommitment = keccak256("test-request");
        uint256 bondAmount = 1000 * 10**6;
        uint256 paymentAmount = 100 * 10**6; // 100 USDC

        vm.startPrank(provider);
        usdc.approve(address(insurance), bondAmount);
        insurance.depositBond(bondAmount);
        vm.stopPrank();

        vm.prank(client);
        insurance.purchaseInsurance(requestCommitment, provider, paymentAmount, 1);

        vm.warp(block.timestamp + 2 minutes);

        uint256 providerBondBefore = insurance.providerBond(provider);

        vm.prank(client);
        insurance.claimInsurance(requestCommitment);

        uint256 providerBondAfter = insurance.providerBond(provider);
        uint256 loss = providerBondBefore - providerBondAfter;

        // Provider loses payment + 2% penalty
        uint256 expectedLoss = paymentAmount * 102 / 100; // 102 USDC
        assertEq(loss, expectedLoss);

        // If provider received 100 USDC from x402, net = -2 USDC!
        // This tests the economic incentive
    }

    function test_RevertWhen_ClaimBeforeTimeout() public {
        bytes32 requestCommitment = keccak256("test-request");
        uint256 paymentAmount = 100 * 10**6;

        vm.startPrank(provider);
        usdc.approve(address(insurance), 1000 * 10**6);
        insurance.depositBond(1000 * 10**6);
        vm.stopPrank();

        vm.prank(client);
        insurance.purchaseInsurance(requestCommitment, provider, paymentAmount, 10);

        // Try to claim immediately
        vm.prank(client);
        vm.expectRevert(X402InsuranceV2.NotExpired.selector);
        insurance.claimInsurance(requestCommitment);
    }

    // =============================================================
    //                      LIQUIDATION TESTS
    // =============================================================

    function test_LiquidateProvider() public {
        uint256 bondAmount = 1000 * 10**6;
        uint256 minBond = 5000 * 10**6; // 要求 5000 USDC，但只存了 1000

        vm.startPrank(provider);
        usdc.approve(address(insurance), bondAmount);
        insurance.depositBond(bondAmount);
        vm.stopPrank();

        // 设置最低保证金（远高于当前）
        vm.prank(platformTreasury);
        insurance.setMinProviderBond(provider, minBond);

        uint256 platformBalanceBefore = usdc.balanceOf(platformTreasury);

        // 先发出警告
        insurance.warnProvider(provider);

        // 快进宽限期 (7 天)
        vm.warp(block.timestamp + 7 days + 1);

        // 清算
        vm.expectEmit(true, false, false, true);
        emit ProviderLiquidated(provider, bondAmount);

        insurance.liquidateProvider(provider);

        // Verify bond transferred to platform
        assertEq(
            usdc.balanceOf(platformTreasury),
            platformBalanceBefore + bondAmount
        );

        assertEq(insurance.providerBond(provider), 0);
        assertTrue(insurance.isLiquidated(provider));
        assertFalse(insurance.isProviderHealthy(provider));
    }

    function test_RevertWhen_LiquidateWithPendingClaims() public {
        bytes32 requestCommitment = keccak256("test-request");
        uint256 bondAmount = 1000 * 10**6;
        uint256 paymentAmount = 100 * 10**6;

        vm.startPrank(provider);
        usdc.approve(address(insurance), bondAmount);
        insurance.depositBond(bondAmount);
        vm.stopPrank();

        vm.prank(client);
        insurance.purchaseInsurance(requestCommitment, provider, paymentAmount, 10);

        // Try to liquidate with pending claim
        vm.prank(platformTreasury);
        vm.expectRevert(X402InsuranceV2.HasPendingClaims.selector);
        insurance.liquidateProvider(provider);
    }

    function test_RevertWhen_LiquidatedProviderDeposits() public {
        uint256 bondAmount = 1000 * 10**6;
        uint256 minBond = 5000 * 10**6;

        vm.startPrank(provider);
        usdc.approve(address(insurance), bondAmount);
        insurance.depositBond(bondAmount);
        vm.stopPrank();

        // 设置最低保证金
        vm.prank(platformTreasury);
        insurance.setMinProviderBond(provider, minBond);

        // 发出警告
        insurance.warnProvider(provider);

        // 快进宽限期
        vm.warp(block.timestamp + 7 days + 1);

        // 清算
        insurance.liquidateProvider(provider);

        // Try to deposit again
        vm.startPrank(provider);
        usdc.approve(address(insurance), bondAmount);
        vm.expectRevert(X402InsuranceV2.ProviderIsLiquidated.selector);
        insurance.depositBond(bondAmount);
        vm.stopPrank();
    }

    // =============================================================
    //                      QUERY FUNCTION TESTS
    // =============================================================

    function test_GetProviderStats() public {
        uint256 bondAmount = 1000 * 10**6;
        uint256 minBond = 500 * 10**6;
        uint256 paymentAmount = 200 * 10**6;

        vm.prank(platformTreasury);
        insurance.setMinProviderBond(provider, minBond);

        vm.startPrank(provider);
        usdc.approve(address(insurance), bondAmount);
        insurance.depositBond(bondAmount);
        vm.stopPrank();

        bytes32 requestCommitment = keccak256("test-request");
        vm.prank(client);
        insurance.purchaseInsurance(requestCommitment, provider, paymentAmount, 10);

        (
            uint256 totalBond,
            uint256 lockedAmount,
            uint256 availableBond,
            uint256 returnedMinBond,
            bool isHealthy,
            bool liquidated,
            ,  // warningTime
            ,  // liquidationDeadline
               // canBeLiquidated
        ) = insurance.getProviderStats(provider);

        uint256 expectedLocked = paymentAmount * 102 / 100; // 204 USDC
        uint256 expectedAvailable = bondAmount - expectedLocked; // 796 USDC

        assertEq(totalBond, bondAmount);
        assertEq(lockedAmount, expectedLocked);
        assertEq(availableBond, expectedAvailable);
        assertEq(returnedMinBond, minBond);
        assertTrue(isHealthy); // 796 > 500
        assertFalse(liquidated);
    }

    function test_CanClaimInsurance() public {
        bytes32 requestCommitment = keccak256("test-request");
        uint256 paymentAmount = 100 * 10**6;
        uint256 timeoutMinutes = 1;

        vm.startPrank(provider);
        usdc.approve(address(insurance), 1000 * 10**6);
        insurance.depositBond(1000 * 10**6);
        vm.stopPrank();

        vm.prank(client);
        insurance.purchaseInsurance(requestCommitment, provider, paymentAmount, timeoutMinutes);

        // Before timeout
        assertFalse(insurance.canClaimInsurance(requestCommitment));

        // After timeout
        vm.warp(block.timestamp + timeoutMinutes * 1 minutes + 1);
        assertTrue(insurance.canClaimInsurance(requestCommitment));
    }

    // =============================================================
    //                      EDGE CASE TESTS
    // =============================================================

    function test_MultipleOrdersLockBond() public {
        uint256 bondAmount = 1000 * 10**6;
        uint256 paymentAmount = 100 * 10**6;

        vm.startPrank(provider);
        usdc.approve(address(insurance), bondAmount);
        insurance.depositBond(bondAmount);
        vm.stopPrank();

        // Purchase 5 insurances
        for (uint i = 0; i < 5; i++) {
            bytes32 commitment = keccak256(abi.encodePacked("request", i));
            vm.prank(client);
            insurance.purchaseInsurance(commitment, provider, paymentAmount, 10);
        }

        // Total locked = 5 * 102 = 510 USDC
        uint256 expectedLocked = 5 * paymentAmount * 102 / 100;
        assertEq(insurance.lockedBond(provider), expectedLocked);

        // Available = 1000 - 510 = 490 USDC
        (,, uint256 available,,,,,,) = insurance.getProviderStats(provider);
        assertEq(available, bondAmount - expectedLocked);
    }

    function test_ConfirmReleasesOnlySpecificLock() public {
        uint256 bondAmount = 1000 * 10**6;
        uint256 payment1 = 100 * 10**6;
        uint256 payment2 = 200 * 10**6;

        vm.startPrank(provider);
        usdc.approve(address(insurance), bondAmount);
        insurance.depositBond(bondAmount);
        vm.stopPrank();

        bytes32 commitment1 = keccak256("request1");
        bytes32 commitment2 = keccak256("request2");

        vm.startPrank(client);
        insurance.purchaseInsurance(commitment1, provider, payment1, 10);
        insurance.purchaseInsurance(commitment2, provider, payment2, 10);
        vm.stopPrank();

        uint256 locked1 = payment1 * 102 / 100;
        uint256 locked2 = payment2 * 102 / 100;
        assertEq(insurance.lockedBond(provider), locked1 + locked2);

        // Confirm first order
        bytes memory sig1 = _signConfirmation(providerPrivateKey, commitment1);
        insurance.confirmService(commitment1, sig1);

        // Only first lock released
        assertEq(insurance.lockedBond(provider), locked2);
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
