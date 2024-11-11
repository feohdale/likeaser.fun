// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LiquidityPool {
    address public token0; // Adresse du token ERC20
    address public tokenFactory; // Adresse du contrat TokenFactory
    uint256 public reserve0; // Réserve de tokens ERC20
    uint256 public reserve1; // Réserve de la cryptomonnaie native (par exemple, Ether)
    uint256 public taxPercentage; // Taux de taxe pour les transactions dans la pool
    address public devAddress; // Adresse dédiée pour recevoir les taxes

    modifier onlyFactory() {
        require(msg.sender == tokenFactory, "Caller is not the TokenFactory");
        _;
    }

    event Swap(address indexed fromToken, address indexed toToken, uint256 amountIn, uint256 amountOut);
    event LiquidityAdded(address indexed provider, uint256 amountToken, uint256 amountNative);
    event TaxPercentageUpdated(uint256 newTaxPercentage);

    constructor(address _devAddress) {
        require(_devAddress != address(0), "Developer address cannot be zero address");
        devAddress = _devAddress;
    }

    function initialize(
        address _token0,
        address _tokenFactory,
        uint256 _initialTokenReserve,
        uint256 _taxPercentage
    ) external payable {
        require(token0 == address(0), "Pool already initialized"); // Assure une initialisation unique
        require(msg.value > 0, "Initial native token amount must be greater than zero");

        token0 = _token0;
        tokenFactory = _tokenFactory;
        taxPercentage = _taxPercentage;

        reserve0 = _initialTokenReserve;
        reserve1 = msg.value;

        emit LiquidityAdded(msg.sender, _initialTokenReserve, msg.value);
    }

    function updateTaxPercentage(uint256 newTaxPercentage) external onlyFactory {
        taxPercentage = newTaxPercentage;
        emit TaxPercentageUpdated(newTaxPercentage);
    }

    // Fonction d'achat de tokens avec de l'Ether
    function buyToken() external payable returns (uint256 amountOut) {
        require(msg.value > 0, "Must send Ether to buy tokens");

        uint256 tax = (msg.value * taxPercentage) / 100;
        uint256 amountInAfterTax = msg.value - tax;

        // Envoyer la taxe à l'adresse des développeurs
        (bool taxSent, ) = devAddress.call{value: tax}("");
        require(taxSent, "Failed to send tax to dev address");

        uint256 newReserve1 = reserve1 + amountInAfterTax;
        amountOut = reserve0 - (reserve0 * reserve1) / newReserve1;

        reserve1 = newReserve1;
        reserve0 -= amountOut;

        IERC20(token0).transfer(msg.sender, amountOut);

        emit Swap(address(0), token0, msg.value, amountOut);
    }

    // Fonction de vente de tokens pour de l'Ether
    function sellToken(uint256 amountIn) external returns (uint256 amountOut) {
        require(amountIn > 0, "Must sell some tokens");

        uint256 tax = (amountIn * taxPercentage) / 100;
        uint256 amountInAfterTax = amountIn - tax;

        // Transfert de la taxe en tokens vers l'adresse des développeurs
        IERC20(token0).transfer(devAddress, tax);

        uint256 newReserve0 = reserve0 + amountInAfterTax;
        amountOut = reserve1 - (reserve0 * reserve1) / newReserve0;

        reserve0 = newReserve0;
        reserve1 -= amountOut;

        IERC20(token0).transferFrom(msg.sender, address(this), amountIn);
        
        (bool success, ) = msg.sender.call{value: amountOut}("");
        require(success, "Ether transfer failed");

        emit Swap(token0, address(0), amountIn, amountOut);
    }

    function getPriceInNative() public view returns (uint256) {
        return (reserve1 * 1e18) / reserve0;
    }

    function getPriceInToken() public view returns (uint256) {
        return (reserve0 * 1e18) / reserve1;
    }

    function calculateSlippageOnBuy(uint256 ethAmount) public view returns (uint256 slippage) {
        uint256 newReserve1 = reserve1 + ethAmount;
        uint256 amountOut = reserve0 - (reserve0 * reserve1) / newReserve1;
        uint256 priceImpact = ((reserve0 - amountOut) * 1e18) / reserve0;
        slippage = 1e18 - priceImpact;
    }

    function calculateSlippageOnSell(uint256 tokenAmount) public view returns (uint256 slippage) {
        uint256 newReserve0 = reserve0 + tokenAmount;
        uint256 amountOut = reserve1 - (reserve0 * reserve1) / newReserve0;
        uint256 priceImpact = ((reserve1 - amountOut) * 1e18) / reserve1;
        slippage = 1e18 - priceImpact;
    }
}
