// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/X402InsuranceV3.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {
        _mint(msg.sender, 1000000 * 10**6); // 1M USDC
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract X402InsuranceV3Test is Test {
    X402InsuranceV3 public insurance;
    MockUSDC public usdc;

    address public owner = address(this);
    address public treasury = address(0x1234);
    address public provider1 = address(0x1111);
    address public provider2 = address(0x2222);
    address public client1 = address(0x3333);
    address public client2 = address(0x4444);
    address public relayer = address(0x5555);

    uint256 constant BRONZE_MIN = 100 * 10**6;     // 100 USDC
    uint256 constant SILVER_MIN = 500 * 10**6;     // 500 USDC
    uint256 constant GOLD_MIN = 1000 * 10**6;      // 1000 USDC
    uint256 constant PLATINUM_MIN = 5000 * 10**6;  // 5000 USDC

    bytes32 constant commitment1 = keccak256("commitment1");
    bytes32 constant commitment2 = keccak256("commitment2");
    bytes32 constant commitment3 = keccak256("commitment3");

    event ProviderRegistered(address indexed provider, uint256 amount, X402InsuranceV3.ProviderTier tier);
    event InsuranceLocked(bytes32 indexed commitment, address indexed provider, address indexed client, uint256 amount, uint256 unlockAt);
    event ServiceDelivered(bytes32 indexed commitment, address indexed provider);
    event InsuranceClaimed(bytes32 indexed commitment, address indexed client, uint256 refundAmount, uint256 penaltyAmount);

    function setUp() public {
        // 部署合约
        usdc = new MockUSDC();
        insurance = new X402InsuranceV3(address(usdc), treasury);

        // 分发USDC给测试账户
        usdc.transfer(provider1, 10000 * 10**6);  // 10000 USDC
        usdc.transfer(provider2, 10000 * 10**6);  // 10000 USDC
        usdc.transfer(client1, 1000 * 10**6);     // 1000 USDC
        usdc.transfer(client2, 1000 * 10**6);     // 1000 USDC

        // 授权
        vm.prank(provider1);
        usdc.approve(address(insurance), type(uint256).max);
        vm.prank(provider2);
        usdc.approve(address(insurance), type(uint256).max);
    }

    // ============ Provider注册测试 ============

    function test_RegisterAndDeposit_Success() public {
        uint256 depositAmount = BRONZE_MIN;

        vm.startPrank(provider1);

        vm.expectEmit(true, true, true, true);
        emit ProviderRegistered(provider1, depositAmount, X402InsuranceV3.ProviderTier.Bronze);

        insurance.registerAndDeposit(depositAmount);

        (uint256 poolBalance, uint256 availableBalance, uint256 lockedBalance,
         X402InsuranceV3.ProviderTier tier, bool isActive, uint256 successRate)
            = insurance.getProviderInfo(provider1);

        assertEq(poolBalance, depositAmount);
        assertEq(availableBalance, depositAmount);
        assertEq(lockedBalance, 0);
        assertEq(uint8(tier), uint8(X402InsuranceV3.ProviderTier.Bronze));
        assertTrue(isActive);
        assertEq(successRate, 0);

        vm.stopPrank();
    }

    function test_RegisterAndDeposit_DifferentTiers() public {
        // Bronze级别
        vm.prank(provider1);
        insurance.registerAndDeposit(BRONZE_MIN);
        (, , , X402InsuranceV3.ProviderTier tier1, , ) = insurance.getProviderInfo(provider1);
        assertEq(uint8(tier1), uint8(X402InsuranceV3.ProviderTier.Bronze));

        // Silver级别
        vm.prank(provider2);
        insurance.registerAndDeposit(SILVER_MIN);
        (, , , X402InsuranceV3.ProviderTier tier2, , ) = insurance.getProviderInfo(provider2);
        assertEq(uint8(tier2), uint8(X402InsuranceV3.ProviderTier.Silver));
    }

    function test_RegisterAndDeposit_RevertIfAlreadyRegistered() public {
        vm.startPrank(provider1);
        insurance.registerAndDeposit(BRONZE_MIN);

        vm.expectRevert("Already registered");
        insurance.registerAndDeposit(BRONZE_MIN);
        vm.stopPrank();
    }

    function test_RegisterAndDeposit_RevertIfBelowMinimum() public {
        vm.prank(provider1);
        vm.expectRevert("Minimum 100 USDC required");
        insurance.registerAndDeposit(50 * 10**6);
    }

    // ============ 充值与提现测试 ============

    function test_Deposit_Success() public {
        // 先注册
        vm.prank(provider1);
        insurance.registerAndDeposit(BRONZE_MIN);

        // 追加充值
        uint256 additionalDeposit = 400 * 10**6;  // 400 USDC
        vm.prank(provider1);
        insurance.deposit(additionalDeposit);

        (uint256 poolBalance, , , X402InsuranceV3.ProviderTier tier, , )
            = insurance.getProviderInfo(provider1);

        assertEq(poolBalance, BRONZE_MIN + additionalDeposit);  // 500 USDC
        assertEq(uint8(tier), uint8(X402InsuranceV3.ProviderTier.Silver));  // 升级到Silver
    }

    function test_Withdraw_Partial() public {
        // 注册并充值500 USDC
        vm.prank(provider1);
        insurance.registerAndDeposit(SILVER_MIN);

        // 提取200 USDC
        vm.prank(provider1);
        insurance.withdraw(200 * 10**6);

        (uint256 poolBalance, , , X402InsuranceV3.ProviderTier tier, bool isActive, )
            = insurance.getProviderInfo(provider1);

        assertEq(poolBalance, 300 * 10**6);  // 剩余300 USDC
        assertEq(uint8(tier), uint8(X402InsuranceV3.ProviderTier.Bronze));  // 降级到Bronze
        assertTrue(isActive);  // 仍然活跃
    }

    function test_WithdrawAllAndDeactivate() public {
        // 注册并充值
        vm.prank(provider1);
        insurance.registerAndDeposit(SILVER_MIN);

        uint256 balanceBefore = usdc.balanceOf(provider1);

        // 提取全部并注销
        vm.prank(provider1);
        insurance.withdrawAllAndDeactivate();

        (uint256 poolBalance, , , X402InsuranceV3.ProviderTier tier, bool isActive, )
            = insurance.getProviderInfo(provider1);

        assertEq(poolBalance, 0);
        assertEq(uint8(tier), uint8(X402InsuranceV3.ProviderTier.None));
        assertFalse(isActive);
        assertEq(usdc.balanceOf(provider1), balanceBefore + SILVER_MIN);
    }

    // ============ 保险锁定测试 ============

    function test_LockInsurance_Success() public {
        // Provider注册
        vm.prank(provider1);
        insurance.registerAndDeposit(GOLD_MIN);

        uint256 insuranceAmount = 10 * 10**6;  // 10 USDC

        vm.expectEmit(true, true, true, true);
        emit InsuranceLocked(commitment1, provider1, client1, insuranceAmount, block.timestamp + 24 hours);

        insurance.lockInsurance(commitment1, provider1, client1, insuranceAmount);

        (address provider, address client, uint256 amount, uint256 lockedAt, uint256 unlockAt, X402InsuranceV3.ClaimStatus status)
            = insurance.getClaimDetails(commitment1);

        assertEq(provider, provider1);
        assertEq(client, client1);
        assertEq(amount, insuranceAmount);
        assertEq(lockedAt, block.timestamp);
        assertEq(unlockAt, block.timestamp + 24 hours);
        assertEq(uint8(status), uint8(X402InsuranceV3.ClaimStatus.Locked));

        // 检查Provider的锁定余额
        (, uint256 availableBalance, uint256 lockedBalance, , , )
            = insurance.getProviderInfo(provider1);
        assertEq(lockedBalance, insuranceAmount);
        assertEq(availableBalance, GOLD_MIN - insuranceAmount);
    }

    function test_LockInsurance_RevertIfInsufficientBalance() public {
        // Provider注册
        vm.prank(provider1);
        insurance.registerAndDeposit(BRONZE_MIN);

        uint256 insuranceAmount = 200 * 10**6;  // 200 USDC (超过余额)

        vm.expectRevert("Insufficient available balance");
        insurance.lockInsurance(commitment1, provider1, client1, insuranceAmount);
    }

    // ============ 交付确认测试 ============

    function test_ConfirmDelivery_Success() public {
        // 准备：注册并锁定保险
        vm.prank(provider1);
        insurance.registerAndDeposit(GOLD_MIN);

        uint256 insuranceAmount = 10 * 10**6;
        insurance.lockInsurance(commitment1, provider1, client1, insuranceAmount);

        // Provider确认交付
        vm.prank(provider1);
        vm.expectEmit(true, true, false, false);
        emit ServiceDelivered(commitment1, provider1);
        insurance.confirmDelivery(commitment1);

        // 检查状态
        (, , , , , X402InsuranceV3.ClaimStatus status) = insurance.getClaimDetails(commitment1);
        assertEq(uint8(status), uint8(X402InsuranceV3.ClaimStatus.Success));

        // 检查锁定已释放
        (, , uint256 lockedBalance, , , ) = insurance.getProviderInfo(provider1);
        assertEq(lockedBalance, 0);

        // 检查统计
        (,,, uint256 successCount, uint256 failureCount,,) = insurance.getProviderStats(provider1);
        assertEq(successCount, 1);
        assertEq(failureCount, 0);
    }

    // ============ 索赔测试 ============

    function test_ClaimInsurance_Success() public {
        // 准备：注册并锁定保险
        vm.prank(provider1);
        insurance.registerAndDeposit(GOLD_MIN);

        uint256 insuranceAmount = 100 * 10**6;  // 100 USDC
        insurance.lockInsurance(commitment1, provider1, client1, insuranceAmount);

        // 快进24小时
        vm.warp(block.timestamp + 24 hours + 1);

        uint256 clientBalanceBefore = usdc.balanceOf(client1);
        uint256 treasuryBalanceBefore = usdc.balanceOf(treasury);

        // Client索赔
        vm.prank(client1);
        vm.expectEmit(true, true, false, true);
        emit InsuranceClaimed(commitment1, client1, insuranceAmount, insuranceAmount * 2 / 100);
        insurance.claimInsurance(commitment1);

        // 检查退款
        assertEq(usdc.balanceOf(client1), clientBalanceBefore + insuranceAmount);  // 100%退款
        assertEq(usdc.balanceOf(treasury), treasuryBalanceBefore + insuranceAmount * 2 / 100);  // 2%罚金

        // 检查Provider余额
        (uint256 poolBalance, , , , , ) = insurance.getProviderInfo(provider1);
        assertEq(poolBalance, GOLD_MIN - insuranceAmount - (insuranceAmount * 2 / 100));  // 扣除102 USDC

        // 检查统计
        (,,, uint256 successCount, uint256 failureCount,,) = insurance.getProviderStats(provider1);
        assertEq(successCount, 0);
        assertEq(failureCount, 1);
    }

    function test_ClaimInsurance_RevertIfNotExpired() public {
        // 准备：注册并锁定保险
        vm.prank(provider1);
        insurance.registerAndDeposit(GOLD_MIN);

        insurance.lockInsurance(commitment1, provider1, client1, 10 * 10**6);

        // 尝试立即索赔（未超时）
        vm.prank(client1);
        vm.expectRevert("Lock period not expired");
        insurance.claimInsurance(commitment1);
    }

    // ============ Meta-transaction测试 ============

    function test_MetaClaimInsurance_Success() public {
        // 使用固定的私钥生成client地址
        uint256 clientPrivateKey = 0xabc123;
        address clientFromKey = vm.addr(clientPrivateKey);

        // 给这个地址发送USDC
        usdc.transfer(clientFromKey, 100 * 10**6);

        // 准备：注册并锁定保险
        vm.prank(provider1);
        insurance.registerAndDeposit(GOLD_MIN);

        uint256 insuranceAmount = 50 * 10**6;
        insurance.lockInsurance(commitment1, provider1, clientFromKey, insuranceAmount);

        // 快进24小时
        vm.warp(block.timestamp + 24 hours + 1);

        // 准备签名参数
        uint256 nonce = insurance.clientNonces(clientFromKey);
        uint256 deadline = block.timestamp + 1 hours;

        // 构造签名消息
        bytes32 domainSeparator = insurance.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(
                insurance.CLAIM_TYPEHASH(),
                commitment1,
                clientFromKey,
                insuranceAmount,
                nonce,
                deadline
            )
        );
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Client签名（使用对应的私钥）
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(clientPrivateKey, hash);

        // Relayer代付Gas执行meta-transaction
        uint256 clientBalanceBefore = usdc.balanceOf(clientFromKey);

        vm.prank(relayer);
        insurance.metaClaimInsurance(
            commitment1,
            clientFromKey,
            insuranceAmount,
            deadline,
            v, r, s
        );

        // 验证Client收到退款（零Gas费）
        assertEq(usdc.balanceOf(clientFromKey), clientBalanceBefore + insuranceAmount);
    }

    // ============ 自动解锁测试 ============

    function test_AutoUnlock_Success() public {
        // 准备：注册并锁定保险
        vm.prank(provider1);
        insurance.registerAndDeposit(GOLD_MIN);

        uint256 insuranceAmount = 10 * 10**6;
        insurance.lockInsurance(commitment1, provider1, client1, insuranceAmount);

        // 快进48小时（超过自动解锁期）
        vm.warp(block.timestamp + 48 hours + 1);

        // 任何人都可以调用自动解锁
        insurance.autoUnlock(commitment1);

        // 检查状态
        (, , , , , X402InsuranceV3.ClaimStatus status) = insurance.getClaimDetails(commitment1);
        assertEq(uint8(status), uint8(X402InsuranceV3.ClaimStatus.Success));

        // 检查锁定已释放
        (, , uint256 lockedBalance, , , ) = insurance.getProviderInfo(provider1);
        assertEq(lockedBalance, 0);
    }

    // ============ 等级系统测试 ============

    function test_TierUpgrade() public {
        // 从Bronze开始
        vm.startPrank(provider1);
        insurance.registerAndDeposit(BRONZE_MIN);

        (, , , X402InsuranceV3.ProviderTier tier, , ) = insurance.getProviderInfo(provider1);
        assertEq(uint8(tier), uint8(X402InsuranceV3.ProviderTier.Bronze));

        // 充值到Silver
        insurance.deposit(400 * 10**6);
        (, , , tier, , ) = insurance.getProviderInfo(provider1);
        assertEq(uint8(tier), uint8(X402InsuranceV3.ProviderTier.Silver));

        // 充值到Gold
        insurance.deposit(500 * 10**6);
        (, , , tier, , ) = insurance.getProviderInfo(provider1);
        assertEq(uint8(tier), uint8(X402InsuranceV3.ProviderTier.Gold));

        // 充值到Platinum
        insurance.deposit(4000 * 10**6);
        (, , , tier, , ) = insurance.getProviderInfo(provider1);
        assertEq(uint8(tier), uint8(X402InsuranceV3.ProviderTier.Platinum));

        vm.stopPrank();
    }

    function test_TierDowngrade() public {
        // 从Gold开始
        vm.startPrank(provider1);
        insurance.registerAndDeposit(GOLD_MIN);

        // 提取到Silver级别
        insurance.withdraw(600 * 10**6);
        (, , , X402InsuranceV3.ProviderTier tier, , ) = insurance.getProviderInfo(provider1);
        assertEq(uint8(tier), uint8(X402InsuranceV3.ProviderTier.Bronze));

        vm.stopPrank();
    }

    // ============ 平台统计测试 ============

    function test_PlatformStats() public {
        // Provider1注册
        vm.prank(provider1);
        insurance.registerAndDeposit(GOLD_MIN);

        // Provider2注册
        vm.prank(provider2);
        insurance.registerAndDeposit(SILVER_MIN);

        // 获取平台统计
        X402InsuranceV3.PlatformStats memory stats = insurance.getPlatformStats();
        assertEq(stats.totalPoolBalance, GOLD_MIN + SILVER_MIN);
        assertEq(stats.totalProviders, 2);
        assertEq(stats.activeProviders, 2);

        // 锁定一笔保险
        insurance.lockInsurance(commitment1, provider1, client1, 10 * 10**6);
        stats = insurance.getPlatformStats();
        assertEq(stats.totalLockedBalance, 10 * 10**6);
        assertEq(stats.totalTransactions, 1);

        // Provider1注销
        vm.prank(provider1);
        insurance.withdrawAllAndDeactivate();
        stats = insurance.getPlatformStats();
        assertEq(stats.activeProviders, 1);
    }

    // ============ 边界条件测试 ============

    function test_ProviderDeactivation_OnInsufficientBalance() public {
        // 注册最小金额
        vm.prank(provider1);
        insurance.registerAndDeposit(BRONZE_MIN);

        // 锁定更大金额的保险，确保索赔后余额低于最低要求
        // 100 USDC - 95 USDC - 1.9 USDC (2%罚金) = 3.1 USDC < 10 USDC (最低要求)
        insurance.lockInsurance(commitment1, provider1, client1, 95 * 10**6);

        // 快进并索赔
        vm.warp(block.timestamp + 24 hours + 1);
        vm.prank(client1);
        insurance.claimInsurance(commitment1);

        // 检查Provider是否被停用（余额不足10 USDC）
        (uint256 poolBalance, , , , bool isActive, ) = insurance.getProviderInfo(provider1);
        assertLt(poolBalance, 10 * 10**6); // 余额应该少于10 USDC
        assertFalse(isActive); // 应该被停用
    }

    function test_MultipleClaimsHandling() public {
        // Provider注册充足资金
        vm.prank(provider1);
        insurance.registerAndDeposit(PLATINUM_MIN);

        // 锁定多笔保险
        uint256 amount1 = 100 * 10**6;
        uint256 amount2 = 200 * 10**6;
        uint256 amount3 = 150 * 10**6;

        insurance.lockInsurance(commitment1, provider1, client1, amount1);
        insurance.lockInsurance(commitment2, provider1, client2, amount2);
        insurance.lockInsurance(commitment3, provider1, client1, amount3);

        // commitment1: 成功交付
        vm.prank(provider1);
        insurance.confirmDelivery(commitment1);

        // commitment2: 超时索赔
        vm.warp(block.timestamp + 24 hours + 1);
        vm.prank(client2);
        insurance.claimInsurance(commitment2);

        // commitment3: 自动解锁
        vm.warp(block.timestamp + 48 hours + 1);
        insurance.autoUnlock(commitment3);

        // 检查最终状态
        (uint256 poolBalance, , , , , ) = insurance.getProviderInfo(provider1);
        uint256 expectedBalance = PLATINUM_MIN - amount2 - (amount2 * 2 / 100);  // 扣除commitment2的本金+罚金
        assertEq(poolBalance, expectedBalance);

        (,,, uint256 successCount, uint256 failureCount,,) = insurance.getProviderStats(provider1);
        assertEq(successCount, 2);  // commitment1 + commitment3
        assertEq(failureCount, 1);   // commitment2
    }
}