// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

interface IAlgebraUnified {
    struct MintParams {
        address token0;
        address token1;
        address deployer;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        address deployer,
        uint160 sqrtPriceX96
    ) external payable returns (address pool);

    function mint(MintParams calldata params)
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );
}

/**
 * @title TransferHelper
 * @dev A utility library for safe token and Ether transfers.
 */
library TransferHelper {
    error STF(); // Safe Transfer From failed
    error ST();  // Safe Transfer failed
    error SA();  // Safe Approve failed
    error STE(); // Safe Transfer Native failed

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(
                IERC20(token).transferFrom.selector,
                from,
                to,
                value
            )
        );
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert STF();
        }
    }

    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(
                IERC20(token).transfer.selector,
                to, value
            )
        );
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert ST();
        }
    }

    function safeApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(
                IERC20(token).approve.selector,
                to,
                value
            )
        );
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert SA();
        }
    }

    function safeTransferNative(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}("");
        if (!success) {
            revert STE();
        }
    }
}

contract Migrator {
    using TransferHelper for address;

    address public owner;
    address public algebraUnified;
    address public WETH;
    address public rootstockAddress;  // redistribute to rootstock
    address public monarkTeamAddress;  // funds for team monark 
    address public DAO; //To redistribute winning tokens to DAO
    

    int24 public constant MIN_TICK = -887220;
    int24 public constant MAX_TICK = 887220;

    uint256 public constant MAX_ETH_LIMIT = 10 ether; // Limite maximale pour ETH
    uint256 public constant MAX_TOKEN_LIMIT = 21_000_000_000 * 1e18; // Limite maximale pour tokens
    uint256 public etherToRedistribute; //tokens that have to be transmited to monark team & rootstock. 
    uint256 public timestampForLimit; //max milestone for rootstock rewards
    uint256 public percentageToDistributeETH = 130; 

    address[] public listOfWinningTokens; // list of tokens that will be redistributed to the dao 
    
    
    mapping(address => bool) private whitelist;   
    mapping(address => uint256) private winningTokensAmount; 

    event MigrationInitialized(
        address indexed poolAddress,
        address indexed token,
        uint256 tokenAmount,
        uint256 ethAmount
    );

    event LiquidityAdded(
        address indexed poolAddress,
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    event AddressAddedToWhitelist(address indexed account);
    event AddressRemovedFromWhitelist(address indexed account);
    event EtherReceived(address indexed sender, uint256 amount, uint256 newTotal);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this");
        _;
    }

      modifier onlyWhitelisted() {
        require(whitelist[msg.sender], "Not authorized: caller is not whitelisted");
        _;
    }

    constructor(address _algebraUnified, address _WETH, address _rootstockAddress, address _monarkTeamAddress) {
        require(_algebraUnified != address(0), "Invalid Algebra address");
        require(_WETH != address(0), "Invalid WETH address");
        require(_rootstockAddress != address(0), "Invalid rootstock address");
        require(_monarkTeamAddress != address(0), "Invalid monarkTeam address");
        owner = msg.sender;
        algebraUnified = _algebraUnified;
        WETH = _WETH;
        rootstockAddress = _rootstockAddress;
        monarkTeamAddress = _monarkTeamAddress; 
    }

    function initiateMigration(address token, uint256 tokenAmount) external payable returns (address pool) {
    require(msg.value > 0, "Ether amount must be greater than zero");
    require(tokenAmount > 0, "Token amount must be greater than zero");
    uint256 tokenAmountDAOTax = (tokenAmount*1000) /30; 
    uint256 tokenAmountAfterTax = tokenAmount - tokenAmountDAOTax ; 
    listOfWinningTokens.push(token); 
    winningTokensAmount[token] = tokenAmountDAOTax; // distribute token to the dao 
    
    uint256 adjustedTokenAmount = tokenAmountAfterTax > MAX_TOKEN_LIMIT ? MAX_TOKEN_LIMIT : tokenAmountAfterTax;
    uint256 amountToCollect = (msg.value * 1000) /percentageToDistributeETH; 
    etherToRedistribute += amountToCollect; 
    uint256 adjustedEthAmount = msg.value > MAX_ETH_LIMIT ? MAX_ETH_LIMIT : msg.value  - amountToCollect ;


    IWETH(WETH).deposit{value: adjustedEthAmount}();
    uint256 wethBalance = IWETH(WETH).balanceOf(address(this));
    require(wethBalance >= adjustedEthAmount, "Failed to wrap Ether into WETH");

    token.safeTransferFrom(msg.sender, address(this), adjustedTokenAmount);

    address token0 = (token < WETH) ? token : WETH;
    address token1 = (token < WETH) ? WETH : token;

    uint160 sqrtPriceX96 = calculateSqrtPriceX96(adjustedTokenAmount, adjustedEthAmount);

    // Create the pool
    pool = IAlgebraUnified(algebraUnified).createAndInitializePoolIfNecessary(
        token0,
        token1,
        address(0),
        sqrtPriceX96
    );

    require(pool != address(0), "Failed to create Algebra pool");
    emit MigrationInitialized(pool, token, adjustedTokenAmount, adjustedEthAmount);

    token.safeApprove(algebraUnified, adjustedTokenAmount);
    WETH.safeApprove(algebraUnified, wethBalance);

    IAlgebraUnified.MintParams memory params = IAlgebraUnified.MintParams({
        token0: token0,
        token1: token1,
        deployer: address(0),
        tickLower: MIN_TICK,
        tickUpper: MAX_TICK,
        amount0Desired: (token0 == token) ? adjustedTokenAmount : wethBalance,
        amount1Desired: (token1 == token) ? wethBalance : adjustedTokenAmount,
        amount0Min: 0,
        amount1Min: 0,
        recipient: address(this),
        deadline: block.timestamp + 3600
    });

    (, uint128 liquidity, uint256 amount0, uint256 amount1) = IAlgebraUnified(algebraUnified).mint(params);

    require(liquidity > 0, "Failed to mint liquidity");
    emit LiquidityAdded(pool, 0, liquidity, amount0, amount1);

    return pool; // Return the address of the created pool
}

    function getFeesCreation() external payable {
        require(msg.value > 0, "Must send some Ether");

        // Ajoute le montant reçu à la variable totalCollected
        etherToRedistribute += msg.value;

        // Émet un événement pour signaler l'ajout
        emit EtherReceived(msg.sender, msg.value, etherToRedistribute);
    }


    function calculateSqrtPriceX96(uint256 tokenAmount, uint256 ethAmount) public pure returns (uint160) {
        uint256 adjustedTokenAmount = tokenAmount > MAX_TOKEN_LIMIT ? MAX_TOKEN_LIMIT : tokenAmount;
        uint256 adjustedEthAmount = ethAmount > MAX_ETH_LIMIT ? MAX_ETH_LIMIT : ethAmount;

        uint256 ratio = (adjustedEthAmount << 96) / adjustedTokenAmount;
        return uint160(sqrt(ratio) << 48);
    }

    function sqrt(uint256 x) internal pure returns (uint256) {
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    function updateAlgebraUnified(address _algebraUnified) external onlyOwner {
        require(_algebraUnified != address(0), "Invalid address");
        algebraUnified = _algebraUnified;
    }

    function updateWETH(address _WETH) external onlyOwner {
        require(_WETH != address(0), "Invalid address");
        WETH = _WETH;
    }
    function emergencyWithdraw() external onlyOwner {
    uint256 etherBalance = address(this).balance;
    if (etherBalance > 0) {
        (bool success, ) = owner.call{value: etherBalance}("");
        require(success, "Ether withdraw failed");
    }
}

function emergencyWithdrawTokens(address token) external onlyOwner {
    uint256 tokenBalance = IERC20(token).balanceOf(address(this));
    require(tokenBalance > 0, "No tokens to withdraw");
    IERC20(token).transfer(owner, tokenBalance);
}


function addToWhitelist(address account) external onlyOwner {
        require(!whitelist[account], "Address already whitelisted");
        whitelist[account] = true;
        emit AddressAddedToWhitelist(account);
    }

    /**
     * @dev Retirer une adresse de la whitelist
     * @param account Adresse à retirer
     */
    function removeFromWhitelist(address account) external onlyOwner {
        require(whitelist[account], "Address not in whitelist");
        whitelist[account] = false;
        emit AddressRemovedFromWhitelist(account);
    }

    /**
     * @dev Vérifier si une adresse est dans la whitelist
     * @param account Adresse à vérifier
     * @return bool Retourne vrai si l'adresse est whitelistée
     */
    function isWhitelisted(address account) external view returns (bool) {
        return whitelist[account];
    }

     function withdrawRewards() external onlyWhitelisted() {
        
        require(etherToRedistribute > 0, "No Ether to withdraw");
        uint256 toRootStock = (etherToRedistribute * 1000) /200; 
        uint256 toMonark = etherToRedistribute - toRootStock; 
        (bool successRootstock, ) = rootstockAddress.call{value: toRootStock}(""); 
        require(successRootstock, "Withdrawal failed");
        (bool successMonark, ) = monarkTeamAddress.call{value: toMonark}("");
        require(successMonark, "Withdrawal failed");
    }




    receive() external payable {}
}
