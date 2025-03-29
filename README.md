# Whitepaper: Decentralized Sports Betting Hook on Uniswap V4

⚠️ Note: This implementation is not yet production-ready — oracle integration for automated match resolution is still in progress.

## Abstract

This whitepaper introduces a decentralized sports betting mechanism integrated as a custom Uniswap V4 Hook, utilizing the Logarithmic Market Scoring Rule (LMSR) for dynamic probability-weighted pricing. The protocol enables users to bet on sports outcomes using USDC, routing liquidity into dedicated pools: USDC/HOME_WIN, USDC/HOME_LOSE, and USDC/HOME_DRAW.

## 1. Introduction

Traditional sports betting platforms rely on centralized intermediaries, leading to issues such as manipulated odds, lack of transparency, and counterparty risks. This proposal leverages Uniswap V4 Hooks to create an automated and decentralized sports betting mechanism that maintains fair pricing through LMSR.

PM: Use external oracle services to fetch initial probabilities and finalize match outcomes. This removes reliance on centralized bookmakers while enabling secure, automated resolution.

## 2. System Architecture

### 2.1. Components

- Uniswap V4 Hook: A smart contract that dynamically adjusts bet pricing and deposits funds into 3 LPs: USDC/HOME_WIN, USDC/HOME_LOSE, and USDC/HOME_DRAW.
- LMSR-Based Market Maker: Ensures that the price of each bet reflects its implied probability.
- Automated Liquidity Routing: Redirects user deposits into the LP and withdraws when payouts are required.

### 2.2. Workflow

- Users place bets by swapping USDC for outcome shares (e.g., WIN, DRAW, LOSE).
- LMSR updates pricing dynamically, ensuring probability-adjusted odds.
- Upon event resolution, prizes are paid out to the winners.

### 3. LMSR Pricing Mechanism

The Logarithmic Market Scoring Rule (LMSR) defines a cost function:

#### $C(q) = b · log(\sum e^{q_i / b} ) $

Where:

$C(q)=$ total cost to buy outcome shares,

$b=$ liquidity parameter (higher reduces price impact),

$q_i=$ quantity of shares held for outcome .

The price for each outcome is:

### $P_i = \frac{e^{q_i / b}}{\sum e^{q_j / b}} $

This ensures that probabilities remain dynamic, updating as users place bets.

### 4. Uniswap V4 Hook Integration: beforeSwap()

Prior to swap execution, LMSR pricing is applied to modify the bet price.

### 5. Advantages of the System

- ✅ Decentralized & Transparent – Eliminates centralized sportsbooks.
- ✅ Fair & Dynamic Pricing – LMSR ensures odds reflect probability.
- ✅ Automated Payouts – Smart contracts handle settlement trustlessly.

### 6. Conclusion

This Uniswap V4 Hook establishes a trustless and transparent framework for decentralized sports betting. It leverages LMSR to provide fair, real-time pricing while managing liquidity across outcome-specific pools. The design simplifies bet execution and settlement without relying on centralized bookmakers. Future improvements may include support for additional sports markets, multi-token collateral, and enhanced incentives for active participation.
