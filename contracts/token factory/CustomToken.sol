// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CustomToken is ERC20, Ownable {
    string private _customName;
    string private _customSymbol;
    bool private initialized;
    string public imageURL; // Lien vers l'image associée au token

    constructor() ERC20("", "") Ownable(msg.sender) {}

    // Fonction d'initialisation pour définir le nom et le symbole après le déploiement
    function initialize(string memory name, string memory symbol) external {
        require(!initialized, "Token already initialized");
        _customName = name;
        _customSymbol = symbol;
        initialized = true;
    }

    // Fonctions pour récupérer le nom et le symbole personnalisés
    function name() public view override returns (string memory) {
        return _customName;
    }

    function symbol() public view override returns (string memory) {
        return _customSymbol;
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
