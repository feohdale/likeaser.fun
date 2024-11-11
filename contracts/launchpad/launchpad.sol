// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Launchpad is Ownable {
    IERC20 public token; // The ERC20 token to be distributed
    uint256 public  PRICE_PER_TOKEN = 0.0000016 ether;
    uint256 public constant DURATION = 4 days; 
    uint256 public constant MAX_TOKENS = 1_000_000; // token limit
    uint256 public  maxAmountPerWallet = 0.083 * 1 ether;
    uint256 public launchpadEndTime;
    uint256 public launchpadStartTime;
   // bool public launchpadFinished;
   //  bool public launchpadStarted; 

    address public taxCollector;
    address[] public allContributors; // List of contributors
    mapping(address => uint256) public contributions; // Contribution in RBTC by user 
    mapping(address => uint256) public contributionsInTokens; // amount in tokens for the user
    mapping(address => uint256) public remainingTokenAvailablePerWallet; // number of tokens remaining for the user
    uint256 public totalContributions; // total contributions in RBTC
    uint256 public totalTokensSold; // total token sold

    constructor(IERC20 _token) Ownable(msg.sender) {
        token = _token;
        launchpadEndTime = block.timestamp + DURATION;
    }

    modifier onlyDuringLaunchpad() {
        require(block.timestamp <= launchpadEndTime, "Launchpad has ended");
        require(block.timestamp >= launchpadStartTime,"Launchpad is not started");
        _;
    }

    modifier onlyAfterLaunchpad() {
        require(
            block.timestamp > launchpadEndTime,
            "Launchpad not finished yet"
        );
        _;
    }

 function contribute() external payable onlyDuringLaunchpad {
    require(msg.value > 0, "You need to send ETH");
    uint256 tokensToBuy = msg.value  / PRICE_PER_TOKEN;

    // doesn't exceed the max token available
    require(
        totalTokensSold + tokensToBuy <= MAX_TOKENS,
        "Exceeds maximum token limit"
    );

    if (contributions[msg.sender] == 0) {
        allContributors.push(msg.sender);
        remainingTokenAvailablePerWallet[msg.sender] = maxAmountPerWallet;
    }

    // Convert tokens b
    uint256 remainingTokensForWallet = remainingTokenAvailablePerWallet[msg.sender] / PRICE_PER_TOKEN;
    require(tokensToBuy <= remainingTokensForWallet, "Exceeds the max token per wallet");

    contributions[msg.sender] += msg.value;
    contributionsInTokens[msg.sender] += tokensToBuy;
    remainingTokenAvailablePerWallet[msg.sender] -= tokensToBuy * PRICE_PER_TOKEN; // Réduction en fonction de l'ETH équivalent
    totalContributions += msg.value;
    totalTokensSold += tokensToBuy;
}


function refundAll() external onlyOwner {
    // Fermeture immédiate du launchpad
    launchpadEndTime = block.timestamp;

    // Procéder au remboursement uniquement s'il y a des contributions
    if (totalContributions > 0) {
        // Boucle pour rembourser chaque contributeur
        for (uint256 i = 0; i < allContributors.length; i++) {
            address contributor = allContributors[i];
            uint256 contribution = contributions[contributor];
            if (contribution > 0) {
                uint256 tokensToRefund = contribution / PRICE_PER_TOKEN;
                contributions[contributor] = 0;
                payable(contributor).transfer(contribution);
                totalTokensSold -= tokensToRefund;
            }
        }
        totalContributions = 0;
    }
}



    function distributeTokens() external onlyOwner onlyAfterLaunchpad {
        //require(!launchpadFinished, "Tokens already distributed");
        //launchpadFinished = true;

        for (uint256 i = 0; i < allContributors.length; i++) {
            address contributor = allContributors[i];
            uint256 contribution = contributions[contributor];
            if (contribution > 0) {
                uint256 amountToDistribute = contribution / PRICE_PER_TOKEN;
                token.transfer(contributor, amountToDistribute);
            }
        }
    }

    function withdrawFunds() external onlyOwner onlyAfterLaunchpad {
        //require(launchpadFinished, "Launchpad is not finished");
        require(taxCollector != address(0), "Tax collector address not set");
        payable(taxCollector).transfer(address(this).balance); // Envoie des fonds à l'adresse taxCollector
    }

    // Fonction pour mettre à jour l'adresse taxCollector
    function setTaxCollector(address _taxCollector) external onlyOwner {
        taxCollector = _taxCollector;
    }

    function getAmountPerWallet(address _wallet) public view returns (uint256) {
        return contributions[_wallet];
    }

    function setMaxAmountPerWallet(uint value) public onlyOwner {
        maxAmountPerWallet = value; 
    }
    function  setPrice(uint value) public onlyOwner {

        PRICE_PER_TOKEN = value; 
        
    }
    function setStartLaunchpadTime(uint256 date) public onlyOwner {
    require(launchpadStartTime == 0 || launchpadStartTime > block.timestamp, "launchpad already started");
    launchpadStartTime = date;
    launchpadEndTime = date + DURATION;
}

}
