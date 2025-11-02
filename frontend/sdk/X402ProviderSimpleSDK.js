/**
 * X402 Provider Simple SDK
 * 让 Provider 接入变得超级简单！
 */

import { ethers } from 'ethers';

// 合约地址
const FACTORY_ADDRESS = '0xbed30550aB282bED6A6ED57F23E9C99FAd8b7b76'; // ProviderFactory
const INSURANCE_V8_ADDRESS = '0x72486eF40BB3729298369d608de85c612adb223e';
const USDC_ADDRESS = '0x036CbD53842c5426634e7929541eC2318f3dCF7e';

// 简化的 ABI
const FACTORY_ABI = [
  'function createProvider(uint256 initialDeposit) returns (address)',
  'function getUserProviders(address user) view returns (address[])',
  'function getAllProviders() view returns (address[])',
  'event ProviderCreated(address indexed owner, address indexed providerContract, uint256 initialDeposit)'
];

const USDC_ABI = [
  'function approve(address spender, uint256 amount) returns (bool)',
  'function balanceOf(address owner) view returns (uint256)'
];

/**
 * X402 Provider 简单 SDK
 *
 * 使用示例：
 *
 * // 1. 连接钱包
 * const sdk = await X402ProviderSimpleSDK.connect();
 *
 * // 2. 一键成为 Provider
 * const provider = await sdk.becomeProvider('100');
 *
 * console.log('你的 Provider 合约:', provider.address);
 */
class X402ProviderSimpleSDK {

  constructor(signer) {
    this.signer = signer;
    this.provider = signer.provider;

    this.factory = new ethers.Contract(FACTORY_ADDRESS, FACTORY_ABI, signer);
    this.usdc = new ethers.Contract(USDC_ADDRESS, USDC_ABI, signer);
  }

  /**
   * 连接钱包并创建 SDK 实例
   * @returns {Promise<X402ProviderSimpleSDK>}
   */
  static async connect() {
    if (typeof window === 'undefined' || !window.ethereum) {
      throw new Error('请安装 MetaMask');
    }

    await window.ethereum.request({ method: 'eth_requestAccounts' });

    const provider = new ethers.BrowserProvider(window.ethereum);
    const signer = await provider.getSigner();

    // 切换到 Base Sepolia
    try {
      await window.ethereum.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: '0x14a34' }]
      });
    } catch (error) {
      if (error.code === 4902) {
        await window.ethereum.request({
          method: 'wallet_addEthereumChain',
          params: [{
            chainId: '0x14a34',
            chainName: 'Base Sepolia',
            nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 },
            rpcUrls: ['https://sepolia.base.org'],
            blockExplorerUrls: ['https://sepolia.basescan.org']
          }]
        });
      }
    }

    return new X402ProviderSimpleSDK(signer);
  }

  /**
   * 一键成为 Provider！
   *
   * @param {string} usdcAmount - USDC 金额（如 "100"）
   * @param {Function} onProgress - 进度回调
   * @returns {Promise<Object>} Provider 信息
   *
   * @example
   * const provider = await sdk.becomeProvider('100', (step, message) => {
   *   console.log(`步骤 ${step}: ${message}`);
   * });
   */
  async becomeProvider(usdcAmount, onProgress = () => {}) {
    const amount = ethers.parseUnits(usdcAmount.toString(), 6);
    const address = await this.signer.getAddress();

    onProgress(1, '检查 USDC 余额...');
    const balance = await this.usdc.balanceOf(address);
    if (balance < amount) {
      throw new Error(`USDC 余额不足。需要: ${usdcAmount}, 拥有: ${ethers.formatUnits(balance, 6)}`);
    }

    onProgress(2, '授权 USDC...');
    const approveTx = await this.usdc.approve(FACTORY_ADDRESS, amount);
    await approveTx.wait();

    onProgress(3, '创建并注册 Provider 合约...');
    const createTx = await this.factory.createProvider(amount);
    const receipt = await createTx.wait();

    // 从事件中获取 Provider 合约地址
    const event = receipt.logs
      .map(log => {
        try {
          return this.factory.interface.parseLog(log);
        } catch {
          return null;
        }
      })
      .find(e => e && e.name === 'ProviderCreated');

    if (!event) {
      throw new Error('无法找到 ProviderCreated 事件');
    }

    const providerAddress = event.args.providerContract;

    onProgress(4, '完成！');

    return {
      address: providerAddress,
      initialDeposit: ethers.formatUnits(amount, 6),
      txHash: createTx.hash,
      blockNumber: receipt.blockNumber
    };
  }

  /**
   * 获取我创建的所有 Provider
   * @returns {Promise<string[]>} Provider 合约地址数组
   */
  async getMyProviders() {
    const address = await this.signer.getAddress();
    return await this.factory.getUserProviders(address);
  }

  /**
   * 获取我的 USDC 余额
   * @returns {Promise<string>} USDC 余额
   */
  async getUSDCBalance() {
    const address = await this.signer.getAddress();
    const balance = await this.usdc.balanceOf(address);
    return ethers.formatUnits(balance, 6);
  }

  /**
   * 获取我的钱包地址
   * @returns {Promise<string>}
   */
  async getAddress() {
    return await this.signer.getAddress();
  }
}

// React Hook 示例
export function useX402Provider() {
  const [sdk, setSdk] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [progress, setProgress] = useState({ step: 0, message: '' });

  const connect = async () => {
    setLoading(true);
    setError(null);
    try {
      const instance = await X402ProviderSimpleSDK.connect();
      setSdk(instance);
      return instance;
    } catch (err) {
      setError(err.message);
      throw err;
    } finally {
      setLoading(false);
    }
  };

  const becomeProvider = async (amount) => {
    if (!sdk) {
      throw new Error('请先连接钱包');
    }

    setLoading(true);
    setError(null);

    try {
      const provider = await sdk.becomeProvider(amount, (step, message) => {
        setProgress({ step, message });
      });
      return provider;
    } catch (err) {
      setError(err.message);
      throw err;
    } finally {
      setLoading(false);
      setProgress({ step: 0, message: '' });
    }
  };

  const getMyProviders = async () => {
    if (!sdk) return [];
    return await sdk.getMyProviders();
  };

  return {
    sdk,
    loading,
    error,
    progress,
    connect,
    becomeProvider,
    getMyProviders
  };
}

export default X402ProviderSimpleSDK;
