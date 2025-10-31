// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/**
 * @title BondedEscrow
 * @notice Trustless refund mechanism for x402 payment protocol
 * @dev Service providers deposit USDC as bond. Clients can claim refunds with server-signed authorization.
 *
 * Key features:
 * - EIP-712 typed signature verification
 * - Prevention of double-refund via requestCommitment tracking
 * - Health check to ensure sufficient bond balance
 * - Owner can deposit/withdraw bond while maintaining minimum balance
 */
contract BondedEscrow is EIP712 {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    // =============================================================
    //                           STORAGE
    // =============================================================

    /// @notice Contract owner (service provider)
    address public immutable owner;

    /// @notice ERC20 token used for bond and refunds (USDC)
    IERC20 public immutable token;

    /// @notice Service provider's signing address for refund authorization
    address public immutable sellerAddress;

    /// @notice Minimum bond balance required for health check
    uint256 public minBond;

    /// @notice Tracks whether a request has been refunded
    /// @dev requestCommitment => settled status
    mapping(bytes32 => bool) public commitmentSettled;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event BondDeposited(address indexed from, uint256 amount);
    event BondWithdrawn(address indexed to, uint256 amount);
    event RefundClaimed(
        bytes32 indexed requestCommitment,
        address indexed recipient,
        uint256 amount
    );
    event MinBondUpdated(uint256 oldMinBond, uint256 newMinBond);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error Unauthorized();
    error InvalidSignature();
    error AlreadySettled();
    error InsufficientBond();
    error ZeroAmount();
    error ZeroAddress();

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    /**
     * @param _token Address of ERC20 token (USDC)
     * @param _sellerAddress Service provider's signing address
     * @param _minBond Minimum bond balance required
     */
    constructor(
        address _token,
        address _sellerAddress,
        uint256 _minBond
    ) EIP712("BondedEscrow", "1") {
        if (_token == address(0) || _sellerAddress == address(0)) {
            revert ZeroAddress();
        }
        if (_minBond == 0) revert ZeroAmount();

        owner = msg.sender;
        token = IERC20(_token);
        sellerAddress = _sellerAddress;
        minBond = _minBond;
    }

    // =============================================================
    //                         MODIFIERS
    // =============================================================

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    // =============================================================
    //                      CORE FUNCTIONS
    // =============================================================

    /**
     * @notice Deposit bond into escrow
     * @param amount Amount of tokens to deposit
     */
    function deposit(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();

        token.safeTransferFrom(msg.sender, address(this), amount);
        emit BondDeposited(msg.sender, amount);
    }

    /**
     * @notice Withdraw bond from escrow (must maintain minBond)
     * @param amount Amount of tokens to withdraw
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
     * @notice Claim refund with server-signed authorization
     * @param requestCommitment Unique identifier for the failed request
     * @param amount Refund amount in token wei
     * @param signature EIP-712 signature from sellerAddress
     *
     * @dev Signature must be created by signing:
     *      keccak256(abi.encode(
     *          keccak256("RefundClaim(bytes32 requestCommitment,uint256 amount)"),
     *          requestCommitment,
     *          amount
     *      ))
     */
    function claimRefund(
        bytes32 requestCommitment,
        uint256 amount,
        bytes calldata signature
    ) external {
        // Prevent double-refund
        if (commitmentSettled[requestCommitment]) {
            revert AlreadySettled();
        }

        // Verify EIP-712 signature
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("RefundClaim(bytes32 requestCommitment,uint256 amount)"),
                requestCommitment,
                amount
            )
        );

        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = digest.recover(signature);

        if (signer != sellerAddress) {
            revert InvalidSignature();
        }

        // Mark as settled
        commitmentSettled[requestCommitment] = true;

        // Transfer refund to caller
        token.safeTransfer(msg.sender, amount);

        emit RefundClaimed(requestCommitment, msg.sender, amount);
    }

    /**
     * @notice Check if escrow has sufficient bond
     * @return healthy True if balance >= minBond
     */
    function isHealthy() external view returns (bool healthy) {
        return token.balanceOf(address(this)) >= minBond;
    }

    /**
     * @notice Get current bond balance
     * @return balance Current token balance in escrow
     */
    function getBondBalance() external view returns (uint256 balance) {
        return token.balanceOf(address(this));
    }

    /**
     * @notice Update minimum bond requirement
     * @param _minBond New minimum bond amount
     */
    function setMinBond(uint256 _minBond) external onlyOwner {
        if (_minBond == 0) revert ZeroAmount();

        uint256 oldMinBond = minBond;
        minBond = _minBond;

        emit MinBondUpdated(oldMinBond, _minBond);
    }

    /**
     * @notice Get EIP-712 domain separator
     * @return Domain separator for signature verification
     */
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }
}
