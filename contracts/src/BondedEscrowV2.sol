// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/**
 * @title BondedEscrowV2
 * @notice 增强版托管合约：支持超时退款 + Meta Transaction + 平台手续费
 * @dev 为商业化平台设计的升级版本
 *
 * 新特性:
 * - 支付锁定期：资金先锁定在合约中
 * - 超时自动退款：服务商未确认时客户可自动退款
 * - Meta Transaction：客户签名，平台代付 gas
 * - 平台手续费：成功交易时自动扣除手续费
 * - Gas Tank：从退款中扣除微量补贴
 */
contract BondedEscrowV2 is EIP712 {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    // =============================================================
    //                           STORAGE
    // =============================================================

    /// @notice 合约所有者（服务商）
    address public immutable owner;

    /// @notice ERC20 代币（USDC）
    IERC20 public immutable token;

    /// @notice 服务商签名地址
    address public immutable sellerAddress;

    /// @notice 平台财务地址
    address public immutable platformTreasury;

    /// @notice 平台手续费率（基点，100 = 1%）
    uint256 public platformFeeRate;

    /// @notice 最低保证金
    uint256 public minBond;

    /// @notice Gas tank 余额（用于补贴 relayer）
    uint256 public gasTankBalance;

    /// @notice Gas 补贴金额（每笔退款扣除）
    uint256 public constant GAS_SUBSIDY = 3000; // 0.003 USDC (6 decimals)

    /// @notice 默认超时时间（5 分钟）
    uint256 public constant DEFAULT_TIMEOUT = 5 minutes;

    /// @notice 待处理的支付
    struct PendingPayment {
        address client;          // 客户地址
        uint256 amount;          // 支付金额
        uint256 deadline;        // 超时时间
        bool completed;          // 是否已完成
        bool refunded;           // 是否已退款
    }

    /// @notice 请求承诺 => 待处理支付
    mapping(bytes32 => PendingPayment) public pendingPayments;

    /// @notice 已结算的请求（防止重复）
    mapping(bytes32 => bool) public commitmentSettled;

    /// @notice Meta transaction nonces（防重放）
    mapping(address => uint256) public nonces;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event BondDeposited(address indexed from, uint256 amount);
    event BondWithdrawn(address indexed to, uint256 amount);
    event PaymentLocked(bytes32 indexed requestCommitment, address indexed client, uint256 amount, uint256 deadline);
    event DeliveryConfirmed(bytes32 indexed requestCommitment, address indexed seller, uint256 sellerAmount, uint256 platformFee);
    event RefundIssued(bytes32 indexed requestCommitment, address indexed client, uint256 amount);
    event TimeoutRefund(bytes32 indexed requestCommitment, address indexed client, uint256 amount);
    event MetaRefundClaimed(bytes32 indexed requestCommitment, address indexed client, uint256 amount, uint256 gasSubsidy, address indexed relayer);
    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);
    event MinBondUpdated(uint256 oldMinBond, uint256 newMinBond);
    event GasTankWithdrawn(address indexed to, uint256 amount);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error Unauthorized();
    error InvalidSignature();
    error AlreadySettled();
    error NotExpired();
    error InsufficientBond();
    error ZeroAmount();
    error ZeroAddress();
    error InvalidFeeRate();
    error SignatureExpired();

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    /**
     * @param _token USDC 代币地址
     * @param _sellerAddress 服务商签名地址
     * @param _minBond 最低保证金
     * @param _platformTreasury 平台财务地址
     * @param _platformFeeRate 平台手续费率（基点）
     */
    constructor(
        address _token,
        address _sellerAddress,
        uint256 _minBond,
        address _platformTreasury,
        uint256 _platformFeeRate
    ) EIP712("BondedEscrowV2", "2") {
        if (_token == address(0) || _sellerAddress == address(0) || _platformTreasury == address(0)) {
            revert ZeroAddress();
        }
        if (_minBond == 0) revert ZeroAmount();
        if (_platformFeeRate > 1000) revert InvalidFeeRate(); // 最大 10%

        owner = msg.sender;
        token = IERC20(_token);
        sellerAddress = _sellerAddress;
        platformTreasury = _platformTreasury;
        platformFeeRate = _platformFeeRate;
        minBond = _minBond;
    }

    // =============================================================
    //                         MODIFIERS
    // =============================================================

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyPlatform() {
        if (msg.sender != platformTreasury) revert Unauthorized();
        _;
    }

    // =============================================================
    //                      保证金管理
    // =============================================================

    /**
     * @notice 存入保证金
     */
    function deposit(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit BondDeposited(msg.sender, amount);
    }

    /**
     * @notice 提取保证金（必须保持最低余额）
     */
    function withdraw(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();

        uint256 balance = token.balanceOf(address(this));
        if (balance - amount < minBond) {
            revert InsufficientBond();
        }

        token.safeTransfer(owner, amount);
        emit BondWithdrawn(owner, amount);
    }

    /**
     * @notice 检查 Escrow 健康状态
     */
    function isHealthy() external view returns (bool) {
        return token.balanceOf(address(this)) >= minBond;
    }

    /**
     * @notice 获取当前保证金余额
     */
    function getBondBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    // =============================================================
    //                      支付锁定（新功能）
    // =============================================================

    /**
     * @notice 客户端锁定支付（资金暂存在合约）
     * @param requestCommitment 请求唯一标识
     * @param amount 支付金额
     * @param timeoutMinutes 超时时间（分钟）
     */
    function lockPayment(
        bytes32 requestCommitment,
        uint256 amount,
        uint256 timeoutMinutes
    ) external {
        if (amount == 0) revert ZeroAmount();
        if (commitmentSettled[requestCommitment]) revert AlreadySettled();

        // 转账到合约
        token.safeTransferFrom(msg.sender, address(this), amount);

        // 设置超时时间
        uint256 timeout = timeoutMinutes > 0 ? timeoutMinutes * 1 minutes : DEFAULT_TIMEOUT;

        // 记录待处理支付
        pendingPayments[requestCommitment] = PendingPayment({
            client: msg.sender,
            amount: amount,
            deadline: block.timestamp + timeout,
            completed: false,
            refunded: false
        });

        emit PaymentLocked(requestCommitment, msg.sender, amount, block.timestamp + timeout);
    }

    // =============================================================
    //                      服务交付确认
    // =============================================================

    /**
     * @notice 服务商确认交付，收取款项（扣除平台手续费）
     * @param requestCommitment 请求唯一标识
     * @param signature 服务商签名
     */
    function confirmDelivery(
        bytes32 requestCommitment,
        bytes calldata signature
    ) external {
        PendingPayment storage payment = pendingPayments[requestCommitment];
        if (payment.completed || payment.refunded) revert AlreadySettled();

        // 验证服务商签名
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("DeliveryConfirmation(bytes32 requestCommitment)"),
                requestCommitment
            )
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = digest.recover(signature);
        if (signer != sellerAddress) revert InvalidSignature();

        // 标记为已完成
        payment.completed = true;
        commitmentSettled[requestCommitment] = true;

        // 计算手续费
        uint256 platformFee = payment.amount * platformFeeRate / 10000;
        uint256 sellerAmount = payment.amount - platformFee;

        // 分配资金
        if (platformFee > 0) {
            token.safeTransfer(platformTreasury, platformFee);
        }
        token.safeTransfer(sellerAddress, sellerAmount);

        emit DeliveryConfirmed(requestCommitment, sellerAddress, sellerAmount, platformFee);
    }

    // =============================================================
    //                      服务商主动退款
    // =============================================================

    /**
     * @notice 服务商主动签署退款（服务失败）
     * @param requestCommitment 请求唯一标识
     * @param signature 服务商退款授权签名
     */
    function issueRefund(
        bytes32 requestCommitment,
        bytes calldata signature
    ) external {
        PendingPayment storage payment = pendingPayments[requestCommitment];
        if (payment.completed || payment.refunded) revert AlreadySettled();

        // 验证服务商退款签名
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("RefundClaim(bytes32 requestCommitment,uint256 amount)"),
                requestCommitment,
                payment.amount
            )
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = digest.recover(signature);
        if (signer != sellerAddress) revert InvalidSignature();

        // 标记为已退款
        payment.refunded = true;
        commitmentSettled[requestCommitment] = true;

        // 全额退款给客户
        token.safeTransfer(payment.client, payment.amount);

        emit RefundIssued(requestCommitment, payment.client, payment.amount);
    }

    // =============================================================
    //                      超时自动退款（新功能）
    // =============================================================

    /**
     * @notice 超时后客户端自动退款（无需服务商签名）
     * @param requestCommitment 请求唯一标识
     */
    function claimTimeoutRefund(bytes32 requestCommitment) external {
        PendingPayment storage payment = pendingPayments[requestCommitment];

        if (msg.sender != payment.client) revert Unauthorized();
        if (block.timestamp <= payment.deadline) revert NotExpired();
        if (payment.completed || payment.refunded) revert AlreadySettled();

        // 标记为已退款
        payment.refunded = true;
        commitmentSettled[requestCommitment] = true;

        // 全额退款
        token.safeTransfer(payment.client, payment.amount);

        emit TimeoutRefund(requestCommitment, payment.client, payment.amount);
    }

    // =============================================================
    //                      Meta Transaction 退款（新功能）
    // =============================================================

    /**
     * @notice Meta transaction 退款（客户签名，平台代付 gas）
     * @param requestCommitment 请求唯一标识
     * @param amount 退款金额
     * @param client 客户地址
     * @param deadline 签名过期时间
     * @param clientSignature 客户授权签名
     * @param serverSignature 服务商退款签名
     */
    function metaClaimRefund(
        bytes32 requestCommitment,
        uint256 amount,
        address client,
        uint256 deadline,
        bytes calldata clientSignature,
        bytes calldata serverSignature
    ) external {
        // 1. 检查签名是否过期
        if (block.timestamp > deadline) revert SignatureExpired();

        // 2. 验证客户授权签名
        bytes32 clientStructHash = keccak256(
            abi.encode(
                keccak256("MetaRefund(bytes32 requestCommitment,uint256 amount,address client,uint256 nonce,uint256 deadline)"),
                requestCommitment,
                amount,
                client,
                nonces[client],
                deadline
            )
        );
        bytes32 clientDigest = _hashTypedDataV4(clientStructHash);
        address clientSigner = clientDigest.recover(clientSignature);
        if (clientSigner != client) revert InvalidSignature();

        // 3. 验证服务商退款授权签名
        bytes32 serverStructHash = keccak256(
            abi.encode(
                keccak256("RefundClaim(bytes32 requestCommitment,uint256 amount)"),
                requestCommitment,
                amount
            )
        );
        bytes32 serverDigest = _hashTypedDataV4(serverStructHash);
        address serverSigner = serverDigest.recover(serverSignature);
        if (serverSigner != sellerAddress) revert InvalidSignature();

        // 4. 防止重复退款
        if (commitmentSettled[requestCommitment]) revert AlreadySettled();
        commitmentSettled[requestCommitment] = true;
        nonces[client]++;

        // 5. 计算分配（扣除 gas 补贴）
        uint256 gasSubsidy = GAS_SUBSIDY;
        if (amount <= gasSubsidy) {
            gasSubsidy = 0; // 金额太小，不扣除
        }
        uint256 clientReceives = amount - gasSubsidy;

        // 6. 执行退款
        token.safeTransfer(client, clientReceives);
        gasTankBalance += gasSubsidy;

        emit MetaRefundClaimed(requestCommitment, client, clientReceives, gasSubsidy, msg.sender);
    }

    // =============================================================
    //                      Gas Tank 管理
    // =============================================================

    /**
     * @notice 平台提取 gas tank 用于补贴 relayer
     */
    function withdrawGasTank(uint256 amount) external onlyPlatform {
        if (amount > gasTankBalance) revert InsufficientBond();
        gasTankBalance -= amount;
        token.safeTransfer(platformTreasury, amount);
        emit GasTankWithdrawn(platformTreasury, amount);
    }

    // =============================================================
    //                      平台管理
    // =============================================================

    /**
     * @notice 更新平台手续费率
     */
    function setPlatformFee(uint256 newFeeRate) external onlyPlatform {
        if (newFeeRate > 1000) revert InvalidFeeRate(); // 最大 10%
        uint256 oldFee = platformFeeRate;
        platformFeeRate = newFeeRate;
        emit PlatformFeeUpdated(oldFee, newFeeRate);
    }

    /**
     * @notice 更新最低保证金
     */
    function setMinBond(uint256 _minBond) external onlyOwner {
        if (_minBond == 0) revert ZeroAmount();
        uint256 oldMinBond = minBond;
        minBond = _minBond;
        emit MinBondUpdated(oldMinBond, _minBond);
    }

    /**
     * @notice 获取 EIP-712 domain separator
     */
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }
}
