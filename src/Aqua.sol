// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SafeERC20, IERC20 } from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";

import { IAqua } from "./interfaces/IAqua.sol";
import { Balance, BalanceLib } from "./libs/Balance.sol";

/// @title Aqua - Shared Liquidity Layer
contract Aqua is IAqua {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using BalanceLib for Balance;

    error MaxNumberOfTokensExceeded(uint256 tokensCount, uint256 maxTokensCount);
    error StrategiesMustBeImmutable(address app, bytes32 strategyHash);
    error DockingShouldCloseAllTokens(address app, bytes32 strategyHash);
    error PushToNonActiveStrategyPrevented(address maker, address app, bytes32 strategyHash, address token);
    error SafeBalancesForTokenNotInActiveStrategy(address maker, address app, bytes32 strategyHash, address token);
    error ArrayLengthMismatch();
    error InvalidAddress();
    error DuplicateToken();
    error InsufficientBalance();
    error InactiveStrategy();

    uint8 private constant _DOCKED = 0xff;

    mapping(address maker =>
        mapping(address app =>
            mapping(bytes32 strategyHash =>
                mapping(address token => Balance)))) private _balances; // aka makers' allowances

    function rawBalances(address maker, address app, bytes32 strategyHash, address token) external view returns (uint248 balance, uint8 tokensCount) {
        return _balances[maker][app][strategyHash][token].load();
    }

    function safeBalances(address maker, address app, bytes32 strategyHash, address token0, address token1) external view returns (uint256 balance0, uint256 balance1) {
        (uint248 amount0, uint8 tokensCount0) = _balances[maker][app][strategyHash][token0].load();
        require(tokensCount0 > 0 && tokensCount0 != _DOCKED, SafeBalancesForTokenNotInActiveStrategy(maker, app, strategyHash, token0));
        balance0 = amount0;

        (uint248 amount1, uint8 tokensCount1) = _balances[maker][app][strategyHash][token1].load();
        require(tokensCount1 > 0 && tokensCount1 != _DOCKED, SafeBalancesForTokenNotInActiveStrategy(maker, app, strategyHash, token1));
        balance1 = amount1;
    }

    function ship(address app, bytes calldata strategy, address[] calldata tokens, uint256[] calldata amounts) external returns(bytes32 strategyHash) {
        require(app != address(0), InvalidAddress());
        require(tokens.length == amounts.length, ArrayLengthMismatch());

        strategyHash = keccak256(strategy);
        uint8 tokensCount = tokens.length.toUint8();
        require(tokensCount != _DOCKED, MaxNumberOfTokensExceeded(tokensCount, _DOCKED));

        emit Shipped(msg.sender, app, strategyHash, strategy);
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length;) {
            address token = tokens[i];
            require(token != address(0), InvalidAddress());

            for (uint256 j = 0; j < i;) {
                require(tokens[j] != token, DuplicateToken());
                unchecked { ++j; }
            }

            Balance storage balance = _balances[msg.sender][app][strategyHash][token];
            require(balance.tokensCount == 0, StrategiesMustBeImmutable(app, strategyHash));
            balance.store(amounts[i].toUint248(), tokensCount);
            emit Pushed(msg.sender, app, strategyHash, token, amounts[i]);

            unchecked { ++i; }
        }
    }

    function dock(address app, bytes32 strategyHash, address[] calldata tokens) external {
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length;) {
            Balance storage balance = _balances[msg.sender][app][strategyHash][tokens[i]];
            require(balance.tokensCount == length, DockingShouldCloseAllTokens(app, strategyHash));
            balance.store(0, _DOCKED);

            unchecked { ++i; }
        }
        emit Docked(msg.sender, app, strategyHash);
    }

    function pull(address maker, bytes32 strategyHash, address token, uint256 amount, address to) external {
        require(maker != address(0) && to != address(0), InvalidAddress());

        Balance storage balance = _balances[maker][msg.sender][strategyHash][token];
        (uint248 prevBalance, uint8 tokensCount) = balance.load();
        require(tokensCount > 0 && tokensCount != _DOCKED, InactiveStrategy());
        require(amount <= prevBalance, InsufficientBalance());

        balance.store(prevBalance - amount.toUint248(), tokensCount);

        IERC20(token).safeTransferFrom(maker, to, amount);
        emit Pulled(maker, msg.sender, strategyHash, token, amount);
    }

    function push(address maker, address app, bytes32 strategyHash, address token, uint256 amount) external {
        require(maker != address(0) && app != address(0), InvalidAddress());

        Balance storage balance = _balances[maker][app][strategyHash][token];
        (uint248 prevBalance, uint8 tokensCount) = balance.load();
        require(tokensCount > 0 && tokensCount != _DOCKED, PushToNonActiveStrategyPrevented(maker, app, strategyHash, token));
        balance.store(prevBalance + amount.toUint248(), tokensCount);

        IERC20(token).safeTransferFrom(msg.sender, maker, amount);
        emit Pushed(maker, app, strategyHash, token, amount);
    }
}
