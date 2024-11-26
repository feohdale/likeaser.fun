// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./CustomToken.sol";
import "./LiquidityPool.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenFactory is Ownable {
    struct TokenInfo {
        address tokenAddress;
        address liquidityPoolAddress;
    }

    TokenInfo[] public allTokens;
    mapping(address => address) public tokenToPool; // Mapping pour associer un token à sa pool
    mapping(string => address) public tokenByName; // Mapping pour rechercher un token par son nom

    uint256 public constant INITIAL_TOKEN_SUPPLY = 21_000_000 * 10 ** 18; // 21 millions de tokens
    uint256 public constant CREATION_COST = 1 ether; // Coût de création du token
    uint256 public constant DEV_FEE_PERCENTAGE = 10; // Pourcentage des frais pour les développeurs
    uint256 public constant DAO_TAX_PERCENTAGE = 3; // Pourcentage pour la DAO
    uint256 public constant TOKEN_CREATOR_SHARE_PERCENTAGE = 10; // Pourcentage des tokens alloués au créateur

    address public devAddress; // Adresse des développeurs pour recevoir les frais
    address public daoAddress; // Adresse de la DAO pour recevoir la taxe

    bool public distributeToCreator = false; // Désactivé par défaut

    event TokenCreated(address indexed tokenAddress, string name, string symbol, address indexed poolAddress);
    event PenaltiesStatusUpdated(address indexed poolAddress, bool enabled);
    event DistributionToCreatorToggled(bool enabled);

    constructor(address _devAddress, address _daoAddress) Ownable(msg.sender) {
        require(_devAddress != address(0), "Dev address cannot be zero address");
        require(_daoAddress != address(0), "DAO address cannot be zero address");
        devAddress = _devAddress;
        daoAddress = _daoAddress;
    }

    function createToken(string memory name, string memory symbol) external payable returns (address) {
        require(tokenByName[name] == address(0), "Token with this name already exists");
        require(msg.value == CREATION_COST, "Initial Ether reserve must be exactly 1 Ether");

        // Transfert des frais aux développeurs
        uint256 devFee = (CREATION_COST * DEV_FEE_PERCENTAGE) / 100;
        uint256 remainingAmount = CREATION_COST - devFee;

        (bool devFeeSent, ) = devAddress.call{value: devFee}("");
        require(devFeeSent, "Failed to send dev fee");

        // Création du token
        CustomToken newToken = new CustomToken();
        newToken.initialize(name, symbol);

        // Allocation des tokens
        uint256 daoTax = (INITIAL_TOKEN_SUPPLY * DAO_TAX_PERCENTAGE) / 100;
        uint256 poolTokenShare = INITIAL_TOKEN_SUPPLY - daoTax;

        if (distributeToCreator) {
            uint256 creatorShare = (INITIAL_TOKEN_SUPPLY * TOKEN_CREATOR_SHARE_PERCENTAGE) / 100;
            poolTokenShare -= creatorShare;
            newToken.mint(msg.sender, creatorShare);
        }

        newToken.mint(daoAddress, daoTax); // Alloue la taxe directement à la DAO
        newToken.mint(address(this), poolTokenShare);

        // Création de la pool de liquidité
        LiquidityPool pool = new LiquidityPool(devAddress, address(this));
        pool.initialize{value: remainingAmount}(address(newToken), poolTokenShare, 2); // 2% de taxe initiale
        newToken.transfer(address(pool), poolTokenShare);

        // Stockage des informations
        address tokenAddress = address(newToken);
        address poolAddress = address(pool);

        allTokens.push(TokenInfo(tokenAddress, poolAddress));
        tokenToPool[tokenAddress] = poolAddress;
        tokenByName[name] = tokenAddress;

        emit TokenCreated(tokenAddress, name, symbol, poolAddress);

        return tokenAddress;
    }

    // Fonction pour activer/désactiver la distribution des tokens au créateur
    function toggleDistributionToCreator(bool enable) external onlyOwner {
        distributeToCreator = enable;
        emit DistributionToCreatorToggled(enable);
    }

    // Fonction pour activer ou désactiver les pénalités pour toutes les pools
    function togglePenaltiesForAllPools(bool enable) external onlyOwner {
        for (uint256 i = 0; i < allTokens.length; i++) {
            address poolAddress = allTokens[i].liquidityPoolAddress;
            LiquidityPool(poolAddress).togglePenalties(enable);
            emit PenaltiesStatusUpdated(poolAddress, enable);
        }
    }

    // Fonction pour obtenir le nombre total de tokens créés
    function getTotalTokensCreated() external view returns (uint256) {
        return allTokens.length;
    }

    // Fonction pour obtenir la liste complète des tokens
    function getAllTokens() external view returns (TokenInfo[] memory) {
        return allTokens;
    }
}
