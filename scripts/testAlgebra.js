const { ethers } = require("ethers");

// Configuration
const provider = new ethers.providers.JsonRpcProvider("https://public-node.testnet.rsk.co");
const privateKey = "8f3092aaeaa64a08681b614cbac6641642dee6ca02bc7114ee009a2c6fbc0d32"; // Remplacez par votre clé privée
const wallet = new ethers.Wallet(privateKey, provider);

// Adresse du contrat et ABI
const contractAddress = "0xCD329e33DD3713384d7042BDD2417a6D7d3C6aEC"; // Remplacez par l'adresse du contrat
const abi = [
  "event Debug(string message)",
  "event TokenAddresses(address tokenA, address tokenB)",
  "event PoolCreated(address pool)",
  "event LiquidityAdded(uint128 amountA, uint128 amountB)",
  "function createAndInitializePool(uint160 sqrtPriceX96) external",
  "function createTokens() external",
  "function addLiquidity(int24 tickLower, int24 tickUpper, uint128 amountA, uint128 amountB) external"
];

const contract = new ethers.Contract(contractAddress, abi, wallet);

// Fonction principale
async function main() {
  console.log("Listening to contract events...");

  // Écouter les événements
  contract.on("Debug", (message) => {
    console.log(`Debug Event: ${message}`);
  });

  contract.on("TokenAddresses", (tokenA, tokenB) => {
    console.log(`Token Addresses: TokenA=${tokenA}, TokenB=${tokenB}`);
  });

  contract.on("PoolCreated", (pool) => {
    console.log(`Pool Created at Address: ${pool}`);
  });

  contract.on("LiquidityAdded", (amountA, amountB) => {
    console.log(`Liquidity Added: AmountA=${amountA}, AmountB=${amountB}`);
  });

  // Exemple d'appels au contrat
  try {
    console.log("Creating tokens...");
    const txCreateTokens = await contract.createTokens();
    await txCreateTokens.wait();
    console.log("Tokens created successfully.");

    console.log("Creating and initializing pool...");
    const sqrtPriceX96 = ethers.BigNumber.from("79228162514264337593543950336"); // Pour un ratio 1:1
    const txCreatePool = await contract.createAndInitializePool(sqrtPriceX96);
    await txCreatePool.wait();
    console.log("Pool created and initialized.");

    console.log("Adding liquidity...");
    const tickLower = -887220;
    const tickUpper = 887220;
    const amountA = ethers.utils.parseUnits("100", 18); // 100 unités de Token A
    const amountB = ethers.utils.parseUnits("100", 18); // 100 unités de Token B
    const txAddLiquidity = await contract.addLiquidity(tickLower, tickUpper, amountA, amountB);
    await txAddLiquidity.wait();
    console.log("Liquidity added successfully.");
  } catch (error) {
    console.error("Error interacting with the contract:", error);
  }
}

// Exécuter la fonction principale
main().catch(console.error);
