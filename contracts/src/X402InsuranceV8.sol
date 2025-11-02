// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title X402InsuranceV8
 * @notice 比例赔付与延迟补偿系统
 *
 * 核心改进：
 * 1. 资金不足时按比例赔付
 * 2. 记录未赔付部分（延迟补偿）
 * 3. Provider充值后自动按比例补偿所有待补偿索赔
 * 4. 池永不为负，保持系统稳定性
 *
 * 重要：补偿继续按比例分配，不是先到先得
 */
contract X402InsuranceV8 is ReentrancyGuard, Ownable {
    IERC20 public immutable usdcToken;

    // 常量配置
    uint256 public constant MIN_POOL_BALANCE = 10 * 10**6;      // 最低10 USDC
    uint256 public constant MAX_POOL_BALANCE = 1000000 * 10**6; // 最高100万 USDC
    uint256 public constant MIN_CLAIM_AMOUNT = 1 * 10**5;       // 最低0.1 USDC
    uint256 public constant MAX_CLAIM_AMOUNT = 10000 * 10**6;   // 最高1万 USDC
    uint256 public constant PENALTY_RATE = 1000;                // 10%罚金
    uint256 public constant PLATFORM_FEE_RATE = 100;            // 1%平台费
    uint256 public constant MAX_EXPOSURE_RATIO = 8000;          // 80%最大暴露率

    // Provider状态
    struct ProviderData {
        bool isActive;
        uint256 poolBalance;        // 保险池余额
        uint256 totalLocked;        // 锁定金额
        uint256 successfulServices;
        uint256 failedServices;
        uint8 tier;                 // 1-3 等级
        uint256 registeredAt;
    }

    // 索赔信息（增加延迟补偿字段）
    struct ClaimInfo {
        address client;
        address provider;
        uint256 requestedAmount;    // 客户请求的金额
        uint256 paidAmount;         // 实际已支付金额
        uint256 pendingAmount;      // 待补偿金额
        uint256 initiatedAt;
        uint256 disputeDeadline;
        ClaimReason reason;
        ClaimStatus status;
    }

    // 延迟补偿记录
    struct PendingCompensation {
        bytes32 commitment;
        address client;
        uint256 amount;             // 待补偿金额
        uint256 createdAt;
        bool isPaid;                // 是否已完全补偿
    }

    enum ClaimStatus { INITIATED, DISPUTED, EXECUTED, REJECTED, PARTIAL }
    enum ClaimReason { NOT_DELIVERED, SERVICE_TIMEOUT, PARTIAL_DELIVERY }

    // 存储
    mapping(address => ProviderData) public providers;
    mapping(bytes32 => ClaimInfo) public claims;
    mapping(address => bytes32[]) public providerPendingCompensations;  // Provider的待补偿列表
    mapping(bytes32 => PendingCompensation) public pendingCompensations;

    // 全局保险池
    uint256 public totalProviderPools;      // 所有Provider池总和
    uint256 public emergencyPool;           // 应急池
    uint256 public platformInsuranceFund;   // 平台保险基金

    // 统计
    uint256 public totalClaimsInitiated;
    uint256 public totalClaimsExecuted;
    uint256 public totalPendingCompensations; // 总待补偿金额

    // 事件
    event ProviderRegistered(address indexed provider, uint256 amount);
    event ProviderDeposited(address indexed provider, uint256 amount);
    event ProviderWithdrew(address indexed provider, uint256 amount);
    event ProviderDeactivated(address indexed provider);

    event ClaimInitiated(bytes32 indexed commitment, address indexed client, address indexed provider, uint256 amount);
    event ClaimDisputed(bytes32 indexed commitment, address indexed provider);
    event ClaimExecuted(bytes32 indexed commitment, uint256 paidAmount, uint256 pendingAmount);
    event ClaimRejected(bytes32 indexed commitment);

    event CompensationPaid(bytes32 indexed commitment, address indexed client, uint256 amount);
    event AutoCompensationTriggered(address indexed provider, uint256 totalCompensated, uint256 claimsProcessed);

    constructor(address _usdcToken, address _owner) Ownable(_owner) {
        require(_usdcToken != address(0), "Invalid USDC address");
        usdcToken = IERC20(_usdcToken);
    }

    // ==================== Provider Functions ====================

    /**
     * @notice 注册或重新激活Provider
     * @param amount 初始保险金额
     */
    function registerOrReactivate(uint256 amount) external nonReentrant {
        require(amount >= MIN_POOL_BALANCE, "Insufficient initial deposit");
        require(amount <= MAX_POOL_BALANCE, "Exceeds maximum pool balance");

        ProviderData storage provider = providers[msg.sender];

        if (provider.registeredAt == 0) {
            // 新Provider
            provider.tier = 1;
            provider.registeredAt = block.timestamp;
        }

        // 转入USDC
        require(usdcToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        provider.isActive = true;
        provider.poolBalance += amount;
        totalProviderPools += amount;

        // 如果有待补偿，自动触发补偿
        if (providerPendingCompensations[msg.sender].length > 0) {
            _processProportionalCompensations(msg.sender);
        }

        emit ProviderRegistered(msg.sender, amount);
    }

    /**
     * @notice 追加保险金
     * @param amount 追加金额
     */
    function depositAdditional(uint256 amount) external nonReentrant {
        ProviderData storage provider = providers[msg.sender];
        require(provider.isActive, "Provider not active");
        require(provider.poolBalance + amount <= MAX_POOL_BALANCE, "Exceeds maximum");

        require(usdcToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        provider.poolBalance += amount;
        totalProviderPools += amount;

        // 触发自动补偿
        if (providerPendingCompensations[msg.sender].length > 0) {
            _processProportionalCompensations(msg.sender);
        }

        emit ProviderDeposited(msg.sender, amount);
    }

    /**
     * @notice 提取部分资金
     * @param amount 提取金额
     */
    function withdraw(uint256 amount) external nonReentrant {
        ProviderData storage provider = providers[msg.sender];
        require(provider.isActive, "Provider not active");

        uint256 available = provider.poolBalance > provider.totalLocked ?
                          provider.poolBalance - provider.totalLocked : 0;
        require(amount <= available, "Insufficient available balance");

        // 提取后余额不能低于最低要求
        require(provider.poolBalance - amount >= MIN_POOL_BALANCE, "Below minimum balance");

        provider.poolBalance -= amount;
        totalProviderPools -= amount;

        require(usdcToken.transfer(msg.sender, amount), "Transfer failed");

        emit ProviderWithdrew(msg.sender, amount);
    }

    /**
     * @notice 提取全部并停用
     */
    function withdrawAllAndDeactivate() external nonReentrant {
        ProviderData storage provider = providers[msg.sender];
        require(provider.isActive, "Provider not active");
        require(provider.totalLocked == 0, "Has active claims");

        uint256 amount = provider.poolBalance;

        provider.isActive = false;
        provider.poolBalance = 0;
        totalProviderPools -= amount;

        if (amount > 0) {
            require(usdcToken.transfer(msg.sender, amount), "Transfer failed");
        }

        emit ProviderDeactivated(msg.sender);
    }

    // ==================== Claim Functions ====================

    /**
     * @notice 发起索赔（V8核心：比例支付）
     */
    function initiateClaim(
        bytes32 commitment,
        address provider,
        uint256 amount,
        ClaimReason reason
    ) external nonReentrant {
        require(amount >= MIN_CLAIM_AMOUNT && amount <= MAX_CLAIM_AMOUNT, "Invalid amount");
        require(claims[commitment].initiatedAt == 0, "Claim already exists");
        require(providers[provider].isActive, "Provider not active");

        // 计算所需总金额
        uint256 penaltyAmount = (amount * PENALTY_RATE) / 10000;
        uint256 platformFee = (amount * PLATFORM_FEE_RATE) / 10000;
        uint256 totalRequired = amount + penaltyAmount + platformFee;

        // V8核心：计算可用资金和支付比例
        ProviderData storage providerData = providers[provider];
        uint256 providerAvailable = providerData.poolBalance > providerData.totalLocked ?
            providerData.poolBalance - providerData.totalLocked : 0;

        uint256 totalAvailable = providerAvailable + emergencyPool + platformInsuranceFund;

        uint256 actualPaidAmount;
        uint256 pendingAmount;
        ClaimStatus claimStatus;

        if (totalAvailable >= amount) {
            // 资金充足，全额支付
            actualPaidAmount = amount;
            pendingAmount = 0;
            claimStatus = ClaimStatus.INITIATED;
        } else if (totalAvailable > 0) {
            // 资金不足，按比例支付
            actualPaidAmount = totalAvailable;
            pendingAmount = amount - actualPaidAmount;
            claimStatus = ClaimStatus.PARTIAL;

            // 记录待补偿
            _recordPendingCompensation(commitment, msg.sender, provider, pendingAmount);
        } else {
            // 完全没有资金
            actualPaidAmount = 0;
            pendingAmount = amount;
            claimStatus = ClaimStatus.PARTIAL;

            // 记录待补偿
            _recordPendingCompensation(commitment, msg.sender, provider, pendingAmount);
        }

        // 锁定资金（只锁定实际可支付部分相关的金额）
        if (actualPaidAmount > 0) {
            uint256 actualTotalRequired = actualPaidAmount +
                (actualPaidAmount * PENALTY_RATE) / 10000 +
                (actualPaidAmount * PLATFORM_FEE_RATE) / 10000;

            uint256 fromProvider = actualTotalRequired <= providerAvailable ?
                actualTotalRequired : providerAvailable;
            providerData.totalLocked += fromProvider;
        }

        // 创建索赔记录
        claims[commitment] = ClaimInfo({
            client: msg.sender,
            provider: provider,
            requestedAmount: amount,
            paidAmount: actualPaidAmount,
            pendingAmount: pendingAmount,
            initiatedAt: block.timestamp,
            disputeDeadline: block.timestamp + _getDisputePeriod(amount),
            reason: reason,
            status: claimStatus
        });

        totalClaimsInitiated++;

        emit ClaimInitiated(commitment, msg.sender, provider, amount);
    }

    /**
     * @notice 执行索赔（支付已锁定的金额）
     */
    function executeClaim(bytes32 commitment) external nonReentrant {
        ClaimInfo storage claim = claims[commitment];
        require(claim.initiatedAt > 0, "Claim not found");
        require(
            claim.status == ClaimStatus.INITIATED || claim.status == ClaimStatus.PARTIAL,
            "Invalid claim status"
        );
        require(block.timestamp > claim.disputeDeadline, "Still in dispute period");

        ProviderData storage providerData = providers[claim.provider];

        uint256 actualPaidAmount = claim.paidAmount;

        if (actualPaidAmount > 0) {
            // 计算费用
            uint256 penaltyAmount = (actualPaidAmount * PENALTY_RATE) / 10000;
            uint256 platformFee = (actualPaidAmount * PLATFORM_FEE_RATE) / 10000;
            uint256 totalRequired = actualPaidAmount + penaltyAmount + platformFee;

            // 从锁定中扣除
            uint256 fromProvider = totalRequired <= providerData.poolBalance ?
                totalRequired : providerData.poolBalance;

            if (fromProvider > 0) {
                providerData.poolBalance -= fromProvider;
                providerData.totalLocked -= (fromProvider <= providerData.totalLocked ?
                    fromProvider : providerData.totalLocked);
                totalProviderPools -= fromProvider;
            }

            // 如果Provider资金不足，从应急池补充
            if (fromProvider < totalRequired) {
                uint256 fromEmergency = totalRequired - fromProvider;
                if (fromEmergency <= emergencyPool) {
                    emergencyPool -= fromEmergency;
                } else {
                    uint256 fromPlatform = fromEmergency - emergencyPool;
                    emergencyPool = 0;
                    platformInsuranceFund -= fromPlatform;
                }
            }

            // 分配资金
            emergencyPool += penaltyAmount / 2;
            platformInsuranceFund += penaltyAmount / 2 + platformFee;

            // 支付给客户
            require(usdcToken.transfer(claim.client, actualPaidAmount), "Transfer failed");
        }

        // 更新状态
        if (claim.pendingAmount == 0) {
            claim.status = ClaimStatus.EXECUTED;
            providerData.successfulServices++;
        } else {
            // 仍有待补偿，保持PARTIAL状态
            claim.status = ClaimStatus.PARTIAL;
        }

        totalClaimsExecuted++;

        emit ClaimExecuted(commitment, actualPaidAmount, claim.pendingAmount);
    }

    /**
     * @notice 争议索赔
     */
    function disputeClaim(bytes32 commitment, string memory evidence) external {
        ClaimInfo storage claim = claims[commitment];
        require(claim.initiatedAt > 0, "Claim not found");
        require(claim.provider == msg.sender, "Not the provider");
        require(claim.status == ClaimStatus.INITIATED || claim.status == ClaimStatus.PARTIAL, "Cannot dispute");
        require(block.timestamp <= claim.disputeDeadline, "Dispute period ended");

        claim.status = ClaimStatus.DISPUTED;

        // 释放锁定（如果有）
        if (claim.paidAmount > 0) {
            ProviderData storage providerData = providers[msg.sender];
            uint256 lockedAmount = claim.paidAmount +
                (claim.paidAmount * PENALTY_RATE) / 10000 +
                (claim.paidAmount * PLATFORM_FEE_RATE) / 10000;

            if (lockedAmount <= providerData.totalLocked) {
                providerData.totalLocked -= lockedAmount;
            } else {
                providerData.totalLocked = 0;
            }
        }

        emit ClaimDisputed(commitment, msg.sender);
    }

    // ==================== Compensation Functions ====================

    /**
     * @notice 记录待补偿
     */
    function _recordPendingCompensation(
        bytes32 commitment,
        address client,
        address provider,
        uint256 amount
    ) private {
        pendingCompensations[commitment] = PendingCompensation({
            commitment: commitment,
            client: client,
            amount: amount,
            createdAt: block.timestamp,
            isPaid: false
        });

        providerPendingCompensations[provider].push(commitment);
        totalPendingCompensations += amount;
    }

    /**
     * @notice 处理比例补偿（核心：继续按比例分配）
     */
    function _processProportionalCompensations(address provider) private {
        bytes32[] storage commitments = providerPendingCompensations[provider];
        if (commitments.length == 0) return;

        ProviderData storage providerData = providers[provider];
        uint256 availableFunds = providerData.poolBalance > providerData.totalLocked ?
            providerData.poolBalance - providerData.totalLocked : 0;

        if (availableFunds == 0) return;

        // 计算总待补偿金额
        uint256 totalPending = 0;
        uint256 validCount = 0;

        for (uint256 i = 0; i < commitments.length; i++) {
            PendingCompensation storage comp = pendingCompensations[commitments[i]];
            if (!comp.isPaid && comp.amount > 0) {
                totalPending += comp.amount;
                validCount++;
            }
        }

        if (totalPending == 0) return;

        // 按比例分配可用资金
        uint256 totalCompensated = 0;
        uint256 claimsProcessed = 0;

        for (uint256 i = 0; i < commitments.length; i++) {
            bytes32 commitment = commitments[i];
            PendingCompensation storage comp = pendingCompensations[commitment];
            ClaimInfo storage claim = claims[commitment];

            if (!comp.isPaid && comp.amount > 0) {
                // 计算此索赔的比例补偿
                uint256 proportionalPayment = (availableFunds * comp.amount) / totalPending;

                // 确保不超过待补偿金额
                if (proportionalPayment > comp.amount) {
                    proportionalPayment = comp.amount;
                }

                if (proportionalPayment > 0) {
                    // 更新补偿记录
                    comp.amount -= proportionalPayment;
                    if (comp.amount == 0) {
                        comp.isPaid = true;
                    }

                    // 更新索赔信息
                    claim.paidAmount += proportionalPayment;
                    claim.pendingAmount -= proportionalPayment;

                    // 扣除Provider资金
                    providerData.poolBalance -= proportionalPayment;
                    totalProviderPools -= proportionalPayment;

                    // 转账给客户
                    require(usdcToken.transfer(claim.client, proportionalPayment), "Compensation transfer failed");

                    totalCompensated += proportionalPayment;
                    claimsProcessed++;
                    totalPendingCompensations -= proportionalPayment;

                    emit CompensationPaid(commitment, claim.client, proportionalPayment);
                }
            }
        }

        // 清理已完全补偿的记录
        uint256 writeIndex = 0;
        for (uint256 i = 0; i < commitments.length; i++) {
            PendingCompensation storage comp = pendingCompensations[commitments[i]];
            if (!comp.isPaid) {
                if (i != writeIndex) {
                    commitments[writeIndex] = commitments[i];
                }
                writeIndex++;
            }
        }

        // 调整数组长度
        while (commitments.length > writeIndex) {
            commitments.pop();
        }

        if (totalCompensated > 0) {
            emit AutoCompensationTriggered(provider, totalCompensated, claimsProcessed);
        }
    }

    // ==================== Query Functions ====================

    /**
     * @notice 获取Provider信息
     */
    function getProviderInfo(address provider) external view returns (
        bool isActive,
        uint256 poolBalance,
        uint256 totalLocked,
        uint256 successfulServices,
        uint256 failedServices,
        uint8 tier,
        uint256 registeredAt
    ) {
        ProviderData memory data = providers[provider];
        return (
            data.isActive,
            data.poolBalance,
            data.totalLocked,
            data.successfulServices,
            data.failedServices,
            data.tier,
            data.registeredAt
        );
    }

    /**
     * @notice 获取Provider待补偿列表
     */
    function getProviderPendingCompensations(address provider) external view returns (
        bytes32[] memory commitments,
        uint256[] memory amounts,
        uint256 totalAmount
    ) {
        bytes32[] storage providerCommitments = providerPendingCompensations[provider];
        commitments = new bytes32[](providerCommitments.length);
        amounts = new uint256[](providerCommitments.length);
        totalAmount = 0;

        uint256 validCount = 0;
        for (uint256 i = 0; i < providerCommitments.length; i++) {
            PendingCompensation memory comp = pendingCompensations[providerCommitments[i]];
            if (!comp.isPaid && comp.amount > 0) {
                commitments[validCount] = providerCommitments[i];
                amounts[validCount] = comp.amount;
                totalAmount += comp.amount;
                validCount++;
            }
        }

        // 调整数组大小
        assembly {
            mstore(commitments, validCount)
            mstore(amounts, validCount)
        }
    }

    /**
     * @notice 获取索赔信息（包含补偿状态）
     */
    function getClaimInfo(bytes32 commitment) external view returns (
        address client,
        address provider,
        uint256 requestedAmount,
        uint256 paidAmount,
        uint256 pendingAmount,
        uint256 initiatedAt,
        uint256 disputeDeadline,
        ClaimReason reason,
        ClaimStatus status
    ) {
        ClaimInfo memory claim = claims[commitment];
        return (
            claim.client,
            claim.provider,
            claim.requestedAmount,
            claim.paidAmount,
            claim.pendingAmount,
            claim.initiatedAt,
            claim.disputeDeadline,
            claim.reason,
            claim.status
        );
    }

    /**
     * @notice 检查是否可以接受服务
     */
    function canAcceptService(address provider, uint256 serviceAmount) external view returns (
        bool canAccept,
        string memory reason
    ) {
        ProviderData memory data = providers[provider];

        if (!data.isActive) {
            return (false, "Provider not active");
        }

        uint256 available = data.poolBalance > data.totalLocked ?
            data.poolBalance - data.totalLocked : 0;

        // V8: 即使资金不足也可以接受，只是会部分支付
        if (available == 0) {
            return (true, "Warning: No funds available, claim will be deferred");
        }

        if (available < serviceAmount) {
            return (true, "Warning: Partial payment possible, remainder will be deferred");
        }

        uint256 maxExposure = (data.poolBalance * MAX_EXPOSURE_RATIO) / 10000;
        if (data.totalLocked + serviceAmount > maxExposure) {
            return (true, "Warning: Near exposure limit, partial payment likely");
        }

        return (true, "OK");
    }

    // ==================== Admin Functions ====================

    /**
     * @notice 向应急池注资
     */
    function fundEmergencyPool(uint256 amount) external onlyOwner {
        require(usdcToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        emergencyPool += amount;
    }

    /**
     * @notice 向平台基金注资
     */
    function fundPlatformInsurance(uint256 amount) external onlyOwner {
        require(usdcToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        platformInsuranceFund += amount;
    }

    // ==================== Internal Functions ====================

    /**
     * @notice 获取争议期
     */
    function _getDisputePeriod(uint256 amount) private pure returns (uint256) {
        if (amount <= 10 * 10**6) return 1 minutes;      // ≤10 USDC: 1分钟
        if (amount <= 100 * 10**6) return 5 minutes;     // ≤100 USDC: 5分钟
        if (amount <= 1000 * 10**6) return 15 minutes;   // ≤1000 USDC: 15分钟
        return 30 minutes;                                // >1000 USDC: 30分钟
    }
}