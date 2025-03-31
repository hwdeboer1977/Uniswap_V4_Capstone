// server.js
const express = require("express");
const axios = require("axios");
require("dotenv").config();

const app = express();
const port = 3000;

app.get("/dortmund-odds", async (req, res) => {
  console.log("✅ Received request at /dortmund-odds");
  try {
    const apiKey = process.env.ODDS_API_KEY;
    const sportKey = "soccer_germany_bundesliga";
    const regions = "eu";
    const markets = "h2h";
    const oddsFormat = "decimal";

    const url = `https://api.the-odds-api.com/v4/sports/${sportKey}/odds`;

    const response = await axios.get(url, {
      params: {
        apiKey,
        regions,
        markets,
        oddsFormat,
      },
    });

    const dortmundMatches = response.data.filter(
      (match) =>
        match.home_team === "Borussia Dortmund" ||
        match.away_team === "Borussia Dortmund"
    );

    res.json(dortmundMatches);
  } catch (error) {
    console.error("Error fetching odds:", error);
    res.status(500).json({ error: "Failed to fetch odds" });
  }
});

app.listen(port, () => {
  console.log(`Odds API server running at http://localhost:${port}`);
});
