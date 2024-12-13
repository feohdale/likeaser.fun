// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title Interface d'Algebra (version avec paramètre sendNativeTRBTC)
 */
interface IAlgebraFactory {
  
    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        address deployer,
        uint160 sqrtPriceX96,
        uint256 sendNativeTRBTC
    ) external payable returns (address pool);
}


contract SimpleERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialMint,
        address _owner
    ) {
        name = _name;
        symbol = _symbol;
        _mint(_owner, _initialMint);
    }
    
    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "ERC20: balance too low");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "ERC20: balance too low");
        require(allowance[from][msg.sender] >= amount, "ERC20: allowance too low");
        balanceOf[from] -= amount;
        allowance[from][msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}


contract AlgebraPoolCreator {
    address public tokenA;
    address public tokenB;

    address public algebraFactory;

    address public liquidityPool;

    constructor(address _algebraFactory) {
        algebraFactory = _algebraFactory;

        SimpleERC20 _tokenA = new SimpleERC20(
            "Token A",
            "TKA",
            1000 ether,  // 1000 tokens
            msg.sender
        );
        SimpleERC20 _tokenB = new SimpleERC20(
            "Token B",
            "TKB",
            1000 ether,
            msg.sender
        );
        
        tokenA = address(_tokenA);
        tokenB = address(_tokenB);
    }


    function createPoolAlgebra(uint160 _sqrtPriceX96, uint256 _sendNativeTRBTC) external payable {
        IAlgebraFactory factory = IAlgebraFactory(algebraFactory);

        // Appel avec 5 paramètres + payable
        address pool = factory.createAndInitializePoolIfNecessary{value: msg.value}(
            tokenA,
            tokenB,
            address(0x0000000000000000000000000000000000000000),     
            _sqrtPriceX96,
            _sendNativeTRBTC
        );
        
        liquidityPool = pool;
    }
}
