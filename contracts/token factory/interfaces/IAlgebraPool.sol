// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IAlgebraPool {
    /**
     * @notice Adds liquidity to the pool.
     * @param amount0Desired The amount of token0 to add.
     * @param amount1Desired The amount of token1 to add.
     * @param amount0Min The minimum amount of token0 to add.
     * @param amount1Min The minimum amount of token1 to add.
     * @param recipient The address to receive the liquidity tokens.
     * @param deadline The timestamp by which the transaction must be confirmed.
     */
    function addLiquidity(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amount0, uint256 amount1, uint256 liquidity);

    /**
     * @notice Removes liquidity from the pool.
     * @param liquidity The amount of liquidity tokens to remove.
     * @param amount0Min The minimum amount of token0 to withdraw.
     * @param amount1Min The minimum amount of token1 to withdraw.
     * @param recipient The address to receive the withdrawn tokens.
     * @param deadline The timestamp by which the transaction must be confirmed.
     */
    function removeLiquidity(
        uint256 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amount0, uint256 amount1);
}
