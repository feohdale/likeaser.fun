// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

library TransferHelper {
    error STF();
    error ST();
    error SA();
    error STE();

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
        require(balanceOf[msg.sender] >= amount, "ERC20: insufficient balance");
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
        require(balanceOf[from] >= amount, "ERC20: insufficient balance");
        require(allowance[from][msg.sender] >= amount, "ERC20: insufficient allowance");
        balanceOf[from] -= amount;
        allowance[from][msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

contract AlgebraPoolCreator {
    using TransferHelper for address;

    address public algebraUnified;
    address public WETH;
    address public tokenB;
    address public liquidityPool;

    uint256 public constant ETH_AMOUNT = 0.00001 ether;
    uint256 public constant TOKEN_AMOUNT = 420_000_000 * 1e18;

    int24 public constant MIN_TICK = -887220;
    int24 public constant MAX_TICK = 887220;

    event WETHWithdrawn(address indexed user, uint256 amount);

    constructor(address _algebraUnified, address _WETH) {
        algebraUnified = _algebraUnified;
        WETH = _WETH;

        SimpleERC20 tkb = new SimpleERC20("Token B", "TKB", TOKEN_AMOUNT, address(this));
        tokenB = address(tkb);
    }

    function createPoolAlgebra() external payable {
        require(liquidityPool == address(0), "Pool already exists");

        uint160 sqrtPriceX96 = 79228162514264337593543950336;

        address token0 = (WETH < tokenB) ? WETH : tokenB;
        address token1 = (WETH < tokenB) ? tokenB : WETH;

        address pool = IAlgebraUnified(algebraUnified).createAndInitializePoolIfNecessary(
            token0,
            token1,
            address(0),
            sqrtPriceX96
        );
        liquidityPool = pool;
    }

    function mintWithWETHAndTKB() external payable returns (
        uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1
    ) {
        require(liquidityPool != address(0), "Pool not created yet");
        require(msg.value == ETH_AMOUNT, "Must send exactly 0.00001 ETH");

        IWETH(WETH).deposit{value: msg.value}();

        uint256 wethBalance = IERC20(WETH).balanceOf(address(this));
        uint256 tkbBalance = IERC20(tokenB).balanceOf(address(this));
        require(wethBalance >= ETH_AMOUNT, "Not enough WETH");
        require(tkbBalance >= TOKEN_AMOUNT, "Not enough TKB");

        address token0 = (WETH < tokenB) ? WETH : tokenB;
        address token1 = (WETH < tokenB) ? tokenB : WETH;

        uint256 amount0Desired = (token0 == WETH) ? wethBalance : TOKEN_AMOUNT;
        uint256 amount1Desired = (token0 == WETH) ? TOKEN_AMOUNT : wethBalance;

        WETH.safeApprove(algebraUnified, wethBalance);
        tokenB.safeApprove(algebraUnified, TOKEN_AMOUNT);

        IAlgebraUnified.MintParams memory params = IAlgebraUnified.MintParams({
            token0: token0,
            token1: token1,
            deployer: address(0),
            tickLower: MIN_TICK,
            tickUpper: MAX_TICK,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (tokenId, liquidity, amount0, amount1) = IAlgebraUnified(algebraUnified).mint(params);
    }

    receive() external payable {}
}
