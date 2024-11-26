// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract LiquidityPool is ReentrancyGuard {
    address public token0; // Adresse du token ERC20
    address public tokenFactory; // Adresse du contrat TokenFactory
    uint256 public reserve0; // Réserve de tokens ERC20
    uint256 public reserve1; // Réserve de la cryptomonnaie native (par exemple, Ether)
    uint256 public taxPercentage; // Taux de taxe pour les transactions dans la pool
    address public devAddress; // Adresse dédiée pour recevoir les taxes
    uint256 public penaltyThreshold = 20; // Seuil de 20% pour appliquer la pénalité
    bool public penaltiesEnabled = false; // Indique si les pénalités sont activées

    modifier onlyFactory() {
        require(msg.sender == tokenFactory, "Caller is not the TokenFactory");
        _;
    }

    event Swap(address indexed fromToken, address indexed toToken, uint256 amountIn, uint256 amountOut);
    event LiquidityAdded(address indexed provider, uint256 amountToken, uint256 amountNative);
    event TaxPercentageUpdated(uint256 newTaxPercentage);
    event PenaltyApplied(address indexed trader, uint256 penaltyAmount, uint256 newAmountOut);
    event PenaltiesStatusUpdated(bool enabled);

    constructor(address _devAddress, address _tokenFactory) {
        require(_devAddress != address(0), "Developer address cannot be zero address");
        require(_tokenFactory != address(0), "TokenFactory address cannot be zero address");
        devAddress = _devAddress;
        tokenFactory = _tokenFactory;
    }

    function initialize(
        address _token0,
        uint256 _initialTokenReserve,
        uint256 _taxPercentage
    ) external payable nonReentrant onlyFactory {
        require(token0 == address(0), "Pool already initialized");
        require(msg.value > 0, "Initial native token amount must be greater than zero");

        token0 = _token0;
        taxPercentage = _taxPercentage;

        reserve0 = _initialTokenReserve;
        reserve1 = msg.value;

        emit LiquidityAdded(msg.sender, _initialTokenReserve, msg.value);
    }

    function updateTaxPercentage(uint256 newTaxPercentage) external onlyFactory {
        taxPercentage = newTaxPercentage;
        emit TaxPercentageUpdated(newTaxPercentage);
    }

    function togglePenalties(bool enable) external onlyFactory {
        penaltiesEnabled = enable;
        emit PenaltiesStatusUpdated(enable);
    }

    function buyToken() external payable nonReentrant returns (uint256 amountOut) {
        require(msg.value > 0, "Must send Ether to buy tokens");

        uint256 tax = (msg.value * taxPercentage) / 100;
        uint256 amountInAfterTax = msg.value - tax;

        (bool taxSent, ) = devAddress.call{value: tax}("");
        require(taxSent, "Failed to send tax to dev address");

        uint256 newReserve1 = reserve1 + amountInAfterTax;
        amountOut = reserve0 - (reserve0 * reserve1) / newReserve1;

        reserve1 = newReserve1;
        reserve0 -= amountOut;

        IERC20(token0).transfer(msg.sender, amountOut);

        emit Swap(address(0), token0, msg.value, amountOut);
    }

    function sellToken(uint256 amountIn) external nonReentrant returns (uint256 amountOut) {
        require(amountIn > 0, "Must sell some tokens");

        uint256 circulatingSupply = IERC20(token0).totalSupply();
        uint256 sellPercentage = (amountIn * 100) / circulatingSupply;

        uint256 tax = (amountIn * taxPercentage) / 100;
        uint256 amountInAfterTax = amountIn - tax;

        uint256 penalty = 0;
        if (penaltiesEnabled && sellPercentage > penaltyThreshold) {
            penalty = ((sellPercentage - penaltyThreshold) * amountInAfterTax) / 100;
            amountInAfterTax -= penalty;

            reserve1 += penalty;
            emit PenaltyApplied(msg.sender, penalty, amountInAfterTax);
        }

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

    function calculatePenalty(uint256 amountIn) public view returns (uint256 penaltyAmount, uint256 penaltyPercentage) {
        uint256 circulatingSupply = IERC20(token0).totalSupply();
        uint256 sellPercentage = (amountIn * 100) / circulatingSupply;

        if (penaltiesEnabled && sellPercentage > penaltyThreshold) {
            penaltyPercentage = sellPercentage - penaltyThreshold;
            penaltyAmount = (penaltyPercentage * amountIn) / 100;
        } else {
            penaltyAmount = 0;
            penaltyPercentage = 0;
        }

        return (penaltyAmount, penaltyPercentage);
    }
}
