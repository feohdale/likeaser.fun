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

    TokenInfo[] public allTokens;
    mapping(address => address) public tokenToPool;
    mapping(string => address) public tokenByName;

    address public devAddress; // Developers' address
    address public daoAddress; // DAO address
    address public migrator; 

    uint256 public constant DAO_RETRIBUTION_PERCENTAGE = 30; // 3% in thousandths (30/1000)
    uint256 public constant INITIAL_TOKEN_SUPPLY = 2_100_000_000 * 10 ** 18; // 2.1 billion tokens
    uint256 public creationCost = 0.0002 ether; // Cost to create a token
    uint256 public constant MAX_TOTAL_TAX = 50; // Maximum total tax in thousandths (5%)

    uint256 public defaultBuyTax = 0; // Default buy tax for new pools (in thousandths)
    uint256 public defaultSellTax = 10; // Default sell tax for new pools (in thousandths)
    uint256 public defaultMigrationThreshold = 0.2 ether; // Default migration threshold
    bool autoMigration = true; 


    event TokenCreated(address indexed tokenAddress, string name, string symbol, address indexed poolAddress);
    event DefaultTaxesUpdated(uint256 newBuyTax, uint256 newSellTax);
    event PoolBuyTaxUpdated(address indexed poolAddress, uint256 newBuyTax);
    event PoolSellTaxUpdated(address indexed poolAddress, uint256 newSellTax);
    event CreationCostUpdated(uint256 newCost);
    event MigrationThresholdUpdated(address indexed poolAddress, uint256 newThreshold);
    event AlgebraInitializerUpdated(address indexed newInitializer);
    event MigrationToggled(address indexed poolAddress, bool enabled);
    event GlobalAutoMigrationToggled(bool enabled);

    constructor(address _devAddress, address _daoAddress, address _migrator) Ownable(msg.sender) {
        require(_devAddress != address(0), "Dev address cannot be zero address");
        require(_daoAddress != address(0), "DAO address cannot be zero address");
        require(_migrator != address(0), "Algebra initializer cannot be zero address");

        devAddress = _devAddress;
        daoAddress = _daoAddress;
        migrator = _migrator;
    }

    /// @notice Creates a new token and its associated liquidity pool
    function createToken(string memory name, string memory symbol) external payable returns (address) {
        require(tokenByName[name] == address(0), "Token with this name already exists");
        require(msg.value == creationCost, "Incorrect Ether value for creation cost");

        uint256 devFee = (creationCost * 10) / 100;
        uint256 remainingAmount = creationCost - devFee;

        (bool devFeeSent, ) = devAddress.call{value: devFee}("");
        require(devFeeSent, "Failed to send dev fee");

        CustomToken newToken = new CustomToken();
        newToken.initialize(name, symbol);

        uint256 daoRetribution = (INITIAL_TOKEN_SUPPLY * DAO_RETRIBUTION_PERCENTAGE) / 1000;
        uint256 poolShare = INITIAL_TOKEN_SUPPLY - daoRetribution;

        newToken.mint(daoAddress, daoRetribution);
        newToken.mint(address(this), poolShare);

        LiquidityPool pool = new LiquidityPool(devAddress, address(this), defaultMigrationThreshold);
        address poolAddress = address(pool);

        newToken.transfer(poolAddress, poolShare);

        pool.initialize{value: remainingAmount}(address(newToken), poolShare, defaultBuyTax, defaultSellTax, migrator, autoMigration);

        address tokenAddress = address(newToken);
        allTokens.push(TokenInfo(tokenAddress, poolAddress));
        tokenToPool[tokenAddress] = poolAddress;
        tokenByName[name] = tokenAddress;

        emit TokenCreated(tokenAddress, name, symbol, poolAddress);

        return tokenAddress;
    }

    /// @notice Updates the default buy and sell taxes for future pools
    function updateDefaultTaxes(uint256 newBuyTax, uint256 newSellTax) external onlyOwner {
        require(newBuyTax + newSellTax <= MAX_TOTAL_TAX, "Total tax cannot exceed 5%");
        defaultBuyTax = newBuyTax;
        defaultSellTax = newSellTax;
        emit DefaultTaxesUpdated(newBuyTax, newSellTax);
    }

    /// @notice Updates the buy tax for an existing pool
    function updatePoolBuyTax(address poolAddress, uint256 newBuyTax) external onlyOwner {
        LiquidityPool pool = LiquidityPool(poolAddress);
        uint256 totalTax = newBuyTax + pool.sellTax();
        require(totalTax <= MAX_TOTAL_TAX, "Total tax cannot exceed 5%");
        pool.updateBuyTax(newBuyTax);
        emit PoolBuyTaxUpdated(poolAddress, newBuyTax);
    }

    /// @notice Updates the sell tax for an existing pool
    function updatePoolSellTax(address poolAddress, uint256 newSellTax) external onlyOwner {
        LiquidityPool pool = LiquidityPool(poolAddress);
        uint256 totalTax = newSellTax + pool.buyTax();
        require(totalTax <= MAX_TOTAL_TAX, "Total tax cannot exceed 5%");
        pool.updateSellTax(newSellTax);
        emit PoolSellTaxUpdated(poolAddress, newSellTax);
    }

    /// @notice Updates the cost to create a new token
    function updateCreationCost(uint256 newCost) external onlyOwner {
        require(newCost > 0, "Creation cost must be greater than zero");
        creationCost = newCost;
        emit CreationCostUpdated(newCost);
    }

    /// @notice Updates the migration threshold for a specific pool
    function updatePoolMigrationThreshold(address poolAddress, uint256 newThreshold) external onlyOwner {
        LiquidityPool pool = LiquidityPool(poolAddress);
        pool.updateMigrationThreshold(newThreshold);
        emit MigrationThresholdUpdated(poolAddress, newThreshold);
    }

    /// @notice Updates the Algebra Pool Initializer address
    function updateMigrator(address newMigrator) external onlyOwner {
        require(newMigrator != address(0), "Initializer cannot be zero address");
        migrator = newMigrator;
        emit AlgebraInitializerUpdated(newMigrator);
    }

    /// @notice Toggles the auto-migration feature for a specific pool
    function togglePoolMigration(address poolAddress, bool enable) external onlyOwner {
        LiquidityPool pool = LiquidityPool(poolAddress);
        pool.toggleAutoMigration(enable);
        emit MigrationToggled(poolAddress, enable);
    }

    /// @notice Returns the total number of tokens created
    function getTotalTokensCreated() external view returns (uint256) {
        return allTokens.length;
    }

    /// @notice Returns the complete list of created tokens
    function getAllTokens() external view returns (TokenInfo[] memory) {
        return allTokens;
    }



    function toggleGlobalAutoMigration(bool enable) external onlyOwner {
        // Iterate over all pools and toggle auto-migration
        for (uint256 i = 0; i < allTokens.length; i++) {
            address poolAddress = allTokens[i].liquidityPoolAddress;
            LiquidityPool(poolAddress).toggleAutoMigration(enable);
        }
        emit GlobalAutoMigrationToggled(enable);
    }
    function toggleAutoMigrationAtCreation() external onlyOwner {
        autoMigration = !autoMigration; 
        
    }
    function forceMigration(address poolAddress) external onlyOwner {
        LiquidityPool pool = LiquidityPool(poolAddress);
        pool.forceMigration(); 

    }
}