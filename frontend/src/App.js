import "./App.css";
import { useEffect, useState } from "react";
import { ethers } from "ethers";
import contractJson from "./abi/SportsBettingHook.json";
import swapRouterJson from "./abi/PoolSwapTest.json";
const contractABI = contractJson.abi;
const swapRouterABI = swapRouterJson.abi;

// Uniswap V4 Sportsbettinghook is created with Foundry (WSL)

// 1. Start Anvil like this in WSL: anvil --host 0.0.0.0
// // Run deploy script in Foundry with: forge script script/deploy.s.sol --rpc-url http://localhost:8545
// 2. In frontend: Use const provider = new ethers.providers.JsonRpcProvider("http://localhost:8545");

// This is for read-only access (Anvil)
const readProvider = new ethers.providers.JsonRpcProvider(
  "http://127.0.0.1:8545"
);

const hookContractAddress = "0xE6Cf7dC07b8a9377Baa0604b025BA1273078C888";
const swapRouterAddress = "0x4A679253410272dd5232B3Ff7cF5dbB88f295319";
const usdcAddress = "0x7a2088a1bFc9d81c55368AE168C2C02570cB814F";
const winAddress = "0xc5a5C42992dECbae36851359345FE25997F5C42d";
const drawAddress = "0x84eA74d481Ee0A5332c457a4d796187F6Ba67fEB";
const loseAddress = "0xE6E340D132b5f46d1e472DebcD681B2aBc16e57E";

function App() {
  const [walletAddress, setWalletAddress] = useState(null);
  const [odds, setOdds] = useState({ win: "-", draw: "-", lose: "-" });
  const [usdcAmount, setUsdcAmount] = useState("");
  const [signer, setSigner] = useState(null);
  const [status, setStatus] = useState({
    open: "-",
    closed: "-",
    resolved: "-",
    startTime: "-",
    closeTime: "-",
  });
  const [winBalance, setWinBalance] = useState(null);
  const [usdcBalance, setUsdcBalance] = useState(null);
  const [drawBalance, setDrawBalance] = useState(null);
  const [loseBalance, setLoseBalance] = useState(null);

  const erc20ABI = [
    "function approve(address spender, uint256 amount) external returns (bool)",
    "function allowance(address owner, address spender) view returns (uint256)",
    "function balanceOf(address owner) view returns (uint256)",
    "function decimals() view returns (uint8)",
  ];

  // Helper function to get the signer
  const getSigner = () => {
    const provider = new ethers.providers.Web3Provider(window.ethereum);
    return provider.getSigner();
  };

  // Helper function to get the contract
  const getContract = (address, abi) => {
    const signer = getSigner();
    return new ethers.Contract(address, abi, signer);
  };

  // Helper function to fetch balances
  const fetchBalances = async (userAddress) => {
    const tokens = {
      usdc: usdcAddress,
      win: winAddress,
      draw: drawAddress,
      lose: loseAddress,
    };

    const balances = {};
    for (const [symbol, address] of Object.entries(tokens)) {
      const token = getContract(address, erc20ABI);
      const raw = await token.balanceOf(userAddress);
      balances[symbol] = ethers.utils.formatUnits(raw, 18); // assuming 18 decimals
    }

    //console.log("USDC:", balances.usdc);
    //console.log("WIN:", balances.win);
    setWinBalance(balances.win);
    setUsdcBalance(balances.usdc);
    setDrawBalance(balances.draw);
    setLoseBalance(balances.lose);
  };

  const connectWallet = async () => {
    if (!window.ethereum) return alert("Please install MetaMask");

    await window.ethereum.request({ method: "eth_requestAccounts" });
    const signer = getSigner();
    const address = await signer.getAddress();
    setWalletAddress(address);
    setSigner(signer);
    await fetchBalances(address);
  };

  const fetchMarketData = async () => {
    try {
      const contract = new ethers.Contract(
        hookContractAddress,
        contractABI,
        readProvider
      );
      const [pWin, pDraw, pLose] = await contract.getOutcomeProbabilities();
      setOdds({
        win: (1e18 / pWin).toFixed(2),
        draw: (1e18 / pDraw).toFixed(2),
        lose: (1e18 / pLose).toFixed(2),
      });

      const [open, closed, resolved, startTime, closeTime] =
        await contract.getMarketState();
      setStatus({
        open: open.toString(),
        closed: closed.toString(),
        resolved: resolved.toString(),
        startTime: new Date(startTime.toNumber() * 1000).toLocaleString(),
        closeTime: new Date(closeTime.toNumber() * 1000).toLocaleString(),
      });
    } catch (err) {
      console.error("Failed to fetch market data:", err);
    }
  };

  const openMarketWithWallet = async () => {
    try {
      const signer = getSigner();
      const contract = getContract(hookContractAddress, contractABI);
      const now = Math.floor(Date.now() / 1000);
      const in7Days = now + 7 * 24 * 60 * 60;
      const tx = await contract.openBetMarket(now, in7Days);
      await tx.wait();
      alert("✅ Market opened successfully!");
    } catch (err) {
      console.error("Failed to open market:", err);
      alert("Failed to open market: " + err.message);
    }
  };

  const closeMarketWithWallet = async () => {
    try {
      const contract = getContract(hookContractAddress, contractABI);
      const tx = await contract.closeBetMarket();
      await tx.wait();
      alert("✅ Market closed successfully!");
    } catch (err) {
      console.error("Failed to close market:", err);
      alert("Failed to close market: " + err.message);
    }
  };

  const resetMarketWithWallet = async () => {
    try {
      const contract = getContract(hookContractAddress, contractABI);
      const tx = await contract.resetMarket();
      await tx.wait();
      alert("✅ Market reset successfully!");
    } catch (err) {
      console.error("Failed to reset market:", err);
      alert("Failed to reset market: " + err.message);
    }
  };

  const resolveMarketWithWallet = async () => {
    try {
      const contract = getContract(hookContractAddress, contractABI);
      const tx = await contract.reolveMarket(0);
      await tx.wait();
      alert("✅ Market resolved successfully!");
    } catch (err) {
      console.error("Failed to resolve market:", err);
      alert("Failed to resolve market: " + err.message);
    }
  };

  const handleApprove = async (outcome) => {
    alert(`You chose to approve ${outcome} with ${usdcAmount} USDC`);
    if (!signer) return alert("Please connect wallet first");

    const usdcToken = getContract(usdcAddress, erc20ABI);
    const allowance = await usdcToken.allowance(
      await signer.getAddress(),
      swapRouterAddress
    );
    const amount = 100;

    if (allowance.gte(amount)) return console.log("Already approved");

    const tx = await usdcToken.approve(swapRouterAddress, amount);
    await tx.wait();
    console.log("Approved USDC for swapRouter");
  };

  const handleBuy = async (outcome) => {
    alert(`You chose to buy ${usdcAmount} ${outcome} with USDC`);
    if (!signer) return alert("Please connect wallet first");

    const swapRouter = getContract(swapRouterAddress, swapRouterABI);
    const userAddress = await signer.getAddress();

    // Get the correct order: in V4 ==> token0 < token1

    // 1. Determine token order
    const zeroForOneDummy =
      usdcAddress.toLowerCase() < winAddress.toLowerCase();

    // 2. Set token0 and token1 in correct order
    const token0 = zeroForOneDummy ? usdcAddress : winAddress;
    const token1 = zeroForOneDummy ? winAddress : usdcAddress;

    // 3. Construct the poolKey using token0/token1
    const poolKey = {
      currency0: token0,
      currency1: token1,
      fee: 3000,
      tickSpacing: 60,
      hooks: hookContractAddress,
    };

    const swapParams = {
      zeroForOne: zeroForOneDummy,
      amountSpecified: usdcAmount,
      sqrtPriceLimitX96: ethers.BigNumber.from("79228162514264337593543950336"),
    };

    const settings = {
      takeClaims: false,
      settleUsingBurn: false,
    };

    const hookData = ethers.utils.defaultAbiCoder.encode(
      ["address"],
      [userAddress]
    );

    const tx = await swapRouter.swap(poolKey, swapParams, settings, hookData);
    await tx.wait();
    console.log("✅ Swap successful!");

    await fetchBalances(userAddress);
  };

  const fetchOdds = async () => {
    try {
      const res = await fetch("http://localhost:3000/dortmund-odds");
      const data = await res.json();
      const match = data[0];
      const outcomes = match.bookmakers[0].markets[0].outcomes;
      const win = outcomes.find((o) => o.name === match.home_team)?.price;
      const draw = outcomes.find((o) => o.name === "Draw")?.price;
      const lose = outcomes.find((o) => o.name === match.away_team)?.price;
      setOdds({ win, draw, lose });
    } catch (err) {
      console.error("Failed to fetch odds:", err);
    }
  };

  useEffect(() => {
    fetchOdds();
    fetchMarketData();
    const interval = setInterval(fetchMarketData, 15000);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    if (walletAddress) fetchBalances(walletAddress);
  }, [walletAddress]);

  return (
    <div className="container">
      {/* Match + Odds */}
      <div className="card">
        <h1 className="title">Current Match: Dortmund vs Freiburg</h1>
        <div className="label">Odds:</div>
        <div className="odds">
          <div>
            <strong>Home Wins:</strong>
            <br />
            🏆 {odds.win}
          </div>
          <div>
            <strong>Draw:</strong>
            <br />
            🤝 {odds.draw}
          </div>
          <div>
            <strong>Away Wins:</strong>
            <br />
            💥 {odds.lose}
          </div>
        </div>

        <div className="actions">
          <button onClick={() => handleApprove("USDC")} className="btn green">
            Approve USDC
          </button>
          <button onClick={() => handleBuy("WIN")} className="btn green">
            Buy WIN
          </button>
          <button onClick={() => handleBuy("DRAW")} className="btn yellow">
            Buy DRAW
          </button>
          <button onClick={() => handleBuy("LOSE")} className="btn red">
            Buy LOSE
          </button>

          <input
            type="number"
            placeholder="Number of WIN/DRAW/LOSE to buy"
            value={usdcAmount}
            onChange={(e) => setUsdcAmount(e.target.value)}
            className="input"
          />

          {!walletAddress ? (
            <button onClick={connectWallet} className="btn purple full">
              Connect Wallet
            </button>
          ) : (
            <div className="connected">
              {walletAddress.slice(0, 6)}...{walletAddress.slice(-4)}
              <h4>Balance USDC: {usdcBalance} </h4>
              <h4>Balance WIN Tokens: {winBalance} </h4>
              <h4>Balance DRAW Tokens: {drawBalance} </h4>
              <h4>Balance LOSE Tokens: {loseBalance} </h4>
            </div>
          )}
        </div>
      </div>

      {/* Admin Controls */}
      <div className="card">
        <h2 className="subtitle">Admin Controls</h2>
        <div className="controls">
          <button onClick={openMarketWithWallet} className="btn blue">
            Open betting market
          </button>
          <button onClick={closeMarketWithWallet} className="btn blue">
            Close betting market
          </button>
          <button onClick={resetMarketWithWallet} className="btn blue">
            Reset betting market
          </button>
          <button onClick={resolveMarketWithWallet} className="btn blue">
            Resolve betting market
          </button>
        </div>
      </div>

      {/* Status Info */}
      <div className="card">
        <h2 className="subtitle">Status betting market</h2>
        <p>Bettting market is open: {String(status.open)}</p>
        <p>Bettting market is closed: {String(status.closed)}</p>
        <p>Resolved: {String(status.resolved)}</p>
        <p>Start of betting market: {status.startTime}</p>
        <p>Close of betting market: {status.closeTime}</p>
      </div>
    </div>
  );
}

export default App;
