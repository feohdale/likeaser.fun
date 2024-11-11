// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./CustomToken.sol";
import "./LiquidityPool.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenFactory is Ownable {
    address[] public allTokens; // Liste des adresses des tokens créés
    address[] public allPools; // Liste des adresses des pools créées
    mapping(address => address) public tokenToPool; // Mapping pour associer un token à sa pool
    mapping(string => address) public tokenByName; // Mapping pour rechercher un token par son nom

    uint256 public constant INITIAL_TOKEN_SUPPLY = 21_000_000 * 10 ** 18; // 21 millions de tokens avec 18 décimales
    uint256 public constant CREATION_COST = 1 ether; // Coût de création du token en Ether
    uint256 public constant DEV_FEE_PERCENTAGE = 10; // Pourcentage des frais pour les développeurs
    uint256 public constant TOKEN_CREATOR_SHARE_PERCENTAGE = 10; // Pourcentage des tokens alloués au créateur

    address public devAddress; // Adresse des développeurs pour recevoir les frais

    event TokenCreated(address indexed tokenAddress, string name, string symbol, address indexed poolAddress);
    event TaxUpdated(address indexed poolAddress, uint256 newTax);

    constructor(address _devAddress) Ownable(msg.sender) {
        require(_devAddress != address(0), "Dev address cannot be zero address");
        devAddress = _devAddress;
    }

    // Fonction pour créer un nouveau token et sa pool de liquidité automatiquement
    function createToken(string memory name, string memory symbol) external payable returns (address) {
        require(tokenByName[name] == address(0), "Token with this name already exists");
        require(msg.value == CREATION_COST, "Initial Ether reserve must be exactly 1 Ether");

        // Transfert de 10% des frais de création à l'adresse des développeurs
        uint256 devFee = (CREATION_COST * DEV_FEE_PERCENTAGE) / 100;
        (bool devFeeSent, ) = devAddress.call{value: devFee}("");
        require(devFeeSent, "Failed to send dev fee");

        // Création du token
        CustomToken newToken = new CustomToken();
        newToken.initialize(name, symbol);
        
        // Calcul des tokens alloués au créateur (10%) et le reste pour la pool de liquidité
        uint256 creatorShare = (INITIAL_TOKEN_SUPPLY * TOKEN_CREATOR_SHARE_PERCENTAGE) / 100;
        uint256 poolTokenShare = INITIAL_TOKEN_SUPPLY - creatorShare;

        // Mint de l'intégralité des tokens dans la factory, puis transfert
        newToken.mint(address(this), INITIAL_TOKEN_SUPPLY);
        newToken.transfer(msg.sender, creatorShare); // Transfert au créateur pour le vesting

        address tokenAddress = address(newToken);
        allTokens.push(tokenAddress);
        tokenByName[name] = tokenAddress;

        // Création automatique de la pool de liquidité
        LiquidityPool pool = new LiquidityPool();
        pool.initialize{value: msg.value - devFee}(tokenAddress, address(this), poolTokenShare, 2); // Exemple de taxe de 2%
        
        // Transfert des tokens à la pool de liquidité
        newToken.transfer(address(pool), poolTokenShare);

        address poolAddress = address(pool);
        allPools.push(poolAddress);
        tokenToPool[tokenAddress] = poolAddress;

        emit TokenCreated(tokenAddress, name, symbol, poolAddress);

        return tokenAddress;
    }

    // Fonction pour mettre à jour la taxe de tous les contrats de pool
    function updateTaxForAllPools(uint256 newTaxPercentage) external onlyOwner {
        require(newTaxPercentage >= 0, "Tax must be non-negative");

        for (uint256 i = 0; i < allPools.length; i++) {
            LiquidityPool(allPools[i]).updateTaxPercentage(newTaxPercentage);
            emit TaxUpdated(allPools[i], newTaxPercentage);
        }
    }
}
