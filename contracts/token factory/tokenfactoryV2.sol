// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./CustomToken.sol";
import "./LiquidityPool.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenFactory is Ownable {
    struct TokenInfo {
        address tokenAddress;
        address liquidityPoolAddress;
    }

    TokenInfo[] public allTokens; // List of all created tokens
    mapping(address => address) public tokenToPool; // Mapping to associate a token with its liquidity pool
    mapping(string => address) public tokenByName; // Mapping to search for a token by its name

    address public devAddress; // Developers' address
    address public daoAddress; // DAO address

    uint256 public constant DAO_RETRIBUTION_PERCENTAGE = 30; // 3% in thousandths (30/1000)
    uint256 public constant INITIAL_TOKEN_SUPPLY = 2_100_000_000 * 10 ** 18; // 2.1 billion tokens
    uint256 public constant CREATION_COST = 1 ether; // Cost to create a token
    uint256 public constant MAX_TOTAL_TAX = 50; // Maximum 5% in thousandths for buyTax + sellTax

    event TokenCreated(address indexed tokenAddress, string name, string symbol, address indexed poolAddress);
    event BuyTaxUpdated(address indexed poolAddress, uint256 newBuyTax);
    event SellTaxUpdated(address indexed poolAddress, uint256 newSellTax);

    constructor(address _devAddress, address _daoAddress) Ownable(msg.sender) {
        require(_devAddress != address(0), "Dev address cannot be zero address");
        require(_daoAddress != address(0), "DAO address cannot be zero address");
        devAddress = _devAddress;
        daoAddress = _daoAddress;
    }

    /// @notice Creates a new token and its associated liquidity pool
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    function createToken(string memory name, string memory symbol) external payable returns (address) {
        require(tokenByName[name] == address(0), "Token with this name already exists");
        require(msg.value == CREATION_COST, "Must send exactly 1 Ether to create token");

        // Fee distribution: 10% to developers, the rest to the pool
        uint256 devFee = (CREATION_COST * 10) / 100;
        uint256 remainingAmount = CREATION_COST - devFee;

        (bool devFeeSent, ) = devAddress.call{value: devFee}("");
        require(devFeeSent, "Failed to send dev fee");

        // Create the token
        CustomToken newToken = new CustomToken();
        newToken.initialize(name, symbol);

        // Token allocation
        uint256 daoRetribution = (INITIAL_TOKEN_SUPPLY * DAO_RETRIBUTION_PERCENTAGE) / 1000; // 3% to DAO
        uint256 poolShare = INITIAL_TOKEN_SUPPLY - daoRetribution;

        newToken.mint(daoAddress, daoRetribution); // Mint tokens for DAO
        newToken.mint(address(this), poolShare); // Mint remaining tokens to TokenFactory

        // Create the liquidity pool
        LiquidityPool pool = new LiquidityPool(devAddress, address(this));
        address poolAddress = address(pool);

        // Transfer tokens to the pool
        newToken.transfer(poolAddress, poolShare);

        // Initialize the pool
        pool.initialize{value: remainingAmount}(address(newToken), poolShare);

        // Record information
        address tokenAddress = address(newToken);

        allTokens.push(TokenInfo(tokenAddress, poolAddress));
        tokenToPool[tokenAddress] = poolAddress;
        tokenByName[name] = tokenAddress;

        emit TokenCreated(tokenAddress, name, symbol, poolAddress);

        return tokenAddress;
    }

    /// @notice Updates the buy tax for a specific liquidity pool
    /// @param poolAddress The address of the liquidity pool
    /// @param newBuyTax The new buy tax in thousandths
    function updatePoolBuyTax(address poolAddress, uint256 newBuyTax) external onlyOwner {
        LiquidityPool pool = LiquidityPool(poolAddress);
        uint256 totalTax = newBuyTax + pool.sellTax();
        require(totalTax <= MAX_TOTAL_TAX, "Total tax cannot exceed 5%");
        pool.updateBuyTax(newBuyTax);
        emit BuyTaxUpdated(poolAddress, newBuyTax);
    }

    /// @notice Updates the sell tax for a specific liquidity pool
    /// @param poolAddress The address of the liquidity pool
    /// @param newSellTax The new sell tax in thousandths
    function updatePoolSellTax(address poolAddress, uint256 newSellTax) external onlyOwner {
        LiquidityPool pool = LiquidityPool(poolAddress);
        uint256 totalTax = newSellTax + pool.buyTax();
        require(totalTax <= MAX_TOTAL_TAX, "Total tax cannot exceed 5%");
        pool.updateSellTax(newSellTax);
        emit SellTaxUpdated(poolAddress, newSellTax);
    }

    /// @notice Returns the total number of created tokens
    /// @return The total number of created tokens
    function getTotalTokensCreated() external view returns (uint256) {
        return allTokens.length;
    }

    /// @notice Returns the list of all created tokens and their liquidity pools
    /// @return An array of TokenInfo structs containing token and pool addresses
    function getAllTokens() external view returns (TokenInfo[] memory) {
        return allTokens;
    }
}
