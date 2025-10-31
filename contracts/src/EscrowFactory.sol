// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./BondedEscrowV2.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title EscrowFactory
 * @notice X402 Guard 平台核心合约 - 为服务商创建和管理 Escrow 合约
 * @dev 工厂模式实现，统一管理所有服务商的 Escrow 合约
 *
 * 功能:
 * - 服务商一键注册创建 Escrow
 * - 统一收取平台手续费
 * - 管理服务商认证状态
 * - 提供 Escrow 查询接口
 */
contract EscrowFactory is Ownable {
    // =============================================================
    //                           STORAGE
    // =============================================================

    /// @notice USDC 代币地址（所有 Escrow 使用同一代币）
    address public immutable usdcAddress;

    /// @notice 平台财务地址（接收手续费）
    address public platformTreasury;

    /// @notice 平台默认手续费率（基点，200 = 2%）
    uint256 public defaultPlatformFeeRate;

    /// @notice 默认最低保证金（100 USDC = 100_000_000）
    uint256 public defaultMinBond;

    /// @notice 服务商地址 => Escrow 合约地址
    mapping(address => address) public providerToEscrow;

    /// @notice Escrow 合约地址 => 服务商地址（反向查询）
    mapping(address => address) public escrowToProvider;

    /// @notice 所有 Escrow 合约列表
    address[] public allEscrows;

    /// @notice 认证服务商（可享受费率优惠等特权）
    mapping(address => bool) public isVerifiedProvider;

    /// @notice 服务商认证等级 => 费率折扣（基点）
    mapping(address => uint256) public providerFeeDiscount;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event EscrowCreated(
        address indexed provider,
        address indexed escrow,
        address indexed sellerAddress,
        uint256 minBond,
        uint256 feeRate
    );

    event ProviderVerified(address indexed provider, bool verified);
    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);
    event PlatformTreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event DefaultMinBondUpdated(uint256 oldBond, uint256 newBond);
    event FeeDiscountSet(address indexed provider, uint256 discount);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error AlreadyRegistered();
    error NotRegistered();
    error ZeroAddress();
    error InvalidFeeRate();
    error InvalidDiscount();

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    /**
     * @param _usdcAddress USDC 代币地址
     * @param _platformTreasury 平台财务地址
     * @param _defaultFeeRate 默认手续费率（基点）
     * @param _defaultMinBond 默认最低保证金
     */
    constructor(
        address _usdcAddress,
        address _platformTreasury,
        uint256 _defaultFeeRate,
        uint256 _defaultMinBond
    ) Ownable(msg.sender) {
        if (_usdcAddress == address(0) || _platformTreasury == address(0)) {
            revert ZeroAddress();
        }
        if (_defaultFeeRate > 1000) revert InvalidFeeRate(); // 最大 10%

        usdcAddress = _usdcAddress;
        platformTreasury = _platformTreasury;
        defaultPlatformFeeRate = _defaultFeeRate;
        defaultMinBond = _defaultMinBond;
    }

    // =============================================================
    //                      服务商注册
    // =============================================================

    /**
     * @notice 服务商注册并创建 Escrow 合约
     * @param sellerAddress 服务商签名地址（用于签署退款授权）
     * @param minBond 最低保证金（可自定义，但不能低于平台要求）
     * @return escrow 创建的 Escrow 合约地址
     */
    function createEscrow(
        address sellerAddress,
        uint256 minBond
    ) external returns (address escrow) {
        // 检查是否已注册
        if (providerToEscrow[msg.sender] != address(0)) {
            revert AlreadyRegistered();
        }

        // 检查参数
        if (sellerAddress == address(0)) revert ZeroAddress();
        if (minBond < defaultMinBond) {
            minBond = defaultMinBond; // 使用平台默认值
        }

        // 计算实际费率（考虑折扣）
        uint256 feeRate = defaultPlatformFeeRate;
        uint256 discount = providerFeeDiscount[msg.sender];
        if (discount > 0 && discount < feeRate) {
            feeRate -= discount;
        }

        // 创建 Escrow 合约
        BondedEscrowV2 newEscrow = new BondedEscrowV2(
            usdcAddress,
            sellerAddress,
            minBond,
            platformTreasury,
            feeRate
        );

        escrow = address(newEscrow);

        // 记录映射关系
        providerToEscrow[msg.sender] = escrow;
        escrowToProvider[escrow] = msg.sender;
        allEscrows.push(escrow);

        emit EscrowCreated(msg.sender, escrow, sellerAddress, minBond, feeRate);
    }

    /**
     * @notice 批量创建 Escrow（用于迁移或批量入驻）
     * @param providers 服务商地址数组
     * @param sellerAddresses 签名地址数组
     * @param minBonds 最低保证金数组
     */
    function batchCreateEscrow(
        address[] calldata providers,
        address[] calldata sellerAddresses,
        uint256[] calldata minBonds
    ) external onlyOwner returns (address[] memory escrows) {
        require(
            providers.length == sellerAddresses.length &&
            providers.length == minBonds.length,
            "Length mismatch"
        );

        escrows = new address[](providers.length);

        for (uint256 i = 0; i < providers.length; i++) {
            if (providerToEscrow[providers[i]] != address(0)) {
                continue; // 跳过已注册的
            }

            uint256 minBond = minBonds[i] < defaultMinBond ? defaultMinBond : minBonds[i];
            uint256 feeRate = defaultPlatformFeeRate - providerFeeDiscount[providers[i]];

            BondedEscrowV2 newEscrow = new BondedEscrowV2(
                usdcAddress,
                sellerAddresses[i],
                minBond,
                platformTreasury,
                feeRate
            );

            escrows[i] = address(newEscrow);
            providerToEscrow[providers[i]] = escrows[i];
            escrowToProvider[escrows[i]] = providers[i];
            allEscrows.push(escrows[i]);

            emit EscrowCreated(providers[i], escrows[i], sellerAddresses[i], minBond, feeRate);
        }
    }

    // =============================================================
    //                      查询接口
    // =============================================================

    /**
     * @notice 获取服务商的 Escrow 地址
     */
    function getEscrow(address provider) external view returns (address) {
        address escrow = providerToEscrow[provider];
        if (escrow == address(0)) revert NotRegistered();
        return escrow;
    }

    /**
     * @notice 根据 Escrow 地址查询服务商
     */
    function getProvider(address escrow) external view returns (address) {
        address provider = escrowToProvider[escrow];
        if (provider == address(0)) revert NotRegistered();
        return provider;
    }

    /**
     * @notice 获取所有 Escrow 合约数量
     */
    function getEscrowCount() external view returns (uint256) {
        return allEscrows.length;
    }

    /**
     * @notice 分页获取 Escrow 列表
     */
    function getEscrows(uint256 offset, uint256 limit) external view returns (address[] memory) {
        uint256 total = allEscrows.length;
        if (offset >= total) {
            return new address[](0);
        }

        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }

        address[] memory result = new address[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = allEscrows[i];
        }

        return result;
    }

    /**
     * @notice 检查地址是否已注册
     */
    function isRegistered(address provider) external view returns (bool) {
        return providerToEscrow[provider] != address(0);
    }

    /**
     * @notice 批量查询 Escrow 信息
     */
    function getEscrowInfo(address escrow) external view returns (
        address provider,
        address seller,
        uint256 balance,
        uint256 minBond,
        bool isHealthy,
        uint256 feeRate
    ) {
        provider = escrowToProvider[escrow];
        if (provider == address(0)) revert NotRegistered();

        BondedEscrowV2 escrowContract = BondedEscrowV2(escrow);
        seller = escrowContract.sellerAddress();
        balance = escrowContract.getBondBalance();
        minBond = escrowContract.minBond();
        isHealthy = escrowContract.isHealthy();
        feeRate = escrowContract.platformFeeRate();
    }

    // =============================================================
    //                      平台管理
    // =============================================================

    /**
     * @notice 认证服务商（可获得费率优惠）
     */
    function verifyProvider(address provider, bool verified) external onlyOwner {
        isVerifiedProvider[provider] = verified;
        emit ProviderVerified(provider, verified);
    }

    /**
     * @notice 批量认证服务商
     */
    function batchVerifyProviders(address[] calldata providers, bool verified) external onlyOwner {
        for (uint256 i = 0; i < providers.length; i++) {
            isVerifiedProvider[providers[i]] = verified;
            emit ProviderVerified(providers[i], verified);
        }
    }

    /**
     * @notice 设置服务商费率折扣
     * @param provider 服务商地址
     * @param discount 折扣（基点，例如 50 = 0.5% 折扣）
     */
    function setFeeDiscount(address provider, uint256 discount) external onlyOwner {
        if (discount >= defaultPlatformFeeRate) revert InvalidDiscount();
        providerFeeDiscount[provider] = discount;
        emit FeeDiscountSet(provider, discount);
    }

    /**
     * @notice 更新默认平台手续费率
     */
    function setDefaultPlatformFee(uint256 newFeeRate) external onlyOwner {
        if (newFeeRate > 1000) revert InvalidFeeRate(); // 最大 10%
        uint256 oldFee = defaultPlatformFeeRate;
        defaultPlatformFeeRate = newFeeRate;
        emit PlatformFeeUpdated(oldFee, newFeeRate);
    }

    /**
     * @notice 更新平台财务地址
     */
    function setPlatformTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert ZeroAddress();
        address oldTreasury = platformTreasury;
        platformTreasury = newTreasury;
        emit PlatformTreasuryUpdated(oldTreasury, newTreasury);
    }

    /**
     * @notice 更新默认最低保证金
     */
    function setDefaultMinBond(uint256 newMinBond) external onlyOwner {
        uint256 oldBond = defaultMinBond;
        defaultMinBond = newMinBond;
        emit DefaultMinBondUpdated(oldBond, newMinBond);
    }

    // =============================================================
    //                      统计数据
    // =============================================================

    /**
     * @notice 获取平台统计数据
     */
    function getPlatformStats() external view returns (
        uint256 totalProviders,
        uint256 verifiedProviders,
        uint256 totalBondLocked,
        uint256 avgFeeRate
    ) {
        totalProviders = allEscrows.length;

        // 统计认证服务商数量
        for (uint256 i = 0; i < allEscrows.length; i++) {
            address provider = escrowToProvider[allEscrows[i]];
            if (isVerifiedProvider[provider]) {
                verifiedProviders++;
            }
        }

        // 统计总锁定保证金
        IERC20 usdc = IERC20(usdcAddress);
        for (uint256 i = 0; i < allEscrows.length; i++) {
            totalBondLocked += usdc.balanceOf(allEscrows[i]);
        }

        // 平均费率
        avgFeeRate = defaultPlatformFeeRate;
    }
}
