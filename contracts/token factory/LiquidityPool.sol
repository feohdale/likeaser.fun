// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LiquidityPool is ReentrancyGuard {
    address public token0; // ERC20 token address
    address public tokenFactory; // TokenFactory address
    address public devAddress; // Developer address
    address public algebraPoolInitializer; // Algebra PoolInitializer contract address
    uint256 public reserve0; // Token reserve
    uint256 public reserve1; // Native currency reserve (e.g., Ether)
    uint256 public buyTax; // Buy tax in thousandths
    uint256 public sellTax; // Sell tax in thousandths
    bool public migratedToAlgebra; // Whether the pool has migrated to Algebra
    bool public autoMigrationEnabled; // Whether auto-migration is enabled
    uint256 public migrationThreshold; // Threshold to trigger migration

    event Swap(address indexed fromToken, address indexed toToken, uint256 amountIn, uint256 amountOut);
    event LiquidityAdded(address indexed provider, uint256 tokenAmount, uint256 nativeAmount);
    event TaxUpdated(uint256 newBuyTax, uint256 newSellTax);
    event MigrationToAlgebra(address indexed newPoolAddress, uint256 tokenTransferred, uint256 etherTransferred);
    event AlgebraPoolInitializerUpdated(address indexed newInitializer);
    event MigrationThresholdUpdated(uint256 newThreshold);
    event AutoMigrationToggled(bool enabled);

    modifier onlyFactory() {
        require(msg.sender == tokenFactory, "Caller is not the TokenFactory");
        _;
    }

    constructor(address _devAddress, address _tokenFactory, uint256 _initialMigrationThreshold) {
        require(_devAddress != address(0), "Developer address cannot be zero");
        require(_tokenFactory != address(0), "TokenFactory address cannot be zero");
        devAddress = _devAddress;
        tokenFactory = _tokenFactory;
        migrationThreshold = _initialMigrationThreshold;
        autoMigrationEnabled = false; // Default to disabled
    }

    function initialize(
        address _token0,
        uint256 _initialTokenReserve,
        uint256 _buyTax,
        uint256 _sellTax
    ) external payable onlyFactory nonReentrant {
        require(token0 == address(0), "Pool already initialized");
        require(msg.value > 0, "Initial native currency reserve required");

        token0 = _token0;
        reserve0 = _initialTokenReserve;
        reserve1 = msg.value;
        buyTax = _buyTax;
        sellTax = _sellTax;

        emit LiquidityAdded(msg.sender, _initialTokenReserve, msg.value);
    }

    function setAlgebraPoolInitializer(address _initializer) external onlyFactory {
        require(_initializer != address(0), "Initializer address cannot be zero");
        algebraPoolInitializer = _initializer;
        emit AlgebraPoolInitializerUpdated(_initializer);
    }

    function toggleAutoMigration(bool enable) external onlyFactory {
        autoMigrationEnabled = enable;
        emit AutoMigrationToggled(enable);
    }

    function updateMigrationThreshold(uint256 newThreshold) external onlyFactory {
        require(newThreshold > 0, "Threshold must be greater than zero");
        migrationThreshold = newThreshold;
        emit MigrationThresholdUpdated(newThreshold);
    }

    function migrateToAlgebra() internal nonReentrant {
        require(!migratedToAlgebra, "Already migrated to Algebra");
        require(algebraPoolInitializer != address(0), "Algebra PoolInitializer address not set");

        // Create the Algebra pool
        bytes memory payload = abi.encodeWithSignature("createPool(address)", token0);
        (bool success, bytes memory returnData) = algebraPoolInitializer.call(payload);
        require(success, "Algebra pool creation failed");

        address newPoolAddress = abi.decode(returnData, (address));
        require(newPoolAddress != address(0), "Invalid Algebra pool address");

        // Transfer the reserves to the new pool
        IERC20(token0).transfer(newPoolAddress, reserve0);
        (bool etherTransferSuccess, ) = newPoolAddress.call{value: reserve1}("");
        require(etherTransferSuccess, "Failed to transfer Ether to Algebra pool");

        migratedToAlgebra = true;

        emit MigrationToAlgebra(newPoolAddress, reserve0, reserve1);
    }

    function buyToken() external payable nonReentrant returns (uint256 amountOut) {
        require(!migratedToAlgebra, "Pool migrated to Algebra");
        require(msg.value > 0, "Must send Ether to buy tokens");

        uint256 tax = (msg.value * buyTax) / 1000;
        uint256 amountInAfterTax = msg.value - tax;

        (bool taxSent, ) = devAddress.call{value: tax}("");
        require(taxSent, "Failed to send tax to dev address");

        uint256 newReserve1 = reserve1 + amountInAfterTax;
        amountOut = reserve0 - (reserve0 * reserve1) / newReserve1;

        reserve1 = newReserve1;
        reserve0 -= amountOut;

        IERC20(token0).transfer(msg.sender, amountOut);

        emit Swap(address(0), token0, msg.value, amountOut);

        if (autoMigrationEnabled && reserve1 >= migrationThreshold) {
            migrateToAlgebra();
        }
    }

    function sellToken(uint256 amountIn) external nonReentrant returns (uint256 amountOut) {
        require(!migratedToAlgebra, "Pool migrated to Algebra");
        require(amountIn > 0, "Must sell some tokens");

        uint256 tax = (amountIn * sellTax) / 1000;
        uint256 amountInAfterTax = amountIn - tax;

        IERC20(token0).transferFrom(msg.sender, address(this), amountIn);
        IERC20(token0).transfer(devAddress, tax);

        uint256 newReserve0 = reserve0 + amountInAfterTax;
        amountOut = reserve1 - (reserve0 * reserve1) / newReserve0;

        reserve0 = newReserve0;
        reserve1 -= amountOut;

        (bool success, ) = msg.sender.call{value: amountOut}("");
        require(success, "Ether transfer failed");

        emit Swap(token0, address(0), amountIn, amountOut);

        if (autoMigrationEnabled && reserve1 >= migrationThreshold) {
            migrateToAlgebra();
        }
    }

    function getReserves() external view returns (uint256, uint256) {
        return (reserve0, reserve1);
    }

    function updateBuyTax(uint256 newBuyTax) external onlyFactory {
        buyTax = newBuyTax;
        emit TaxUpdated(newBuyTax, sellTax);
    }

    function updateSellTax(uint256 newSellTax) external onlyFactory {
        sellTax = newSellTax;
        emit TaxUpdated(buyTax, newSellTax);
    }
}
