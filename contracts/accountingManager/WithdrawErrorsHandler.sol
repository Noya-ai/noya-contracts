// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import "@openzeppelin/contracts-5.0/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-5.0/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-5.0/access/AccessControl.sol";

struct Error {
    address token;
    address from;
    uint256 amount;
    uint256 timestamp;
}

contract WithdrawErrorHandler is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant ACCOUNTING_ROLE = keccak256("ACCOUNTING_ROLE");

    error Unauthorized(address sender);
    error InsufficientBalance(uint256 balance, uint256 amount);

    event WithdrawError(address indexed token, address indexed to, uint256 amount, string reason);
    event HandleWithdrawalError(address indexed token, address from, address to, uint256 amount);

    Error[] public errors;
    mapping(address => uint256) public errorBalances;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
        _setRoleAdmin(MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(ACCOUNTING_ROLE, DEFAULT_ADMIN_ROLE);
    }

    function withdrawalError(address token, address to, uint256 amount, string memory reason)
        external
        onlyRole(ACCOUNTING_ROLE)
        nonReentrant
    {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance < amount + errorBalances[token]) {
            revert InsufficientBalance(balance, amount);
        }
        errorBalances[token] += amount;
        errors.push(Error(token, to, amount, block.timestamp));
        emit WithdrawError(token, to, amount, reason);
    }

    function handleWithdrawalErrors(uint256 errorId, address to) external onlyRole(MANAGER_ROLE) nonReentrant {
        Error memory error = errors[errorId];
        IERC20(error.token).safeTransfer(to, error.amount);
        errorBalances[error.token] -= error.amount;
        emit HandleWithdrawalError(error.token, error.from, to, error.amount);
    }
}
