// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/**
 * @title PaymentContractWithInsurance
 * @notice 示例：一个集成了保险功能的支付合约
 * @dev 展示业务合约如何直接成为 Insurance Provider
 */
contract PaymentContractWithInsurance {

    // ==================== 保险相关 ====================
    address public constant INSURANCE_V8 = 0x72486eF40BB3729298369d608de85c612adb223e;
    address public constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    // ==================== 业务相关 ====================
    address public owner;
    bool public insuranceEnabled;

    struct Order {
        address client;
        uint256 amount;
        uint256 createdAt;
        uint256 deliveredAt;
        bool delivered;
        bool refunded;
    }

    mapping(bytes32 => Order) public orders;
    bytes32[] public orderList;

    // ==================== 事件 ====================
    event OrderCreated(bytes32 indexed orderId, address client, uint256 amount);
    event OrderDelivered(bytes32 indexed orderId);
    event OrderRefunded(bytes32 indexed orderId, uint256 amount);
    event InsuranceEnabled(uint256 amount);
    event ClaimDisputed(bytes32 indexed commitment, string evidence);

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    // ==================== 业务逻辑 ====================

    /**
     * 创建订单
     * @param orderId 订单ID
     * @param client 客户地址
     * @param amount 订单金额（USDC）
     */
    function createOrder(
        bytes32 orderId,
        address client,
        uint256 amount
    ) external onlyOwner {
        require(orders[orderId].client == address(0), "Order exists");

        orders[orderId] = Order({
            client: client,
            amount: amount,
            createdAt: block.timestamp,
            deliveredAt: 0,
            delivered: false,
            refunded: false
        });

        orderList.push(orderId);

        emit OrderCreated(orderId, client, amount);
    }

    /**
     * 标记订单已交付
     * @param orderId 订单ID
     */
    function deliverOrder(bytes32 orderId) external onlyOwner {
        Order storage order = orders[orderId];
        require(order.client != address(0), "Order not found");
        require(!order.delivered, "Already delivered");

        order.delivered = true;
        order.deliveredAt = block.timestamp;

        emit OrderDelivered(orderId);
    }

    /**
     * 批量交付
     * @param orderIds 订单ID数组
     */
    function batchDeliverOrders(bytes32[] calldata orderIds) external onlyOwner {
        for (uint256 i = 0; i < orderIds.length; i++) {
            Order storage order = orders[orderIds[i]];
            if (order.client != address(0) && !order.delivered) {
                order.delivered = true;
                order.deliveredAt = block.timestamp;
                emit OrderDelivered(orderIds[i]);
            }
        }
    }

    // ==================== 保险功能 ====================

    /**
     * 启用保险功能
     * @param initialAmount 初始保险金额（USDC，6位小数）
     *
     * 使用说明：
     * 1. 先向本合约转入 USDC
     * 2. 调用此函数激活保险
     */
    function enableInsurance(uint256 initialAmount) external onlyOwner {
        require(!insuranceEnabled, "Insurance already enabled");
        require(initialAmount >= 10 * 10**6, "Minimum 10 USDC");

        // 授权 USDC 给 Insurance V8
        require(
            IERC20(USDC).approve(INSURANCE_V8, initialAmount),
            "Approve failed"
        );

        // 注册为 Provider
        // 重要：msg.sender 此时是本合约地址！
        IInsurance(INSURANCE_V8).registerOrReactivate(initialAmount);

        insuranceEnabled = true;

        emit InsuranceEnabled(initialAmount);
    }

    /**
     * 追加保险金
     * @param amount 追加金额
     */
    function addInsurance(uint256 amount) external onlyOwner {
        require(insuranceEnabled, "Insurance not enabled");

        IERC20(USDC).approve(INSURANCE_V8, amount);
        IInsurance(INSURANCE_V8).depositAdditional(amount);
    }

    /**
     * 提取保险金
     * @param amount 提取金额
     */
    function withdrawInsurance(uint256 amount) external onlyOwner {
        require(insuranceEnabled, "Insurance not enabled");
        IInsurance(INSURANCE_V8).withdraw(amount);
    }

    /**
     * 处理索赔
     * @param claimCommitment 索赔ID（由客户在 Insurance V8 中发起）
     * @param orderId 对应的订单ID
     *
     * 工作流程：
     * 1. 客户在 Insurance V8 发起索赔，使用 claimCommitment
     * 2. 我们根据 orderId 检查订单是否已交付
     * 3. 如果已交付，自动争议索赔
     */
    function handleClaim(
        bytes32 claimCommitment,
        bytes32 orderId
    ) external onlyOwner {
        require(insuranceEnabled, "Insurance not enabled");

        Order memory order = orders[orderId];
        require(order.client != address(0), "Order not found");

        if (order.delivered) {
            // 订单已交付，争议索赔
            string memory evidence = string(
                abi.encodePacked(
                    "Order ",
                    toHexString(orderId),
                    " was delivered at timestamp ",
                    uint2str(order.deliveredAt)
                )
            );

            IInsurance(INSURANCE_V8).disputeClaim(claimCommitment, evidence);

            emit ClaimDisputed(claimCommitment, evidence);
        }
        // 如果订单未交付，不做任何事，接受索赔
    }

    /**
     * 批量处理索赔
     * @param claims 索赔数组
     */
    function batchHandleClaims(
        ClaimData[] calldata claims
    ) external onlyOwner {
        for (uint256 i = 0; i < claims.length; i++) {
            Order memory order = orders[claims[i].orderId];

            if (order.client != address(0) && order.delivered) {
                string memory evidence = string(
                    abi.encodePacked(
                        "Order delivered at ",
                        uint2str(order.deliveredAt)
                    )
                );

                IInsurance(INSURANCE_V8).disputeClaim(
                    claims[i].commitment,
                    evidence
                );
            }
        }
    }

    struct ClaimData {
        bytes32 commitment;
        bytes32 orderId;
    }

    // ==================== 查询功能 ====================

    /**
     * 获取订单信息
     */
    function getOrder(bytes32 orderId)
        external
        view
        returns (
            address client,
            uint256 amount,
            uint256 createdAt,
            uint256 deliveredAt,
            bool delivered,
            bool refunded
        )
    {
        Order memory order = orders[orderId];
        return (
            order.client,
            order.amount,
            order.createdAt,
            order.deliveredAt,
            order.delivered,
            order.refunded
        );
    }

    /**
     * 获取所有订单
     */
    function getAllOrders() external view returns (bytes32[] memory) {
        return orderList;
    }

    /**
     * 获取保险池状态
     */
    function getInsuranceStatus()
        external
        view
        returns (
            bool isActive,
            uint256 poolBalance,
            uint256 totalLocked,
            uint256 successfulServices,
            uint256 failedServices,
            uint8 tier
        )
    {
        if (!insuranceEnabled) {
            return (false, 0, 0, 0, 0, 0);
        }

        (
            bool active,
            uint256 pool,
            uint256 locked,
            uint256 successful,
            uint256 failed,
            uint8 tierLevel,

        ) = IInsurance(INSURANCE_V8).getProviderInfo(address(this));

        return (active, pool, locked, successful, failed, tierLevel);
    }

    // ==================== 工具函数 ====================

    function uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    function toHexString(bytes32 data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            str[i * 2] = alphabet[uint8(data[i] >> 4)];
            str[1 + i * 2] = alphabet[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }

    /**
     * 接收 USDC
     */
    function depositUSDC(uint256 amount) external {
        require(
            IERC20(USDC).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
    }
}

// ==================== 接口定义 ====================

interface IInsurance {
    function registerOrReactivate(uint256 amount) external;
    function depositAdditional(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function disputeClaim(bytes32 commitment, string memory evidence) external;
    function getProviderInfo(address provider)
        external
        view
        returns (
            bool isActive,
            uint256 poolBalance,
            uint256 totalLocked,
            uint256 successfulServices,
            uint256 failedServices,
            uint8 tier,
            uint256 registeredAt
        );
}

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount)
        external
        returns (bool);
    function balanceOf(address account) external view returns (uint256);
}
