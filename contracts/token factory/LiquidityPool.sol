// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LiquidityPool is ReentrancyGuard {
    address public token0; // Address of the ERC20 token
    address public tokenFactory; // Address of the TokenFactory contract
    uint256 public reserve0; // Reserve of tokens in the pool
    uint256 public reserve1; // Reserve of ether in the pool
    uint256 public buyTax; // Buy tax in thousandths
    uint256 public sellTax; // Sell tax in thousandths
    address public devAddress; // Developer address for taxes

    modifier onlyFactory() {
        require(msg.sender == tokenFactory, "Caller is not the TokenFactory");
        _;
    }

    event TokensPurchased(address indexed buyer, uint256 amountInEther, uint256 amountOutTokens, uint256 buyTax);
    event TokensSold(address indexed seller, uint256 amountInTokens, uint256 amountOutEther, uint256 sellTax);
    event LiquidityAdded(uint256 amountToken, uint256 amountEther);
    event BuyTaxUpdated(uint256 newBuyTax);
    event SellTaxUpdated(uint256 newSellTax);

    constructor(address _devAddress, address _tokenFactory) {
        require(_devAddress != address(0), "Developer address cannot be zero address");
        require(_tokenFactory != address(0), "TokenFactory address cannot be zero address");
        devAddress = _devAddress;
        tokenFactory = _tokenFactory;
    }

    function initialize(
        address _token0,
        uint256 _initialTokenReserve,
        uint256 _buyTax,
        uint256 _sellTax
    ) external payable onlyFactory {
        require(token0 == address(0), "Pool already initialized");
        require(msg.value > 0, "Initial ether reserve must be greater than zero");

        token0 = _token0;
        reserve0 = _initialTokenReserve;
        reserve1 = msg.value;
        buyTax = _buyTax;
        sellTax = _sellTax;

        emit LiquidityAdded(_initialTokenReserve, msg.value);
    }

    function buyToken() external payable nonReentrant returns (uint256 amountOut) {
        require(msg.value > 0, "Must send ether to buy tokens");

        uint256 tax = (msg.value * buyTax) / 1000;
        uint256 amountInAfterTax = msg.value - tax;

        (bool taxSent, ) = devAddress.call{value: tax}("");
        require(taxSent, "Failed to send buy tax");

        uint256 newReserve1 = reserve1 + amountInAfterTax;
        amountOut = reserve0 - (reserve0 * reserve1) / newReserve1;

        reserve1 = newReserve1;
        reserve0 -= amountOut;

        IERC20(token0).transfer(msg.sender, amountOut);

        emit TokensPurchased(msg.sender, msg.value, amountOut, tax);
    }

    function sellToken(uint256 amountIn) external nonReentrant returns (uint256 amountOut) {
        require(amountIn > 0, "Must sell some tokens");

        uint256 tax = (amountIn * sellTax) / 1000;
        uint256 amountInAfterTax = amountIn - tax;

        uint256 newReserve0 = reserve0 + amountInAfterTax;
        amountOut = reserve1 - (reserve0 * reserve1) / newReserve0;

        // Send sell tax to the developer address
        uint256 etherTax = (amountOut * sellTax) / 1000;
        amountOut -= etherTax;

        (bool taxSent, ) = devAddress.call{value: etherTax}("");
        require(taxSent, "Failed to send sell tax");

        reserve0 = newReserve0;
        reserve1 -= amountOut;

        IERC20(token0).transferFrom(msg.sender, address(this), amountIn);
        (bool success, ) = msg.sender.call{value: amountOut}("");
        require(success, "Failed to send ether");

        emit TokensSold(msg.sender, amountIn, amountOut, sellTax);
    }

    function updateBuyTax(uint256 newBuyTax) external onlyFactory {
        require(newBuyTax + sellTax <= 50, "Total tax cannot exceed 5%");
        buyTax = newBuyTax;
        emit BuyTaxUpdated(newBuyTax);
    }

    function updateSellTax(uint256 newSellTax) external onlyFactory {
        require(buyTax + newSellTax <= 50, "Total tax cannot exceed 5%");
        sellTax = newSellTax;
        emit SellTaxUpdated(newSellTax);
    }

    function getReserve() external view returns (uint256 tokenReserve, uint256 etherReserve) {
        return (reserve0, reserve1);
    }
}
