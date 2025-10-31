// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/**
 * @title X402Insurance
 * @notice 为 x402 支付提供可选的保险保护层
 * @dev 完全兼容原生 x402 协议，不干预正常支付流程
 *
 * 工作原理:
 * 1. x402 正常结算 - 服务商立即收到支付
 * 2. 客户额外支付小额保险费（如 1%）- 锁定在合约
 * 3. 服务成功 - 保险费作为奖励给服务商
 * 4. 服务失败/超时 - 从服务商 bond 中赔付客户
 *
 * 优势:
 * - ✅ 不改变 x402 协议
 * - ✅ 服务商立即收款
 * - ✅ 客户有保险保障
 * - ✅ 可选使用（不强制）
 */
contract X402Insurance is EIP712 {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    // =============================================================
    //                           STORAGE
    // =============================================================

    /// @notice USDC 代币
    IERC20 public immutable usdc;

    /// @notice 平台财务地址
    address public platformTreasury;

    /// @notice 平台从保险费中收取的比例（基点，100 = 1%）
    uint256 public platformFeeRate;

    /// @notice 默认超时时间（分钟）
    uint256 public defaultTimeout;

    /// @notice 服务商保证金余额
    mapping(address => uint256) public providerBond;

    /// @notice 服务商最低保证金要求
    mapping(address => uint256) public minProviderBond;

    /// @notice 保险索赔记录
    mapping(bytes32 => InsuranceClaim) public claims;

    /// @notice 保险索赔状态
    struct InsuranceClaim {
        address client;             // 客户地址
        address provider;           // 服务商地址
        uint256 paymentAmount;      // 原始支付金额（已通过 x402 结算）
        uint256 insuranceFee;       // 保险费（锁定在合约）
        uint256 deadline;           // 超时时间
        ClaimStatus status;         // 状态
    }

    enum ClaimStatus {
        Pending,      // 待处理
        Confirmed,    // 服务成功（保险费给服务商）
        Claimed       // 已赔付（从 bond 赔付客户）
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

    // =============================================================
    //                            ERRORS
    // =============================================================

    error Unauthorized();
    error InvalidAmount();
    error InsufficientBond();
    error AlreadySettled();
    error NotExpired();
    error InvalidSignature();
    error ZeroAddress();

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    constructor(
        address _usdc,
        address _platformTreasury,
        uint256 _platformFeeRate,
        uint256 _defaultTimeout
    ) EIP712("X402Insurance", "1") {
        if (_usdc == address(0) || _platformTreasury == address(0)) {
            revert ZeroAddress();
        }

        usdc = IERC20(_usdc);
        platformTreasury = _platformTreasury;
        platformFeeRate = _platformFeeRate;
        defaultTimeout = _defaultTimeout;
    }

    // =============================================================
    //                      服务商 BOND 管理
    // =============================================================

    /**
     * @notice 服务商存入保证金
     */
    function depositBond(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();

        usdc.safeTransferFrom(msg.sender, address(this), amount);
        providerBond[msg.sender] += amount;

        emit BondDeposited(msg.sender, amount);
    }

    /**
     * @notice 服务商提取保证金（必须满足最低要求）
     */
    function withdrawBond(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();

        uint256 currentBond = providerBond[msg.sender];
        uint256 minBond = minProviderBond[msg.sender];

        if (currentBond - amount < minBond) {
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
     * @notice 检查服务商是否有足够保证金
     */
    function isProviderHealthy(address provider) external view returns (bool) {
        return providerBond[provider] >= minProviderBond[provider];
    }

    // =============================================================
    //                      保险购买和索赔
    // =============================================================

    /**
     * @notice 客户购买保险（在 x402 支付后调用）
     * @param requestCommitment 请求唯一标识（与 x402 相同）
     * @param provider 服务商地址
     * @param paymentAmount x402 支付金额（已结算给服务商）
     * @param insuranceFee 保险费（额外支付）
     * @param timeoutMinutes 超时时间（分钟）
     *
     * @dev 注意：x402 支付已经完成，服务商已收到 paymentAmount
     *      这里只是额外收取保险费并记录索赔窗口
     */
    function purchaseInsurance(
        bytes32 requestCommitment,
        address provider,
        uint256 paymentAmount,
        uint256 insuranceFee,
        uint256 timeoutMinutes
    ) external {
        if (insuranceFee == 0) revert InvalidAmount();
        if (provider == address(0)) revert ZeroAddress();
        if (claims[requestCommitment].client != address(0)) revert AlreadySettled();

        // 检查服务商有足够 bond
        if (providerBond[provider] < paymentAmount) {
            revert InsufficientBond();
        }

        // 收取保险费
        usdc.safeTransferFrom(msg.sender, address(this), insuranceFee);

        // 使用默认超时如果未指定
        uint256 timeout = timeoutMinutes > 0 ? timeoutMinutes : defaultTimeout;

        // 记录保险索赔
        claims[requestCommitment] = InsuranceClaim({
            client: msg.sender,
            provider: provider,
            paymentAmount: paymentAmount,
            insuranceFee: insuranceFee,
            deadline: block.timestamp + (timeout * 1 minutes),
            status: ClaimStatus.Pending
        });

        emit InsurancePurchased(
            requestCommitment,
            msg.sender,
            provider,
            paymentAmount,
            insuranceFee,
            block.timestamp + (timeout * 1 minutes)
        );
    }

    /**
     * @notice 服务商确认服务成功（获得保险费奖励）
     * @param requestCommitment 请求标识
     * @param signature 服务商签名
     *
     * @dev 服务商通过签名证明服务已成功交付
     *      保险费的一部分作为奖励给服务商，剩余给平台
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

        // 分配保险费
        uint256 platformFee = claim.insuranceFee * platformFeeRate / 10000;
        uint256 providerReward = claim.insuranceFee - platformFee;

        // 转账
        if (platformFee > 0) {
            usdc.safeTransfer(platformTreasury, platformFee);
            emit PlatformFeeCollected(requestCommitment, platformFee);
        }

        usdc.safeTransfer(claim.provider, providerReward);

        emit ServiceConfirmed(requestCommitment, claim.provider, providerReward);
    }

    /**
     * @notice 客户申领保险赔付（超时后）
     * @param requestCommitment 请求标识
     *
     * @dev 如果服务商在超时时间内未确认，客户可申领赔付
     *      赔付金额从服务商的 bond 中扣除
     *      保险费退还给客户
     */
    function claimInsurance(bytes32 requestCommitment) external {
        InsuranceClaim storage claim = claims[requestCommitment];

        if (msg.sender != claim.client) revert Unauthorized();
        if (claim.status != ClaimStatus.Pending) revert AlreadySettled();
        if (block.timestamp <= claim.deadline) revert NotExpired();

        // 检查服务商 bond 是否足够
        if (providerBond[claim.provider] < claim.paymentAmount) {
            revert InsufficientBond();
        }

        // 标记为已赔付
        claim.status = ClaimStatus.Claimed;

        // 从服务商 bond 中扣除
        providerBond[claim.provider] -= claim.paymentAmount;

        // 赔付客户（原始支付金额）
        usdc.safeTransfer(claim.client, claim.paymentAmount);

        // 退还保险费
        usdc.safeTransfer(claim.client, claim.insuranceFee);

        emit InsuranceClaimed(requestCommitment, claim.client, claim.paymentAmount);
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
        uint256 insuranceFee,
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
            claim.insuranceFee,
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
               providerBond[claim.provider] >= claim.paymentAmount;
    }

    /**
     * @notice 获取服务商统计数据
     */
    function getProviderStats(address provider) external view returns (
        uint256 bondBalance,
        uint256 minBond,
        bool isHealthy
    ) {
        bondBalance = providerBond[provider];
        minBond = minProviderBond[provider];
        isHealthy = bondBalance >= minBond;
    }

    // =============================================================
    //                      平台管理
    // =============================================================

    /**
     * @notice 更新平台手续费率
     */
    function setPlatformFeeRate(uint256 newRate) external {
        if (msg.sender != platformTreasury) revert Unauthorized();
        platformFeeRate = newRate;
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
     * @notice 获取 EIP-712 domain separator
     */
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }
}
