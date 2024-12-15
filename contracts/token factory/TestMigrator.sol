// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Migrator.sol";

contract TestMigrator {
    Migrator public migrator;
    CustomToken public customToken;
    address public weth;
    address public algebraUnified;

    event MigrationExecuted(address indexed token, uint256 tokenAmount, uint256 ethAmount);

    constructor(address _algebraUnified, address _weth) {
        require(_algebraUnified != address(0), "Invalid AlgebraUnified address");
        require(_weth != address(0), "Invalid WETH address");

        weth = _weth;
        algebraUnified = _algebraUnified;

        // Déployer le Migrator
        migrator = new Migrator(algebraUnified, weth);

        // Déployer un CustomToken pour les tests
        customToken = new CustomToken("CustomToken", "CTK", 1_000_000 * 1e18);
    }

    function createAndMigrate(uint256 tokenAmount) external payable {
        require(msg.value > 0, "Ether amount must be greater than 0");
        require(tokenAmount > 0, "Token amount must be greater than 0");
        require(tokenAmount <= customToken.balanceOf(address(this)), "Not enough tokens available");

        // Approuver le transfert des tokens au Migrator
        customToken.approve(address(migrator), tokenAmount);

        // Appeler la fonction de migration dans Migrator
        migrator.initiateMigration{value: msg.value}(address(customToken), tokenAmount);

        emit MigrationExecuted(address(customToken), tokenAmount, msg.value);
    }

    function getMigratorAddress() external view returns (address) {
        return address(migrator);
    }

    function getCustomTokenAddress() external view returns (address) {
        return address(customToken);
    }
}

contract CustomToken {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint256 _initialSupply) {
        name = _name;
        symbol = _symbol;
        totalSupply = _initialSupply;
        balanceOf[msg.sender] = _initialSupply;
        emit Transfer(address(0), msg.sender, _initialSupply);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "CustomToken: insufficient balance");
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
        require(balanceOf[from] >= amount, "CustomToken: insufficient balance");
        require(allowance[from][msg.sender] >= amount, "CustomToken: insufficient allowance");
        balanceOf[from] -= amount;
        allowance[from][msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
