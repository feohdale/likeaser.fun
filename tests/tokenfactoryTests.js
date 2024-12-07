const { expect } = require("chai");

describe("TokenFactory", function () {
  let owner, user, devAddress, daoAddress, tokenFactory;

  beforeEach(async function () {
    [owner, user, devAddress, daoAddress] = await ethers.getSigners();

    const TokenFactory = await ethers.getContractFactory("TokenFactory");
    tokenFactory = await TokenFactory.connect(owner).deploy(devAddress.address, daoAddress.address);
    await tokenFactory.waitForDeployment(); // Nouvelle méthode pour attendre le déploiement
  });

  it("should create a new token and liquidity pool", async function () {
    const creationCost = ethers.parseEther("0.0002");
    const tx = await tokenFactory.connect(user).createToken("TestToken", "TTK", { value: creationCost });
    const receipt = await tx.wait();

    const totalTokens = await tokenFactory.getTotalTokensCreated();
    expect(totalTokens).to.equal(1);

    const allTokens = await tokenFactory.getAllTokens();
    const tokenInfo = allTokens[0];
    expect(tokenInfo.tokenAddress).to.be.properAddress;
    expect(tokenInfo.liquidityPoolAddress).to.be.properAddress;
  });

  it("should transfer DAO and dev fees correctly during token creation", async function () {
    const creationCost = ethers.parseUnits("0.0002", "ether");

    // Balance de l'utilisateur avant la création du token
    const initialUserBalance = await ethers.provider.getBalance(user.address);
    console.log("Initial User Balance:", ethers.formatEther(initialUserBalance), "ETH");

    // Création d'un nouveau token
    const tx = await tokenFactory.connect(user).createToken("NewTestToken", "NTT", { value: creationCost });
    await tx.wait();

    // Balance de l'utilisateur après la création du token
    const finalUserBalance = await ethers.provider.getBalance(user.address);
    console.log("Final User Balance:", ethers.formatEther(finalUserBalance), "ETH");

    // Vérifier que le solde de l'utilisateur a diminué d'au moins `creationCost`
    expect(initialUserBalance - finalUserBalance).to.be.gte(creationCost);

    // Récupérer l'adresse du nouveau token via TokenFactory
    const allTokens = await tokenFactory.getAllTokens();
    const tokenAddress = allTokens[allTokens.length - 1].tokenAddress;

    // Créer une instance du token
    const token = await ethers.getContractAt("CustomToken", tokenAddress);

    // Vérifier la balance initiale de l'adresse DAO pour le token
    const daoBalance = await token.balanceOf(daoAddress.address);
    console.log("DAO Token Balance:", daoBalance.toString());

    // Vérifier que l'adresse DAO a reçu des tokens
    expect(daoBalance).to.be.gt(0);

    // Vérifier que le solde de l'utilisateur est supérieur à 0 (il reste des ETH)
    expect(finalUserBalance).to.be.gt(0);
});




  it("should not allow duplicate token names", async function () {
    const creationCost = ethers.parseEther("0.0002");

    await tokenFactory.connect(user).createToken("TestToken", "TTK", { value: creationCost });
    await expect(
      tokenFactory.connect(user).createToken("TestToken", "TTK2", { value: creationCost })
    ).to.be.revertedWith("Token with this name already exists");
  });
  it("should allow buying tokens", async function () {
    const creationCost = ethers.parseUnits("0.0002", "ether");

    // Création d'un nouveau token
    const tx = await tokenFactory.connect(user).createToken("NewBuyToken", "NBT", { value: creationCost });
    await tx.wait();

    // Récupérer l'adresse du nouveau token
    const allTokens = await tokenFactory.getAllTokens();
    const tokenAddress = allTokens[allTokens.length - 1].tokenAddress;
    const poolAddress = allTokens[allTokens.length - 1].liquidityPoolAddress;

    // Créer des instances du token et de la pool
    const token = await ethers.getContractAt("CustomToken", tokenAddress);
    const pool = await ethers.getContractAt("LiquidityPool", poolAddress);

    // Balance de l'utilisateur avant achat
    const initialUserTokenBalance = await token.balanceOf(user.address);
    console.log("Initial User Token Balance:", initialUserTokenBalance.toString());

    const amountToBuy = ethers.parseUnits("0.1", "ether");

    // Achat de tokens
    const buyTx = await pool.connect(user).buyToken({ value: amountToBuy });
    await buyTx.wait();

    // Balance de l'utilisateur après achat
    const finalUserTokenBalance = await token.balanceOf(user.address);
    console.log("Final User Token Balance:", finalUserTokenBalance.toString());

    // Vérification de l'augmentation des tokens de l'utilisateur
    expect(finalUserTokenBalance).to.be.gt(initialUserTokenBalance);
});

it("should allow selling tokens", async function () {
    const creationCost = ethers.parseUnits("0.0002", "ether");

    // Création d'un nouveau token
    const tx = await tokenFactory.connect(user).createToken("NewSellToken", "NST", { value: creationCost });
    await tx.wait();

    // Récupérer l'adresse du nouveau token
    const allTokens = await tokenFactory.getAllTokens();
    const tokenAddress = allTokens[allTokens.length - 1].tokenAddress;
    const poolAddress = allTokens[allTokens.length - 1].liquidityPoolAddress;

    // Créer des instances du token et de la pool
    const token = await ethers.getContractAt("CustomToken", tokenAddress);
    const pool = await ethers.getContractAt("LiquidityPool", poolAddress);

    // Achat initial de tokens
    const amountToBuy = ethers.parseUnits("0.1", "ether");
    const buyTx = await pool.connect(user).buyToken({ value: amountToBuy });
    await buyTx.wait();

    // Balance initiale de l'utilisateur en tokens et en ETH
    const initialUserTokenBalance = await token.balanceOf(user.address);
    const initialUserEtherBalance = await ethers.provider.getBalance(user.address);
    console.log("Initial User Token Balance:", initialUserTokenBalance.toString());
    console.log("Initial User Ether Balance:", ethers.formatEther(initialUserEtherBalance), "ETH");

    // Appel de `approve` pour permettre la vente
    const amountToSell = initialUserTokenBalance / 2n; // Divise la balance par 2 (bigint)
    const approveTx = await token.connect(user).approve(poolAddress, amountToSell);
    await approveTx.wait();

    // Vente de tokens
    const sellTx = await pool.connect(user).sellToken(amountToSell);
    await sellTx.wait();

    // Balance finale de l'utilisateur en tokens et en ETH
    const finalUserTokenBalance = await token.balanceOf(user.address);
    const finalUserEtherBalance = await ethers.provider.getBalance(user.address);
    console.log("Final User Token Balance:", finalUserTokenBalance.toString());
    console.log("Final User Ether Balance:", ethers.formatEther(finalUserEtherBalance), "ETH");

    // Vérification de la réduction des tokens de l'utilisateur
    expect(finalUserTokenBalance).to.be.lt(initialUserTokenBalance);

    // Vérification de l'augmentation du solde ETH de l'utilisateur
    expect(finalUserEtherBalance).to.be.gt(initialUserEtherBalance);
});
it("should validate bonding curve checkpoints up to 0.2 ETH", async function () {
  const creationCost = ethers.parseUnits("0.0002", "ether");

  // Création d'un nouveau token
  const tx = await tokenFactory.connect(user).createToken("BondingToken", "BND", { value: creationCost });
  await tx.wait();

  // Récupérer l'adresse du nouveau token et de la pool
  const allTokens = await tokenFactory.getAllTokens();
  const tokenAddress = allTokens[allTokens.length - 1].tokenAddress;
  const poolAddress = allTokens[allTokens.length - 1].liquidityPoolAddress;

  // Créer des instances du token et de la pool
  const token = await ethers.getContractAt("CustomToken", tokenAddress);
  const pool = await ethers.getContractAt("LiquidityPool", poolAddress);

  // Initial reserves
  let [tokenReserve, etherReserve] = await pool.getReserve();
  console.log("Initial Reserves - Token:", tokenReserve.toString(), "Ether:", ethers.formatEther(etherReserve));

  // Vérifier la bonding curve jusqu'à 0.2 ETH
  const step = ethers.parseUnits("0.05", "ether"); // Montant d'ETH par étape
  const maxEth = ethers.parseUnits("0.2", "ether");
  let currentEth = ethers.parseUnits("0.05", "ether");

  while (currentEth <= maxEth) {
      console.log(`\nTesting with ${ethers.formatEther(currentEth)} ETH`);
      
      // Balance utilisateur avant achat
      const initialUserTokenBalance = await token.balanceOf(user.address);
      
      // Acheter des tokens
      const buyTx = await pool.connect(user).buyToken({ value: currentEth });
      await buyTx.wait();

      // Balance utilisateur après achat
      const finalUserTokenBalance = await token.balanceOf(user.address);
      const tokensBought = finalUserTokenBalance - initialUserTokenBalance;
      
      // Réserves après achat
      [tokenReserve, etherReserve] = await pool.getReserve();

      console.log("Tokens Bought:", tokensBought.toString());
      console.log("Updated Reserves - Token:", tokenReserve.toString(), "Ether:", ethers.formatEther(etherReserve));

      // Incrémenter pour le prochain test
      currentEth += step;
  }
});


});
