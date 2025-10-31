// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/**
 * @title X402InsuranceV2
 * @notice 零保险费模式 - 客户无需额外付费，由服务商 Bond 提供保护
 *
 * 核心特性：
 * 1. 客户只付服务费，不付保险费
 * 2. 服务失败时从服务商 bond 中赔付客户
 * 3. 额外扣除服务费的2%作为平台惩罚性收入
 * 4. Bond 低于阈值时服务商无法接单
 * 5. 服务商退出时剩余 bond 归平台管理
 *
 * 工作原理:
 * 1. x402 正常结算 - 服务商立即收到支付
 * 2. Bond 中临时锁定等额保护金
 * 3. 服务成功 - 解锁 bond，服务商保留收入
 * 4. 服务失败 - 从 bond 赔付客户 + 扣除2%罚金给平台
 */
contract X402InsuranceV2 is EIP712 {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    // =============================================================
    //                           STORAGE
    // =============================================================

    /// @notice USDC 代币
    IERC20 public immutable usdc;

    /// @notice 平台财务地址
    address public platformTreasury;

    /// @notice 平台惩罚费率（基点，200 = 2%）
    uint256 public platformPenaltyRate;

    /// @notice 默认超时时间（分钟）
    uint256 public defaultTimeout;

    /// @notice 服务商总保证金余额
    mapping(address => uint256) public providerBond;

    /// @notice 服务商已锁定的保证金（用于待处理订单）
    mapping(address => uint256) public lockedBond;

    /// @notice 服务商最低保证金要求
    mapping(address => uint256) public minProviderBond;

    /// @notice 保险索赔记录
    mapping(bytes32 => InsuranceClaim) public claims;

    /// @notice 服务商是否被清算
    mapping(address => bool) public isLiquidated;

    /// @notice 服务商警告时间戳（当 bond < minBond 时记录）
    mapping(address => uint256) public warningTimestamp;

    /// @notice 清算宽限期（秒）- 服务商有这么长时间补齐 bond
    uint256 public liquidationGracePeriod;

    /// @notice 保险索赔状态
    struct InsuranceClaim {
        address client;             // 客户地址
        address provider;           // 服务商地址
        uint256 paymentAmount;      // 原始支付金额（已通过 x402 结算）
        uint256 deadline;           // 超时时间
        ClaimStatus status;         // 状态
    }

    enum ClaimStatus {
        Pending,      // 待处理（bond已锁定）
        Confirmed,    // 服务成功（bond已解锁）
        Claimed       // 已赔付（bond已扣除+罚金）
    }

    // =============================================================
    //                            EVENTS
    // =============================================================

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
    event MinBondUpdated(
        address indexed provider,
        uint256 oldBond,
        uint256 newBond
    );
    event ProviderLiquidated(
        address indexed provider,
        uint256 remainingBond
    );
    event ProviderWarned(
        address indexed provider,
        uint256 currentBond,
        uint256 requiredBond,
        uint256 deadline
    );
    event LiquidationGracePeriodUpdated(
        uint256 oldPeriod,
        uint256 newPeriod
    );

    // =============================================================
    //                            ERRORS
    // =============================================================

    error Unauthorized();
    error InvalidAmount();
    error InsufficientBond();
    error InsufficientAvailableBond();
    error AlreadySettled();
    error NotExpired();
    error InvalidSignature();
    error ZeroAddress();
    error ProviderIsLiquidated();
    error ProviderUnhealthy();
    error HasPendingClaims();
    error GracePeriodNotExpired();
    error NoWarningIssued();

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    constructor(
        address _usdc,
        address _platformTreasury,
        uint256 _platformPenaltyRate,
        uint256 _defaultTimeout
    ) EIP712("X402InsuranceV2", "1") {
        if (_usdc == address(0) || _platformTreasury == address(0)) {
            revert ZeroAddress();
        }

        usdc = IERC20(_usdc);
        platformTreasury = _platformTreasury;
        platformPenaltyRate = _platformPenaltyRate;
        defaultTimeout = _defaultTimeout;
        liquidationGracePeriod = 7 days; // 默认 7 天宽限期
    }

    // =============================================================
    //                      服务商 BOND 管理
    // =============================================================

    /**
     * @notice 服务商存入保证金
     */
    function depositBond(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();
        if (isLiquidated[msg.sender]) revert ProviderIsLiquidated();

        usdc.safeTransferFrom(msg.sender, address(this), amount);
        providerBond[msg.sender] += amount;

        // 如果补齐了保证金，清除警告
        uint256 totalBond = providerBond[msg.sender];
        uint256 locked = lockedBond[msg.sender];
        uint256 available = totalBond - locked;
        uint256 minBond = minProviderBond[msg.sender];

        if (available >= minBond && warningTimestamp[msg.sender] > 0) {
            warningTimestamp[msg.sender] = 0; // 清除警告
        }

        emit BondDeposited(msg.sender, amount);
    }

    /**
     * @notice 服务商提取保证金（必须满足最低要求且无锁定）
     */
    function withdrawBond(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();

        uint256 totalBond = providerBond[msg.sender];
        uint256 locked = lockedBond[msg.sender];
        uint256 available = totalBond - locked;
        uint256 minBond = minProviderBond[msg.sender];

        if (available < amount) {
            revert InsufficientAvailableBond();
        }

        if (totalBond - amount < minBond) {
            revert InsufficientBond();
        }

        providerBond[msg.sender] -= amount;
        usdc.safeTransfer(msg.sender, amount);

        emit BondWithdrawn(msg.sender, amount);
    }

    /**
     * @notice 设置服务商最低保证金要求（平台管理员）
     */
    function setMinProviderBond(address provider, uint256 minBond) external {
        if (msg.sender != platformTreasury) revert Unauthorized();

        uint256 oldBond = minProviderBond[provider];
        minProviderBond[provider] = minBond;

        emit MinBondUpdated(provider, oldBond, minBond);
    }

    /**
     * @notice 检查服务商是否健康（可接单）
     */
    function isProviderHealthy(address provider) public view returns (bool) {
        if (isLiquidated[provider]) return false;

        uint256 totalBond = providerBond[provider];
        uint256 locked = lockedBond[provider];
        uint256 available = totalBond - locked;
        uint256 minBond = minProviderBond[provider];

        return available >= minBond;
    }

    /**
     * @notice 对服务商发出警告（bond 不足）
     * @dev 任何人都可以调用，触发警告计时
     */
    function warnProvider(address provider) external {
        if (isLiquidated[provider]) revert ProviderIsLiquidated();
        if (warningTimestamp[provider] > 0) return; // 已经警告过了

        uint256 totalBond = providerBond[provider];
        uint256 locked = lockedBond[provider];
        uint256 available = totalBond - locked;
        uint256 minBond = minProviderBond[provider];

        // 只有当可用 bond < minBond 时才能警告
        if (available >= minBond) return;

        // 记录警告时间
        warningTimestamp[provider] = block.timestamp;

        emit ProviderWarned(
            provider,
            available,
            minBond,
            block.timestamp + liquidationGracePeriod
        );
    }

    /**
     * @notice 清算服务商（任何人都可以调用）
     * @dev 需要满足以下条件：
     *      1. 已发出警告
     *      2. 宽限期已过
     *      3. 无待处理订单
     *      4. bond 仍然不足
     */
    function liquidateProvider(address provider) external {
        if (lockedBond[provider] > 0) revert HasPendingClaims();
        if (warningTimestamp[provider] == 0) revert NoWarningIssued();
        if (block.timestamp < warningTimestamp[provider] + liquidationGracePeriod) {
            revert GracePeriodNotExpired();
        }

        // 再次检查是否仍然不健康
        uint256 totalBond = providerBond[provider];
        uint256 locked = lockedBond[provider];
        uint256 available = totalBond - locked;
        uint256 minBond = minProviderBond[provider];

        // 如果已经补齐了，清除警告并返回
        if (available >= minBond) {
            warningTimestamp[provider] = 0;
            return;
        }

        // 执行清算
        uint256 remainingBond = providerBond[provider];

        if (remainingBond > 0) {
            providerBond[provider] = 0;
            usdc.safeTransfer(platformTreasury, remainingBond);
        }

        isLiquidated[provider] = true;
        warningTimestamp[provider] = 0; // 清除警告时间戳

        emit ProviderLiquidated(provider, remainingBond);
    }

    // =============================================================
    //                      保险购买和索赔
    // =============================================================

    /**
     * @notice 客户购买保险（在 x402 支付后调用）
     * @param requestCommitment 请求唯一标识（与 x402 相同）
     * @param provider 服务商地址
     * @param paymentAmount x402 支付金额（已结算给服务商）
     * @param timeoutMinutes 超时时间（分钟）
     *
     * @dev 注意：
     *      1. x402 支付已经完成，服务商已收到 paymentAmount
     *      2. 这里不收取保险费，而是从服务商 bond 中锁定等额保护金
     *      3. 客户无需额外付费！
     */
    function purchaseInsurance(
        bytes32 requestCommitment,
        address provider,
        uint256 paymentAmount,
        uint256 timeoutMinutes
    ) external {
        if (paymentAmount == 0) revert InvalidAmount();
        if (provider == address(0)) revert ZeroAddress();
        if (claims[requestCommitment].client != address(0)) {
            revert AlreadySettled();
        }
        if (isLiquidated[provider]) revert ProviderIsLiquidated();

        // 检查服务商是否健康
        if (!isProviderHealthy(provider)) {
            revert ProviderUnhealthy();
        }

        // 计算需要锁定的金额（服务费 + 2%罚金）
        uint256 penaltyAmount = paymentAmount * platformPenaltyRate / 10000;
        uint256 totalLockAmount = paymentAmount + penaltyAmount;

        // 检查服务商可用 bond 是否足够
        uint256 totalBond = providerBond[provider];
        uint256 locked = lockedBond[provider];
        uint256 available = totalBond - locked;

        if (available < totalLockAmount) {
            revert InsufficientAvailableBond();
        }

        // 锁定 bond
        lockedBond[provider] += totalLockAmount;

        // 使用默认超时如果未指定
        uint256 timeout = timeoutMinutes > 0 ? timeoutMinutes : defaultTimeout;

        // 记录保险索赔
        claims[requestCommitment] = InsuranceClaim({
            client: msg.sender,
            provider: provider,
            paymentAmount: paymentAmount,
            deadline: block.timestamp + (timeout * 1 minutes),
            status: ClaimStatus.Pending
        });

        emit InsurancePurchased(
            requestCommitment,
            msg.sender,
            provider,
            paymentAmount,
            totalLockAmount,
            block.timestamp + (timeout * 1 minutes)
        );
    }

    /**
     * @notice 服务商确认服务成功（解锁 bond）
     * @param requestCommitment 请求标识
     * @param signature 服务商签名
     *
     * @dev 服务商通过签名证明服务已成功交付
     *      锁定的 bond 将被解锁，服务商保留 x402 收入
     */
    function confirmService(
        bytes32 requestCommitment,
        bytes calldata signature
    ) external {
        InsuranceClaim storage claim = claims[requestCommitment];

        if (claim.status != ClaimStatus.Pending) revert AlreadySettled();

        // 验证服务商签名
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("ServiceConfirmation(bytes32 requestCommitment)"),
                requestCommitment
            )
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = digest.recover(signature);

        if (signer != claim.provider) revert InvalidSignature();

        // 标记为已确认
        claim.status = ClaimStatus.Confirmed;

        // 解锁 bond
        uint256 penaltyAmount = claim.paymentAmount * platformPenaltyRate / 10000;
        uint256 totalLockAmount = claim.paymentAmount + penaltyAmount;

        lockedBond[claim.provider] -= totalLockAmount;

        emit ServiceConfirmed(
            requestCommitment,
            claim.provider,
            totalLockAmount
        );
    }

    /**
     * @notice 客户申领保险赔付（超时后）
     * @param requestCommitment 请求标识
     *
     * @dev 如果服务商在超时时间内未确认，客户可申领赔付
     *      赔付金额从服务商的 bond 中扣除
     *      同时扣除2%罚金给平台
     */
    function claimInsurance(bytes32 requestCommitment) external {
        InsuranceClaim storage claim = claims[requestCommitment];

        if (msg.sender != claim.client) revert Unauthorized();
        if (claim.status != ClaimStatus.Pending) revert AlreadySettled();
        if (block.timestamp <= claim.deadline) revert NotExpired();

        // 计算金额
        uint256 compensationAmount = claim.paymentAmount;
        uint256 penaltyAmount = compensationAmount * platformPenaltyRate / 10000;
        uint256 totalDeduction = compensationAmount + penaltyAmount;

        // 检查服务商 bond 是否足够（应该足够，因为已锁定）
        if (lockedBond[claim.provider] < totalDeduction) {
            revert InsufficientBond();
        }

        // 标记为已赔付
        claim.status = ClaimStatus.Claimed;

        // 从锁定的 bond 中扣除
        lockedBond[claim.provider] -= totalDeduction;
        providerBond[claim.provider] -= totalDeduction;

        // 赔付客户（原始支付金额）
        usdc.safeTransfer(claim.client, compensationAmount);

        // 罚金给平台
        if (penaltyAmount > 0) {
            usdc.safeTransfer(platformTreasury, penaltyAmount);
            emit PlatformPenaltyCollected(requestCommitment, penaltyAmount);
        }

        emit InsuranceClaimed(
            requestCommitment,
            claim.client,
            compensationAmount,
            penaltyAmount
        );
    }

    // =============================================================
    //                      查询接口
    // =============================================================

    /**
     * @notice 获取保险索赔详情
     */
    function getClaimDetails(bytes32 requestCommitment) external view returns (
        address client,
        address provider,
        uint256 paymentAmount,
        uint256 deadline,
        ClaimStatus status,
        uint256 timeLeft
    ) {
        InsuranceClaim memory claim = claims[requestCommitment];

        uint256 remaining = 0;
        if (block.timestamp < claim.deadline) {
            remaining = claim.deadline - block.timestamp;
        }

        return (
            claim.client,
            claim.provider,
            claim.paymentAmount,
            claim.deadline,
            claim.status,
            remaining
        );
    }

    /**
     * @notice 检查客户是否可以申领赔付
     */
    function canClaimInsurance(bytes32 requestCommitment) external view returns (bool) {
        InsuranceClaim memory claim = claims[requestCommitment];

        return claim.status == ClaimStatus.Pending &&
               block.timestamp > claim.deadline &&
               lockedBond[claim.provider] >= claim.paymentAmount;
    }

    /**
     * @notice 获取服务商统计数据
     */
    function getProviderStats(address provider) external view returns (
        uint256 totalBond,
        uint256 lockedAmount,
        uint256 availableBond,
        uint256 minBond,
        bool isHealthy,
        bool liquidated,
        uint256 warningTime,
        uint256 liquidationDeadline,
        bool canBeLiquidated
    ) {
        totalBond = providerBond[provider];
        lockedAmount = lockedBond[provider];
        availableBond = totalBond - lockedAmount;
        minBond = minProviderBond[provider];
        isHealthy = isProviderHealthy(provider);
        liquidated = isLiquidated[provider];
        warningTime = warningTimestamp[provider];

        // 计算清算截止时间
        if (warningTime > 0) {
            liquidationDeadline = warningTime + liquidationGracePeriod;
            canBeLiquidated = block.timestamp >= liquidationDeadline &&
                             lockedBond[provider] == 0 &&
                             availableBond < minBond;
        } else {
            liquidationDeadline = 0;
            canBeLiquidated = false;
        }
    }

    /**
     * @notice 获取保护成本预估
     * @param paymentAmount 支付金额
     * @return totalLockAmount 需要锁定的总金额（含罚金）
     * @return penaltyAmount 罚金金额
     */
    function getProtectionCost(uint256 paymentAmount) external view returns (
        uint256 totalLockAmount,
        uint256 penaltyAmount
    ) {
        penaltyAmount = paymentAmount * platformPenaltyRate / 10000;
        totalLockAmount = paymentAmount + penaltyAmount;
    }

    // =============================================================
    //                      平台管理
    // =============================================================

    /**
     * @notice 更新平台惩罚费率
     */
    function setPlatformPenaltyRate(uint256 newRate) external {
        if (msg.sender != platformTreasury) revert Unauthorized();
        platformPenaltyRate = newRate;
    }

    /**
     * @notice 更新默认超时时间
     */
    function setDefaultTimeout(uint256 newTimeout) external {
        if (msg.sender != platformTreasury) revert Unauthorized();
        defaultTimeout = newTimeout;
    }

    /**
     * @notice 更新平台财务地址
     */
    function setPlatformTreasury(address newTreasury) external {
        if (msg.sender != platformTreasury) revert Unauthorized();
        if (newTreasury == address(0)) revert ZeroAddress();
        platformTreasury = newTreasury;
    }

    /**
     * @notice 更新清算宽限期
     */
    function setLiquidationGracePeriod(uint256 newPeriod) external {
        if (msg.sender != platformTreasury) revert Unauthorized();
        uint256 oldPeriod = liquidationGracePeriod;
        liquidationGracePeriod = newPeriod;
        emit LiquidationGracePeriodUpdated(oldPeriod, newPeriod);
    }

    /**
     * @notice 获取 EIP-712 domain separator
     */
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }
}
