import "./App.css";
import { useEffect, useState } from "react";
import { ethers } from "ethers";

function App() {
  const [walletAddress, setWalletAddress] = useState(null);
  const [odds, setOdds] = useState({ win: "-", draw: "-", lose: "-" });
  const [usdcAmount, setUsdcAmount] = useState("");

  async function connectWallet() {
    if (window.ethereum) {
      const accounts = await window.ethereum.request({
        method: "eth_requestAccounts",
      });
      setWalletAddress(accounts[0]);
    } else {
      alert("Please install MetaMask");
    }
  }

  async function fetchOdds() {
    try {
      const res = await fetch("http://localhost:3000/dortmund-odds");
      const data = await res.json();

      const match = data[0]; // Assume first match is Dortmund vs Freiburg
      const outcomes = match.bookmakers[0].markets[0].outcomes;
      const win = outcomes.find((o) => o.name === match.home_team)?.price;
      const draw = outcomes.find((o) => o.name === "Draw")?.price;
      const lose = outcomes.find((o) => o.name === match.away_team)?.price;

      setOdds({ win, draw, lose });
    } catch (err) {
      console.error("Failed to fetch odds:", err);
    }
  }

  function handleBuy(outcome) {
    alert(`You chose to buy ${outcome} with ${usdcAmount} USDC`);
    // You can hook this up to your smart contract logic
  }

  useEffect(() => {
    fetchOdds();
  }, []);

  return (
    <div className="p-4 max-w-xl mx-auto">
      <h1 className="text-2xl font-bold mb-4">Dortmund vs Freiburg</h1>

      <div className="mb-2">Odds:</div>
      <div className="grid grid-cols-3 gap-2 mb-4">
        <div>🏆 WIN: {odds.win}</div>
        <div>🤝 DRAW: {odds.draw}</div>
        <div>💥 LOSE: {odds.lose}</div>
      </div>

      <input
        type="number"
        placeholder="Enter USDC amount"
        value={usdcAmount}
        onChange={(e) => setUsdcAmount(e.target.value)}
        className="w-full p-2 border rounded mb-4"
      />

      {!walletAddress ? (
        <button
          onClick={connectWallet}
          className="bg-blue-600 text-white px-4 py-2 rounded w-full mb-4"
        >
          Connect Wallet
        </button>
      ) : (
        <div className="text-green-600 mb-4">
          Connected: {walletAddress.slice(0, 6)}...{walletAddress.slice(-4)}
        </div>
      )}

      <div className="grid grid-cols-1 gap-2">
        <button
          onClick={() => handleBuy("WIN")}
          className="bg-green-600 text-white p-2 rounded"
        >
          Buy WIN
        </button>
        <button
          onClick={() => handleBuy("DRAW")}
          className="bg-yellow-500 text-white p-2 rounded"
        >
          Buy DRAW
        </button>
        <button
          onClick={() => handleBuy("LOSE")}
          className="bg-red-600 text-white p-2 rounded"
        >
          Buy LOSE
        </button>
      </div>
    </div>
  );
}

export default App;
