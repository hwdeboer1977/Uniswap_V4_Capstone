// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { UD60x18, ud } from "prb-math/UD60x18.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import "forge-std/console.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";


contract SportsBettingHook is BaseHook {
    IERC20 public usdc;
    IERC20 public tokenHomeWin;
    address public admin;
    uint256 public liquidityParameter = 500e18;

    using StateLibrary for IPoolManager;
    PoolId poolId;

    // Temporary as public state variables
    uint256 public initialCost;
    uint256 public newLiquidity;
    uint256 public newCost;
    uint256 public betCost;
    uint256 public betAmount;

    // Address protocolOwner (only one who can add/remove liquidity)
    address public protocolOwner;
    uint256 public matchStartTime; // starting time match

    // Setting for betting market
    bool public betMarketOpen;
    bool public betMarketClosed;
    bool public resolved;
    bool public outcomeIsWIN;
    bool public outcomeIsLOSE;
    bool public outcomeIsDRAW;
    uint256 public startTime;
    uint256 public endTime;

    // State variables to track pool balances
    uint256 public usdcInWinPool = 0;
    uint256 public homeWinInWinPool = 0;
    uint256 public homeWinPrice = 0;

    IPositionManager posm;

    enum Outcome { LIV_WINS, LIV_DRAW, LIV_LOSE }

    mapping(Outcome => uint256) public liquidity;
    mapping(Outcome => mapping(address => uint256)) public userBets;
    Outcome public finalOutcome;
    bool public matchSettled;
    uint256 public totalLiquidity;

    event BetPlaced(address indexed user, Outcome outcome, uint256 amount, uint256 cost);
    event MatchSettled(Outcome winningOutcome);
    event PayoutClaimed(address user, uint256 userStake, uint256 totalPool, uint256 contractBalance, uint256 reward);
    event WinningsClaimed(address user, uint256 userPrice);

    constructor(
        IPoolManager _manager,
        address _protocolOwner,
        uint256 _matchStartTime,
        IPositionManager _posm,
        address _usdc,
        address _tokenHomeWin
    ) BaseHook(_manager)  {
        protocolOwner = _protocolOwner;
        matchStartTime=_matchStartTime;
        posm = _posm;
        usdc = IERC20(_usdc);
        tokenHomeWin = IERC20(_tokenHomeWin);
        liquidity[Outcome.LIV_WINS] = 0;
        liquidity[Outcome.LIV_DRAW] = 0;
        liquidity[Outcome.LIV_LOSE] = 0;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeSwap: true,
            afterSwap: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeInitialize: false,
            afterInitialize: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }


    // Function to process the bets
    function placeBet(Outcome _outcome, uint256 _amount) external {
        require(!matchSettled, "Betting is closed");
        require(_amount <= 2000e18, "Bet too large for liquidity");

        // Calculate cost of bet = newCost - Initial Cost
        // Use state variables for now
        betAmount = _amount;
        initialCost = getMarketCost();
        newLiquidity = liquidity[_outcome] + _amount;
        liquidity[_outcome] = newLiquidity;

        newCost = getMarketCost();
        betCost = newCost - initialCost;

        // require(usdc.transferFrom(msg.sender, address(this), betCost), "USDC transfer failed");
        userBets[_outcome][msg.sender] += _amount;

        emit BetPlaced(msg.sender, _outcome, _amount, betCost);


    }

    
    function claimWinnings() external {
        
    
        require(block.timestamp >= matchStartTime, "Cannot claim prices before match ends");
        
        // Determine the winning outcome
        Outcome winningOutcome;

        if (outcomeIsWIN) {
            winningOutcome = Outcome.LIV_WINS;
        } else if (outcomeIsLOSE) {
            winningOutcome = Outcome.LIV_LOSE;
        } else if (outcomeIsDRAW) {
            winningOutcome = Outcome.LIV_DRAW;
        } else {
            revert("No outcome set yet");
        }
            
        uint256 userBet = userBets[winningOutcome][msg.sender];
        require(userBet > 0, "No winnings to claim");

        // Calculate total winnings pool
        uint256 totalWinningBets = liquidity[winningOutcome];

        // Calculate user share based on their bet proportion
        uint256 prizePool = usdc.balanceOf(address(this));
        uint256 userPrice = (userBet * prizePool) / totalWinningBets;
        console.log("user Price: ", userPrice);

        // Prevent reentrancy
        userBets[winningOutcome][msg.sender] = 0;

        // Transfer winnings
        require(usdc.transfer(msg.sender, userPrice), "USDC transfer failed");

        emit WinningsClaimed(msg.sender, userPrice);
    }


    function _beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
   
   
        // 1. Get current pool balances from AMM LP
        uint256 amountX = tokenHomeWin.balanceOf(address(poolManager));
        console.log("amount HomeWin:", amountX);
        uint256 amountY = usdc.balanceOf(address(poolManager));
        console.log("amount USDC:", amountY);

        // 2. Get the amount that will be swapped
        uint256 dx = uint256(SignedMath.abs(params.amountSpecified));
        console.log("Incoming buy for WIN (amountIn):", dx);

        
        
        // 3.  Get the cost to swap in AMM
        uint256 constantK = amountY * amountX;
        // (X - dX) * (Y + dY) = k
        uint256 dy =  (constantK/(amountX - dx)) - amountY;
        console.log("How many USDC Tokens: ", dy);
          
        
        // 4. Get the cost from LMSR
        console.log("Current price HomeWin token in AMM pool:", betCost);

        // 5. Determine fee to equate price AMM and price LMSR
        
           
            uint256 fee = 0;
             // Scenario 1: Price AMM > Price LMSR
            if (betCost<dx) {
                fee = 1e18 - betCost * 1e18 / dx; // fee as 1e18

            } else if (betCost>dx) {  // Scenario 2: Price AMM < Price LMSR
                fee = betCost * 1e18 / dx - 1e18;
            }
            console.log("Current fee:", fee);
           

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }


    function _beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4) {
        
        // // Log
        // console.log("Sender:", sender); // this is address modifyLiquidityRouter
        // console.log("Protocol Owner:", protocolOwner);

        // // Ensure only the protocol can add liquidity
        // //require(sender == protocolOwner, "Only the protocol can provide liquidity");

        // // Ensure the match is still open (betting period is active)
        // console.log("Block Timestamp:", block.timestamp);
        // console.log("matchStartTime:", matchStartTime);
        // require(block.timestamp < matchStartTime, "Cannot add liquidity after match starts");

        return BaseHook.beforeAddLiquidity.selector;
    }
    

    function _beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4) {
        
        // // Log
        // console.log("Sender:", sender); // this is address modifyLiquidityRouter
        // console.log("Protocol Owner:", protocolOwner);

        // // Ensure only the protocol can add liquidity
        // //require(sender == protocolOwner, "Only the protocol can provide liquidity");

        // // Ensure the match is still open (betting period is active)
        // console.log("Block Timestamp:", block.timestamp);
        // console.log("matchStartTime:", matchStartTime);
        // require(block.timestamp >= matchStartTime, "Cannot remove liquidity before match ends");

        return BaseHook.beforeRemoveLiquidity.selector;
    }


    // Get the market cost of a bet 
    function getMarketCost() public view returns (uint256) {
        uint256 expSum = this.expScaled(liquidity[Outcome.LIV_WINS]) +
                        this.expScaled(liquidity[Outcome.LIV_DRAW]) +
                        this.expScaled(liquidity[Outcome.LIV_LOSE]);

        // The cost of a bet increases exponentially as the bet size increases.

        // Use PRBMath for ln(expSum) directly
        UD60x18 fixedX = ud(expSum);  // Scale x correctly to 18 decimals
     
        uint256 lnExpSum = fixedX.ln().unwrap();
       
        // Return the market cost
        return (liquidityParameter * lnExpSum) / 1e18; // Final scaling
        
    }

    // Function for exponent
    function expScaled(uint256 x) public view returns (uint256) {
        //require(x <= 133e18, "Input too large for exp()");
        
        // Convert x to fixed-point (18 decimals)
        UD60x18 fixedX = ud((x * 1e18) / liquidityParameter);  
        
        return fixedX.exp().unwrap(); // Compute e^x correctly
    }

    /// Sets the betting market as open
    function openBetMarket(uint256 _startTime, uint256 _endTime) external  {
        require(!betMarketOpen, "Market already open");
        require(_startTime < _endTime, "Invalid time range");
        
        betMarketOpen = true;
        betMarketClosed = false;
        resolved = false;
        startTime = _startTime;
        endTime = _endTime;
    }

    function closeBetMarket() external {
        require(betMarketOpen, "Market is not open");
        require(block.timestamp >= startTime, "Cannot close before start");

        betMarketOpen = false;
        betMarketClosed = true;
    }

    /// Resolves the betting market with an outcome
    function resolveMarket(uint8 outcome) external  {
        require(betMarketClosed, "Market must be closed first");
        require(!resolved, "Market already resolved");

        resolved = true;

        if (outcome == 1) {
            outcomeIsWIN = true;
        } else if (outcome == 2) {
            outcomeIsLOSE = true;
        } else if (outcome == 3) {
            outcomeIsDRAW = true;
        } else {
            revert("Invalid outcome");
        }
    }

    /// Resets the market for a new match
    function resetMarket() external  {
        require(resolved, "Market must be resolved first");

        betMarketOpen = false;
        betMarketClosed = false;
        resolved = false;
        outcomeIsWIN = false;
        outcomeIsLOSE = false;
        outcomeIsDRAW = false;
        startTime = 0;
        endTime = 0;
    }

    /// Gets the current state of the betting market
    function getMarketState() external view returns (bool, bool, bool, uint256, uint256) {
        return (betMarketOpen, betMarketClosed, resolved, startTime, endTime);
    }

    function getAMMPrice(PoolKey memory key) internal view returns (uint256 price) {
        PoolId id = key.toId(); // Convert PoolKey to PoolId first

        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(id);

        uint256 numerator = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        uint256 denominator = 1 << 192;

        // Assume token0 = USDC (6 decimals), token1 = WIN (18 decimals)
        // So: 10^(6 - 18) = 1e-12 → Multiply by 1e12
        price = (numerator * 1e12) / denominator;
    }




}