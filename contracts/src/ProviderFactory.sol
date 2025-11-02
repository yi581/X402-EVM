// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "./ProviderContractInterface.sol";

/**
 * @title ProviderFactory
 * @notice 工厂合约，让 Provider 接入变得超级简单
 * @dev Provider 只需调用一个函数即可完成部署和注册
 */
contract ProviderFactory {

    address public immutable insuranceV8;
    address public immutable usdcToken;

    // 记录所有通过工厂创建的 Provider 合约
    mapping(address => address[]) public userProviders;
    address[] public allProviders;

    event ProviderCreated(
        address indexed owner,
        address indexed providerContract,
        uint256 initialDeposit
    );

    constructor(address _insuranceV8, address _usdcToken) {
        insuranceV8 = _insuranceV8;
        usdcToken = _usdcToken;
    }

    /**
     * @notice 一键创建并注册 Provider 合约
     * @param initialDeposit 初始保险金（USDC，6位小数）
     * @return providerContract 创建的 Provider 合约地址
     *
     * 使用步骤：
     * 1. 授权 USDC: usdc.approve(factoryAddress, amount)
     * 2. 调用此函数: factory.createProvider(amount)
     * 3. 完成！你的 Provider 合约已部署并注册
     */
    function createProvider(uint256 initialDeposit)
        external
        returns (address providerContract)
    {
        require(initialDeposit >= 10 * 10**6, "Minimum 10 USDC required");

        // 1. 部署 SimpleProviderContract
        SimpleProviderContract provider = new SimpleProviderContract(insuranceV8);
        providerContract = address(provider);

        // 2. 从调用者转入 USDC 到 Provider 合约
        require(
            IERC20(usdcToken).transferFrom(msg.sender, providerContract, initialDeposit),
            "USDC transfer failed"
        );

        // 3. 调用 Provider 合约的注册函数
        provider.registerAsProvider(initialDeposit);

        // 4. 转移所有权给调用者
        provider.transferOwnership(msg.sender);

        // 5. 记录
        userProviders[msg.sender].push(providerContract);
        allProviders.push(providerContract);

        emit ProviderCreated(msg.sender, providerContract, initialDeposit);

        return providerContract;
    }

    /**
     * @notice 批量创建多个 Provider 合约
     * @param deposits 每个 Provider 的初始保险金数组
     * @return providers 创建的 Provider 合约地址数组
     */
    function createMultipleProviders(uint256[] calldata deposits)
        external
        returns (address[] memory providers)
    {
        providers = new address[](deposits.length);

        for (uint256 i = 0; i < deposits.length; i++) {
            providers[i] = this.createProvider(deposits[i]);
        }

        return providers;
    }

    /**
     * @notice 获取用户创建的所有 Provider 合约
     * @param user 用户地址
     * @return 用户的 Provider 合约地址数组
     */
    function getUserProviders(address user)
        external
        view
        returns (address[] memory)
    {
        return userProviders[user];
    }

    /**
     * @notice 获取所有通过工厂创建的 Provider
     * @return 所有 Provider 合约地址数组
     */
    function getAllProviders()
        external
        view
        returns (address[] memory)
    {
        return allProviders;
    }

    /**
     * @notice 获取统计信息
     * @return totalProviders 总 Provider 数量
     * @return totalUsers 总用户数量
     */
    function getStats()
        external
        view
        returns (uint256 totalProviders, uint256 totalUsers)
    {
        totalProviders = allProviders.length;
        // 简化版本，实际可以维护更详细的统计
        totalUsers = allProviders.length; // 假设一个用户一个 Provider
        return (totalProviders, totalUsers);
    }
}
