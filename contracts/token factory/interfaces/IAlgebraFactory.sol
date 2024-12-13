// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IAlgebraFactory {
    /**
     * @notice Creates a new pool for the given token pair.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @return pool The address of the created pool.
     */
    function createPool(address tokenA, address tokenB) external returns (address pool);

    /**
     * @notice Computes the address of a pool for the given token pair.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @return pool The address of the computed pool.
     */
    function computePoolAddress(address tokenA, address tokenB) external view returns (address pool);
}
