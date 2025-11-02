// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IProviderContract
 * @notice Provider合约需要实现的接口，用于与X402Insurance交互
 */
interface IProviderContract {
    /**
     * @notice 当收到索赔通知时被调用
     * @param commitment 索赔ID
     * @param client 客户地址
     * @param amount 索赔金额
     * @param reason 索赔原因
     * @return 是否接受索赔
     */
    function onClaimNotification(
        bytes32 commitment,
        address client,
        uint256 amount,
        uint8 reason
    ) external returns (bool);

    /**
     * @notice 当收到补偿时被调用
     * @param commitment 索赔ID
     * @param amount 补偿金额
     */
    function onCompensationReceived(
        bytes32 commitment,
        uint256 amount
    ) external;

    /**
     * @notice 验证合约是否支持Provider功能
     * @return 返回固定的魔术值确认支持
     */
    function supportsProviderInterface() external pure returns (bytes4);
}

/**
 * @title ProviderContractBase
 * @notice Provider合约的基础实现
 */
abstract contract ProviderContractBase is IProviderContract {

    // 魔术值，用于验证接口支持
    bytes4 constant PROVIDER_INTERFACE_ID = 0x12345678;

    // X402Insurance合约地址
    address public immutable insuranceContract;

    // 合约所有者
    address public owner;

    // 事件
    event ClaimReceived(bytes32 indexed commitment, address client, uint256 amount);
    event CompensationReceived(bytes32 indexed commitment, uint256 amount);
    event InsuranceRegistered(uint256 amount);
    event InsuranceDeposited(uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    /**
     * @notice 转移合约所有权
     * @param newOwner 新所有者地址
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "New owner is zero address");
        owner = newOwner;
    }

    modifier onlyInsurance() {
        require(msg.sender == insuranceContract, "Only insurance contract");
        _;
    }

    constructor(address _insuranceContract) {
        insuranceContract = _insuranceContract;
        owner = msg.sender;
    }

    /**
     * @notice 验证接口支持
     */
    function supportsProviderInterface() external pure override returns (bytes4) {
        return PROVIDER_INTERFACE_ID;
    }

    /**
     * @notice 注册为Provider
     * @param amount USDC金额
     */
    function registerAsProvider(uint256 amount) external onlyOwner {
        // 1. 授权USDC给Insurance合约
        IERC20 usdc = IERC20(IInsurance(insuranceContract).usdcToken());
        require(usdc.approve(insuranceContract, amount), "Approve failed");

        // 2. 调用注册
        IInsurance(insuranceContract).registerOrReactivate(amount);

        emit InsuranceRegistered(amount);
    }

    /**
     * @notice 追加保险金
     * @param amount USDC金额
     */
    function depositInsurance(uint256 amount) external onlyOwner {
        IERC20 usdc = IERC20(IInsurance(insuranceContract).usdcToken());
        require(usdc.approve(insuranceContract, amount), "Approve failed");

        IInsurance(insuranceContract).depositAdditional(amount);

        emit InsuranceDeposited(amount);
    }

    /**
     * @notice 提取保险金
     * @param amount USDC金额
     */
    function withdrawInsurance(uint256 amount) external onlyOwner {
        IInsurance(insuranceContract).withdraw(amount);
    }

    /**
     * @notice 处理索赔通知（子合约实现具体逻辑）
     */
    function onClaimNotification(
        bytes32 commitment,
        address client,
        uint256 amount,
        uint8 reason
    ) external virtual override onlyInsurance returns (bool) {
        emit ClaimReceived(commitment, client, amount);

        // 子合约可以覆盖此方法实现自定义逻辑
        return _handleClaim(commitment, client, amount, reason);
    }

    /**
     * @notice 处理补偿通知
     */
    function onCompensationReceived(
        bytes32 commitment,
        uint256 amount
    ) external virtual override onlyInsurance {
        emit CompensationReceived(commitment, amount);

        // 子合约可以覆盖此方法实现自定义逻辑
        _handleCompensation(commitment, amount);
    }

    // 子合约需要实现的抽象方法
    function _handleClaim(
        bytes32 commitment,
        address client,
        uint256 amount,
        uint8 reason
    ) internal virtual returns (bool);

    function _handleCompensation(
        bytes32 commitment,
        uint256 amount
    ) internal virtual;
}

/**
 * @title SimpleProviderContract
 * @notice Provider合约的简单实现示例
 */
contract SimpleProviderContract is ProviderContractBase {

    // 存储索赔记录
    mapping(bytes32 => bool) public claimDisputes;

    constructor(address _insuranceContract)
        ProviderContractBase(_insuranceContract)
    {}

    /**
     * @notice 处理索赔（自动接受或基于条件判断）
     */
    function _handleClaim(
        bytes32 commitment,
        address client,
        uint256 amount,
        uint8 reason
    ) internal override returns (bool) {
        // 示例：金额小于100 USDC自动接受
        if (amount <= 100 * 10**6) {
            return true;
        }

        // 大额索赔可能需要人工审核
        // 这里可以添加更复杂的逻辑
        return false;
    }

    /**
     * @notice 处理补偿
     */
    function _handleCompensation(
        bytes32 commitment,
        uint256 amount
    ) internal override {
        // 记录补偿，可能触发其他业务逻辑
        // 比如更新内部账本、通知其他系统等
    }

    /**
     * @notice 手动争议索赔
     */
    function disputeClaim(
        bytes32 commitment,
        string memory evidence
    ) external onlyOwner {
        IInsurance(insuranceContract).disputeClaim(commitment, evidence);
        claimDisputes[commitment] = true;
    }
}

/**
 * @title AutomatedProviderContract
 * @notice 全自动Provider合约示例
 */
contract AutomatedProviderContract is ProviderContractBase {

    // 服务验证合约地址
    address public serviceValidator;

    // 自动补充保险金的阈值
    uint256 public autoRefillThreshold = 50 * 10**6; // 50 USDC
    uint256 public autoRefillAmount = 100 * 10**6;   // 100 USDC

    constructor(
        address _insuranceContract,
        address _serviceValidator
    ) ProviderContractBase(_insuranceContract) {
        serviceValidator = _serviceValidator;
    }

    /**
     * @notice 自动处理索赔
     */
    function _handleClaim(
        bytes32 commitment,
        address client,
        uint256 amount,
        uint8 reason
    ) internal override returns (bool) {
        // 调用外部验证合约检查服务是否真的未交付
        if (serviceValidator != address(0)) {
            bool isValid = IServiceValidator(serviceValidator)
                .validateClaim(commitment, client, amount, reason);

            if (!isValid) {
                // 如果验证失败，自动争议
                _autoDispute(commitment, "Service was delivered according to validator");
                return false;
            }
        }

        // 验证通过，接受索赔
        return true;
    }

    /**
     * @notice 处理补偿，可能触发自动补充
     */
    function _handleCompensation(
        bytes32 commitment,
        uint256 amount
    ) internal override {
        // 检查余额，如果低于阈值则自动补充
        _checkAndRefill();
    }

    /**
     * @notice 自动争议
     */
    function _autoDispute(bytes32 commitment, string memory evidence) private {
        IInsurance(insuranceContract).disputeClaim(commitment, evidence);
    }

    /**
     * @notice 检查并自动补充保险金
     */
    function _checkAndRefill() private {
        (
            bool isActive,
            uint256 poolBalance,
            uint256 totalLocked,
            ,,,
        ) = IInsurance(insuranceContract).getProviderInfo(address(this));

        if (isActive && poolBalance < autoRefillThreshold) {
            // 需要补充保险金
            IERC20 usdc = IERC20(IInsurance(insuranceContract).usdcToken());
            uint256 balance = usdc.balanceOf(address(this));

            if (balance >= autoRefillAmount) {
                usdc.approve(insuranceContract, autoRefillAmount);
                IInsurance(insuranceContract).depositAdditional(autoRefillAmount);
            }
        }
    }

    /**
     * @notice 设置自动补充参数
     */
    function setAutoRefillParams(
        uint256 _threshold,
        uint256 _amount
    ) external onlyOwner {
        autoRefillThreshold = _threshold;
        autoRefillAmount = _amount;
    }

    /**
     * @notice 接收USDC（用于自动补充）
     */
    function depositUSDC(uint256 amount) external {
        IERC20 usdc = IERC20(IInsurance(insuranceContract).usdcToken());
        require(
            usdc.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
    }
}

// 接口定义
interface IInsurance {
    function registerOrReactivate(uint256 amount) external;
    function depositAdditional(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function disputeClaim(bytes32 commitment, string memory evidence) external;
    function getProviderInfo(address provider) external view returns (
        bool isActive,
        uint256 poolBalance,
        uint256 totalLocked,
        uint256 successfulServices,
        uint256 failedServices,
        uint8 tier,
        uint256 registeredAt
    );
    function usdcToken() external view returns (address);
}

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IServiceValidator {
    function validateClaim(
        bytes32 commitment,
        address client,
        uint256 amount,
        uint8 reason
    ) external view returns (bool);
}