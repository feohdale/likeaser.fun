// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LiquidityPool is ReentrancyGuard {
    uint256 public constant X_DELTA_LOWER = 257627658726967931872702964;
    uint256 public constant X_DELTA_UPPER = 257627658726993462773682809;
    uint256 public constant Y_DELTA_LOWER = 31864892854290958;
    uint256 public constant Y_DELTA_UPPER = 31864892854294116;

    address public token0; // ERC20 token address
    address public tokenFactory; // TokenFactory address
    address public devAddress; // Developer address
    address public algebraPoolInitializer; // Algebra PoolInitializer contract address
    uint256 public reserve0; // Token reserve
    uint256 public reserve1; // Native currency reserve (e.g., Ether)
    uint256 public buyTax; // Buy tax in thousandths
    uint256 public sellTax; // Sell tax in thousandths
    bool public migratedToAlgebra; // Whether the pool has migrated to Algebra
    bool public autoMigrationEnabled = true; // Whether auto-migration is enabled
    uint256 public migrationThreshold; // Threshold to trigger migration

    event TokensPurchased(address indexed buyer, uint256 amountIn, uint256 amountOut, uint256 tax);
    event TokensSold(address indexed seller, uint256 amountIn, uint256 amountOut, uint256 tax);
    event LiquidityAdded(address indexed provider, uint256 tokenAmount);
    event TaxUpdated(uint256 newBuyTax, uint256 newSellTax);
    event MigrationToAlgebra(address indexed newPoolAddress, uint256 tokenTransferred, uint256 etherTransferred);
    event AlgebraPoolInitializerUpdated(address indexed newInitializer);
    event MigrationThresholdUpdated(uint256 newThreshold);
    event AutoMigrationToggled(bool enabled);
    event Step(string step, address indexed dataAddress, uint256 indexed value);

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
        uint256 _sellTax,
        address _algebraPoolInitializer,
        bool _automigration
    ) external payable onlyFactory nonReentrant {
        require(token0 == address(0), "Pool already initialized");

        token0 = _token0;
        reserve0 = _initialTokenReserve;
        buyTax = _buyTax;
        sellTax = _sellTax;
        algebraPoolInitializer = _algebraPoolInitializer;
        autoMigrationEnabled = _automigration; 
        emit LiquidityAdded(msg.sender, _initialTokenReserve);
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
    emit Step("Migration started", address(this), block.timestamp);
    
    require(!migratedToAlgebra, "Already migrated to Algebra");
    emit Step("Migration check passed", address(this), block.timestamp);
    
    require(algebraPoolInitializer != address(0), "Algebra PoolInitializer address not set");
    emit Step("Initializer check passed", algebraPoolInitializer, block.timestamp);
    
    uint160 sqrtPriceX96 = calculateSqrtPriceX96(1, 100); // Adjust parameters as needed
    emit Step("SqrtPriceX96 calculated", address(0), sqrtPriceX96);

    bytes memory payload = abi.encodeWithSignature(
        "createAndInitializePoolIfNecessary(address,address,uint160)",
        token0,
        address(this),
        sqrtPriceX96
    );

    (bool success, bytes memory returnData) = algebraPoolInitializer.call(payload);
    emit Step("Call to initializer made", address(algebraPoolInitializer), success ? 1 : 0);
    require(success, "Algebra pool creation and initialization failed");

    address newPoolAddress = abi.decode(returnData, (address));
    emit Step("Pool address decoded", newPoolAddress, block.timestamp);
    require(newPoolAddress != address(0), "Invalid Algebra pool address");

    IERC20(token0).transfer(newPoolAddress, reserve0);
    emit Step("Tokens transferred", newPoolAddress, reserve0);

    (bool etherTransferSuccess, ) = newPoolAddress.call{value: reserve1}("");
    require(etherTransferSuccess, "Failed to transfer Ether to Algebra pool");
    emit Step("Ether transferred", newPoolAddress, reserve1);

    migratedToAlgebra = true;
    emit MigrationToAlgebra(newPoolAddress, reserve0, reserve1);
}

    function buyToken()
        external
        payable
        nonReentrant
        returns (uint256 amountOut)
    {
        require(!migratedToAlgebra, "Pool migrated to Algebra");
        require(msg.value > 0, "Must send Ether to buy tokens");
        require(reserve1 < 0.2 ether, "Pool is full");
        require(reserve0 > 0, "No tokens in the pool");

        uint256 tax = (msg.value * buyTax) / 1000;
        uint256 amountInAfterTax = msg.value - tax;

        if (reserve1 + amountInAfterTax >= 0.2 ether) {
            uint256 etherToUse = 0.2 ether - reserve1;
            uint256 refund = amountInAfterTax - etherToUse;

            reserve1 += etherToUse;
            amountOut = reserve0;
            reserve0 = 0;

            if (refund > 0) {
                (bool refundSent, ) = msg.sender.call{value: refund}("");
                require(refundSent, "Failed to refund excess ether");
            }
        } else {
            uint256 newReserve1 = reserve1 + amountInAfterTax;
            uint256 quotient = ((reserve0 + X_DELTA_UPPER) *
                (reserve1 + Y_DELTA_UPPER)) / (newReserve1 + Y_DELTA_LOWER);
            if (quotient < X_DELTA_LOWER) {
                quotient = X_DELTA_LOWER;
            }
            uint256 newReserve0 = quotient - X_DELTA_LOWER;
            amountOut = newReserve0 > reserve0 ? reserve0 : reserve0 - newReserve0;

            reserve1 = newReserve1;
            reserve0 -= amountOut;
        }

        require(IERC20(token0).transfer(msg.sender, amountOut), "Failed to transfer tokens");

        (bool taxSent, ) = devAddress.call{value: tax}("");
        require(taxSent, "Failed to send buy tax");
        emit TokensPurchased(msg.sender, msg.value, amountOut, tax);
    }

    function sellToken(
        uint256 amountIn
    ) external nonReentrant returns (uint256 amountOut) {
        require(amountIn > 0, "Must sell some tokens");

        uint256 newReserve0 = reserve0 + amountIn;
        uint256 quotient = ((reserve0 + X_DELTA_UPPER) * (reserve1 + Y_DELTA_UPPER)) / 
            (newReserve0 + X_DELTA_UPPER);
        if (quotient < Y_DELTA_UPPER) {
            quotient = Y_DELTA_UPPER;
        }
        uint256 newReserve1 = quotient - Y_DELTA_UPPER;
        amountOut = newReserve1 > reserve1 ? reserve1 : reserve1 - newReserve1;

        reserve0 = newReserve0;
        reserve1 -= amountOut;
        
        // Send sell tax to the developer address
        uint256 etherTax = (amountOut * sellTax) / 1000;
        amountOut -= etherTax;

        (bool taxSent, ) = devAddress.call{value: etherTax}("");
        require(taxSent, "Failed to send sell tax");


        require(IERC20(token0).transferFrom(msg.sender, address(this), amountIn), "Failed to transfer tokens"   );
        (bool success, ) = msg.sender.call{value: amountOut}("");
        require(success, "Failed to send ether");

        emit TokensSold(msg.sender, amountIn, amountOut, sellTax);
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
    function forceMigration() external  {
    migrateToAlgebra();
}
function calculateSqrtPriceX96(uint256 amount0, uint256 amount1) public pure returns (uint160) {
    require(amount0 > 0 && amount1 > 0, "Amounts must be greater than zero");
    uint256 ratio = (amount1 << 96) / amount0; // Multiplie amount1 par 2^96 pour obtenir le ratio en virgule fixe
    uint160 sqrtPriceX96 = uint160(sqrt(ratio) << 48); // La racine carrée du ratio multipliée par 2^48
    return sqrtPriceX96;
}

// Fonction auxiliaire pour calculer la racine carrée
function sqrt(uint256 x) internal pure returns (uint256) {
    uint256 z = (x + 1) / 2;
    uint256 y = x;
    while (z < y) {
        y = z;
        z = (x / z + z) / 2;
    }
    return y;
}

}
