// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.0;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

/// @title Aqua - Shared Liquidity Layer
/// @notice Manages token balances (aka allowances) between makers (liquidity providers) and apps,
///         enabling shared liquidity access directly from maker wallets
interface IAqua {
    /// @notice Thrown when the number of tokens in a strategy exceeds the maximum allowed
    /// @param tokensCount The actual number of tokens provided
    /// @param maxTokensCount The maximum number of tokens allowed
    error MaxNumberOfTokensExceeded(uint256 tokensCount, uint256 maxTokensCount);

    /// @notice Thrown when attempting to modify an already existing strategy
    /// @param app The app address of the strategy
    /// @param strategyHash The hash of the existing strategy
    error StrategiesMustBeImmutable(address app, bytes32 strategyHash);

    /// @notice Thrown when docking doesn't include all tokens from the strategy
    /// @param app The app address of the strategy
    /// @param strategyHash The hash of the strategy being docked
    error DockingShouldCloseAllTokens(address app, bytes32 strategyHash);

    /// @notice Thrown when attempting to push tokens to a non-active or docked strategy
    /// @param maker The maker address
    /// @param app The app address
    /// @param strategyHash The hash of the strategy
    /// @param token The token being pushed
    error PushToNonActiveStrategyPrevented(address maker, address app, bytes32 strategyHash, address token);

    /// @notice Thrown when querying safe balances for a token not part of an active strategy
    /// @param maker The maker address
    /// @param app The app address
    /// @param strategyHash The hash of the strategy
    /// @param token The token being queried
    error SafeBalancesForTokenNotInActiveStrategy(address maker, address app, bytes32 strategyHash, address token);

    /// @notice Emitted when a new strategy is shipped (deployed) and initialized with balances
    /// @param maker The address of the maker shipping the strategy
    /// @param app The app address associated with the strategy
    /// @param strategyHash The hash of the strategy being shipped
    /// @param strategy The strategy being shipped (abi encoded)
    event Shipped(address maker, address app, bytes32 strategyHash, bytes strategy);

    /// @notice Emitted when a maker revokes (deactivates) a strategy
    /// @param maker The address of the maker revoking the strategy
    /// @param app The app address associated with the strategy being docked
    /// @param strategyHash The hash of the strategy being revoked
    event Docked(address maker, address app, bytes32 strategyHash);

    /// @notice Emitted when a strategy pulls tokens from a maker
    /// @param maker The address of the maker whose tokens are being pulled
    /// @param app The app address that initiated the pull
    /// @param strategyHash The hash of the strategy being pulled from
    /// @param token The token address being pulled
    /// @param amount The amount of tokens being pulled
    /// @dev The tokens are transferred from the maker's balance to the specified recipient
    event Pulled(address maker, address app, bytes32 strategyHash, address token, uint256 amount);

    /// @notice Emitted when tokens are pushed into a maker's balance
    /// @param maker The address of the maker whose balance receives the tokens
    /// @param app The app address whose balance gets increased
    /// @param strategyHash The hash of the strategy being pushed to
    /// @param token The token address being pushed
    /// @param amount The amount of tokens being pushed and added to the strategy's balance
    /// @dev The tokens are transferred from the caller to the maker's balance
    event Pushed(address maker, address app, bytes32 strategyHash, address token, uint256 amount);

    /// @notice Returns the balance amount for a specific maker, app, and token combination
    /// @param maker The address of the maker who granted the balance
    /// @param app The address of the app/strategy that can pull tokens
    /// @param strategyHash The hash of the strategy being used
    /// @param token The address of the token
    /// @return balance The current balance amount
    /// @return tokensCount The number of tokens in the strategy
    function rawBalances(address maker, address app, bytes32 strategyHash, address token) external view returns (uint248 balance, uint8 tokensCount);

    /// @notice Returns balances of multiple tokens in a strategy, reverts if any of the tokens is not part of the active strategy
    /// @param maker The address of the maker who granted the balances
    /// @param app The address of the app/strategy that can pull tokens
    /// @param strategyHash The hash of the strategy being used
    /// @param token0 The address of the first token
    /// @param token1 The address of the second token
    /// @return balance0 The current balance amount for the first token
    /// @return balance1 The current balance amount for the second token
    function safeBalances(address maker, address app, bytes32 strategyHash, address token0, address token1) external view returns (uint256 balance0, uint256 balance1);

    /// @notice Ships a new strategy as of an app and sets initial balances
    /// @dev Parameter `strategy` is presented fully instead of being pre-hashed for data availability
    /// @param app The implementation contract
    /// @param strategy Initialization data passed to the strategy
    /// @param tokens Array of token addresses to approve
    /// @param amounts Array of balance amounts for each token
    function ship(
        address app,
        bytes calldata strategy,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external returns(bytes32 strategyHash);

    /// @notice Docks (deactivates) a strategy by clearing balances for specified tokens
    /// @dev Sets balances to 0 for all specified tokens
    /// @param app The app address associated with the strategy
    /// @param strategyHash The hash of the strategy being docked
    /// @param tokens Array of token addresses to clear
    function dock(address app, bytes32 strategyHash, address[] calldata tokens) external;

    /// @notice Allows a strategy to pull tokens from a maker's wallet
    /// @dev Decrements the balance and transfers tokens. Caller must be an approved app
    /// @param maker The maker to pull tokens from
    /// @param strategyHash The hash of the strategy being used
    /// @param token The token address to pull
    /// @param amount The amount to pull
    /// @param to The recipient address
    function pull(address maker, bytes32 strategyHash, address token, uint256 amount, address to) external;

    /// @notice Pushes tokens and increases an app balance
    /// @dev Transfers tokens from caller to maker and increases the app's balance
    /// @param maker The maker whose balance receives the tokens
    /// @param app The address of the app/strategy receiving the tokens
    /// @param strategyHash The hash of the strategy being pushed
    /// @param token The token address to push
    /// @param amount The amount to push and add to balance
    function push(address maker, address app, bytes32 strategyHash, address token, uint256 amount) external;
}
