// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LiquidityPool is ReentrancyGuard {
    address public token0; // Adresse du token ERC20
    address public tokenFactory; // Adresse du contrat TokenFactory
    uint256 public reserve0; // Réserve de tokens ERC20
    uint256 public reserve1; // Réserve de la cryptomonnaie native (par exemple, Ether)
    uint256 public buyTax = 0; // Taxe d'achat en millièmes (par défaut 0%)
    uint256 public sellTax = 10; // Taxe de vente en millièmes (par défaut 1%)
    address public devAddress; // Adresse dédiée pour recevoir les taxes
    uint256 public penaltyThreshold = 200; // Seuil de 20% (200/1000) pour appliquer la pénalité
    bool public penaltiesEnabled = false; // Indique si les pénalités sont activées

    modifier onlyFactory() {
        require(msg.sender == tokenFactory, "Caller is not the TokenFactory");
        _;
    }

    event BuyToken(address indexed buyer, uint256 etherAmount, uint256 tokenAmount);
    event SellToken(address indexed seller, uint256 tokenAmount, uint256 etherAmount);
    event LiquidityAdded(address indexed provider, uint256 amountToken, uint256 amountNative);
    event BuyTaxUpdated(uint256 newBuyTax);
    event SellTaxUpdated(uint256 newSellTax);
    event PenaltyApplied(address indexed trader, uint256 penaltyAmount, uint256 newAmountOut);
    event PenaltiesStatusUpdated(bool enabled);

    constructor(address _devAddress, address _tokenFactory) {
        require(_devAddress != address(0), "Developer address cannot be zero address");
        require(_tokenFactory != address(0), "TokenFactory address cannot be zero address");
        devAddress = _devAddress;
        tokenFactory = _tokenFactory;
    }

    /// @notice Initialise la pool avec des réserves et les taxes par défaut
    function initialize(
        address _token0,
        uint256 _initialTokenReserve
    ) external payable nonReentrant onlyFactory {
        require(token0 == address(0), "Pool already initialized");
        require(msg.value > 0, "Initial native token amount must be greater than zero");

        token0 = _token0;
        reserve0 = _initialTokenReserve;
        reserve1 = msg.value;

        emit LiquidityAdded(msg.sender, _initialTokenReserve, msg.value);
    }

    /// @notice Mise à jour de la taxe d'achat
    function updateBuyTax(uint256 newBuyTax) external onlyFactory {
        require(newBuyTax + sellTax <= 50, "Total tax cannot exceed 5%");
        buyTax = newBuyTax;
        emit BuyTaxUpdated(newBuyTax);
    }

    /// @notice Mise à jour de la taxe de vente
    function updateSellTax(uint256 newSellTax) external onlyFactory {
        require(buyTax + newSellTax <= 50, "Total tax cannot exceed 5%");
        sellTax = newSellTax;
        emit SellTaxUpdated(newSellTax);
    }

    /// @notice Achat de tokens avec de l'Ether
    function buyToken() external payable nonReentrant returns (uint256 amountOut) {
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

        emit BuyToken(msg.sender, msg.value, amountOut);
    }

    /// @notice Vente de tokens pour de l'Ether
    function sellToken(uint256 amountIn) external nonReentrant returns (uint256 amountOut) {
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

        emit SellToken(msg.sender, amountIn, amountOut);
    }

    /// @notice Calcule le prix des tokens pour un montant donné en Ether
    function calculatePriceForTokens(uint256 etherAmount) public view returns (uint256 tokenAmount) {
        uint256 amountInAfterTax = etherAmount - (etherAmount * buyTax) / 1000;
        uint256 newReserve1 = reserve1 + amountInAfterTax;
        tokenAmount = reserve0 - (reserve0 * reserve1) / newReserve1;
    }

    /// @notice Calcule le prix de l'Ether pour un nombre donné de tokens
    function calculatePriceForEther(uint256 tokenAmount) public view returns (uint256 etherAmount) {
        uint256 amountInAfterTax = tokenAmount - (tokenAmount * sellTax) / 1000;
        uint256 newReserve0 = reserve0 + amountInAfterTax;
        etherAmount = reserve1 - (reserve0 * reserve1) / newReserve0;
    }

    /// @notice Active ou désactive les pénalités
    function togglePenalties(bool enable) external onlyFactory {
        penaltiesEnabled = enable;
        emit PenaltiesStatusUpdated(enable);
    }

    /// @notice Calcule la pénalité pour une vente importante
    function calculatePenalty(uint256 amountIn) public view returns (uint256 penaltyAmount, uint256 penaltyPercentage) {
        uint256 circulatingSupply = IERC20(token0).totalSupply();
        uint256 sellPercentage = (amountIn * 1000) / circulatingSupply;

        if (penaltiesEnabled && sellPercentage > penaltyThreshold) {
            penaltyPercentage = sellPercentage - penaltyThreshold;
            penaltyAmount = (penaltyPercentage * amountIn) / 1000;
        } else {
            penaltyAmount = 0;
            penaltyPercentage = 0;
        }

        return (penaltyAmount, penaltyPercentage);
    }
}
