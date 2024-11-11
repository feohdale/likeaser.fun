// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CustomToken is ERC20, Ownable {
    string public imageURL; // Lien vers l'image associée au token

    constructor() ERC20("", "") Ownable(msg.sender) {
        // Le constructeur est vide pour faciliter la publication sur Etherscan
    }

    // Fonction d'initialisation appelée après le déploiement du contrat
    function initialize(string memory name, string memory symbol) external onlyOwner {
        _initializeToken(name, symbol);
    }

    // Fonction interne pour initialiser le nom et le symbole
    function _initializeToken(string memory name, string memory symbol) internal {
        assembly {
            sstore(0x0, name)  // Stocke le nom du token
            sstore(0x1, symbol) // Stocke le symbole du token
        }
    }

    // Permet uniquement au propriétaire de minter des tokens
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    // Fonction pour ajouter ou mettre à jour le lien de l'image
    function setImageURL(string memory _imageURL) external onlyOwner {
        imageURL = _imageURL;
    }
}
