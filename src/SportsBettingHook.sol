// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Importing necessary Uniswap V4 and utility modules
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import { UD60x18, ud } from "prb-math/UD60x18.sol";
import "forge-std/console.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";

// Implements LMSR (Logarithmic Market Scoring Rule) for pricing bets
// Inspired by the Constant Sum Market Maker (CSMM) example by Atrium Academy
// https://github.com/haardikk21/csmm-noop-hook/tree/main

contract SportsBettingHook is BaseHook {
    using CurrencySettler for Currency;
    using CurrencyLibrary for Currency;

    uint256 public liquidityParameter = 500e18;
    enum Outcome { HOME_WINS, HOME_DRAW, HOME_LOSE }

     // Mapping from pool ID to associated betting outcome
    mapping(bytes32 => Outcome) public poolToOutcome;

     // Liquidity held for each outcome
    mapping(Outcome => uint256) public liquidity;

    // Tracks each user's bets per outcome
    mapping(Outcome => mapping(address => uint256)) public userBets;


    // Market state variables
    bool public betMarketOpen;
    bool public betMarketClosed;
    bool public resolved;
    bool public outcomeIsWIN;
    bool public outcomeIsLOSE;
    bool public outcomeIsDRAW;
    uint256 public startTime;
    uint256 public endTime;
    bool public matchSettled;

    // Temporary public state variables used during swap logic
    // Can be replaced in production (NOT gas efficient) 
    uint256 public initialCost;
    uint256 public newLiquidity;
    uint256 public newCost;
    uint256 public betCost;
    uint256 public betAmount;


    // Events for logging key contract activity
    event BetPlaced(address indexed user, Outcome outcome, uint256 amount, uint256 cost);
    event MatchSettled(Outcome winningOutcome);
    event PayoutClaimed(address user, uint256 userStake, uint256 totalPool, uint256 contractBalance, uint256 reward);
    event WinningsClaimed(address user, uint256 userPrice);

    error AddLiquidityThroughHook();

    

    struct CallbackData {
        uint256 amountEach;
        Currency currency0;
        Currency currency1;
        address sender;
    }



    constructor(IPoolManager poolManager) BaseHook(poolManager) {
            liquidity[Outcome.HOME_WINS] = 0;
            liquidity[Outcome.HOME_DRAW] = 0;
            liquidity[Outcome.HOME_LOSE] = 0;
    }

     // Define the permissions for this hook
    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: true, // Don't allow adding liquidity normally
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true, // Override how swaps are done
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: true, // Allow beforeSwap to return a custom delta
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    // Prevent users from adding liquidity through default PM flow
    function _beforeAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) internal pure override returns (bytes4) {
        revert AddLiquidityThroughHook();
    }

    // Custom function to add liquidity using `unlock` mechanism
    function addLiquidity(PoolKey calldata key, uint256 amountEach) external {
        poolManager.unlock(
            abi.encode(
                CallbackData(
                    amountEach,
                    key.currency0,
                    key.currency1,
                    msg.sender
                )
            )
        );
    }


     // Callback executed during poolManager.unlock()
    function unlockCallback(
        bytes calldata data
    ) external onlyPoolManager returns (bytes memory) {
        CallbackData memory callbackData = abi.decode(data, (CallbackData));

        // Settle `amountEach` of each currency from the sender
        // i.e. Create a debit of `amountEach` of each currency with the Pool Manager
        callbackData.currency0.settle(
            poolManager,
            callbackData.sender,
            callbackData.amountEach,
            false // `burn` = `false` i.e. we're actually transferring tokens, not burning ERC-6909 Claim Tokens
        );
        callbackData.currency1.settle(
            poolManager,
            callbackData.sender,
            callbackData.amountEach,
            false
        );

        // Since we didn't go through the regular "modify liquidity" flow,
        // the PM just has a debit of `amountEach` of each currency from us
        // We can, in exchange, get back ERC-6909 claim tokens for `amountEach` of each currency
        // to create a credit of `amountEach` of each currency to us
        // that balances out the debit

        callbackData.currency0.take(
            poolManager,
            address(this),
            callbackData.amountEach,
            true // true = mint claim tokens for the hook, equivalent to money we just deposited to the PM
        );
        callbackData.currency1.take(
            poolManager,
            address(this),
            callbackData.amountEach,
            true
        );

        return "";
    }


    // Custom swap handler using LMSR pricing logic
    function _beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata data
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        address user = abi.decode(data, (address));    // Store the address of the users who swap and place bets
       
  
    //     BalanceDelta is a packed value of (currency0Amount, currency1Amount)

    //     Specified Currency => The currency in which the user is specifying the amount they're swapping for
    //     Unspecified Currency => The other currency

    //     For example, in an ETH/USDC pool, there are 4 possible swap cases:

    //     1. ETH for USDC with Exact Input for Output (amountSpecified = negative value representing ETH)
    //     2. ETH for USDC with Exact Output for Input (amountSpecified = positive value representing USDC)
    //     3. USDC for ETH with Exact Input for Output (amountSpecified = negative value representing USDC)
    //     4. USDC for ETH with Exact Output for Input (amountSpecified = positive value representing ETH)

    //     In Case (1):
    //         -> the user is specifying their swap amount in terms of ETH, so the specifiedCurrency is ETH
    //         -> the unspecifiedCurrency is USDC

    //     In Case (2):
    //         -> the user is specifying their swap amount in terms of USDC, so the specifiedCurrency is USDC
    //         -> the unspecifiedCurrency is ETH

    //     In Case (3):
    //         -> the user is specifying their swap amount in terms of USDC, so the specifiedCurrency is USDC
    //         -> the unspecifiedCurrency is ETH

    //     In Case (4):
    //         -> the user is specifying their swap amount in terms of ETH, so the specifiedCurrency is ETH
    //         -> the unspecifiedCurrency is USDC
    
    //     -------
        
    //     Assume zeroForOne = true (without loss of generality)
    //     Assume abs(amountSpecified) = 100

    //     For an exact input swap where amountSpecified is negative (-100)
    //         -> specified token = token0
    //         -> unspecified token = token1
    //         -> we set deltaSpecified = -(-100) = 100
    //         -> we set deltaUnspecified = -100
    //         -> i.e. hook is owed 100 specified token (token0) by PM (that comes from the user)
    //         -> and hook owes 100 unspecified token (token1) to PM (to go to the user)
    
    //     For an exact output swap where amountSpecified is positive (100)
    //         -> specified token = token1
    //         -> unspecified token = token0
    //         -> we set deltaSpecified = -100
    //         -> we set deltaUnspecified = 100
    //         -> i.e. hook owes 100 specified token (token1) to PM (to go to the user)
    //         -> and hook is owed 100 unspecified token (token0) by PM (that comes from the user)

    //     In either case, we can design BeforeSwapDelta as (-params.amountSpecified, params.amountSpecified)
    
    // */

    

        // We're handling Exact Output for now (amountSpecified > 0)
        require(params.amountSpecified > 0, "Only Exact Output supported");


        // Call the function placeBet to determine the cost of the bet (in USDC): LMSR
        // Derive outcome for this pool and calculate bet cost
        Outcome outcome = poolToOutcome[getPoolId(key)];
        placeBet(outcome, uint256(params.amountSpecified), user);
        console.log("Cost of the bet: ", betCost/1e18);

       
        // Custom pricing example: user wants 200 WIN, pays 400 USDC
        // So:
        // - specifiedCurrency (WIN): we owe -200
        // - unspecifiedCurrency (USDC): we are owed +400

        int128 specifiedDelta = int128(-params.amountSpecified);              // -200 WIN
        int128 unspecifiedDelta = int128(int256(betCost)); // LMSR-computed cost

        //console.log("specifiedDelta:", specifiedDelta);
        //console.log("unspecifiedDelta:", unspecifiedDelta);

        // BeforeSwapDelta varies such that it is not sorted by token0 and token1
        // Instead, it is sorted by "specifiedCurrency" and "unspecifiedCurrency"
        BeforeSwapDelta beforeSwapDelta = toBeforeSwapDelta(
            specifiedDelta,
            unspecifiedDelta
        );

        // Convert int128 → int256 → uint256 safely
        uint256 amountIn = uint256(int256(unspecifiedDelta));      
        uint256 amountOut = uint256(int256(-specifiedDelta));      
        console.log("amountIn:", amountIn/1e18);
        console.log("amountOut:", amountOut/1e18);

        if (params.zeroForOne) {
            // Token0 = USDC, Token1 = WIN
            // User1 wants 200 WIN → pays betcost USDC
            // Pull USDC from user, but assign claim to the HOOK (this contract) so use false
            key.currency0.take(poolManager, address(this), amountIn, false);     // user gives USDC
            key.currency1.settle(poolManager, address(this), amountOut, true);  // user gets WIN

            // Balances inside this _beforeSwap() are not updated directly

        } else {
            // User wants 100 USDC → pays 200 WIN (reverse direction)

            key.currency1.take(poolManager, address(this), amountIn, true);    // user gives 400 USDC
            key.currency0.settle(poolManager, address(this), amountOut, true); // user gets 200 WIN
        }

        uint256 claimable = key.currency0.balanceOf(address(this)); // 
        //console.log("usdcClaimBalance: ", claimable);


        return (this.beforeSwap.selector, beforeSwapDelta, 0);
    }


    // Main function to place bets into an outcome
    function placeBet(Outcome _outcome, uint256 _amount, address _user) public  {
    //function placeBet(Outcome _outcome, uint256 _amount) public  {
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


        console.log("User's address: ", _user);
        userBets[_outcome][_user] += _amount;
        
        emit BetPlaced(_user, _outcome, _amount, betCost);

    }

     // Claim winnings after match is resolved
    function claimWinnings(PoolKey calldata key, address _user) external {

        // Determine the winning outcome
        Outcome winningOutcome;

        require(matchSettled, "Not settled");

          if (outcomeIsWIN) {
            winningOutcome = Outcome.HOME_WINS;
        } else if (outcomeIsLOSE) {
            winningOutcome = Outcome.HOME_LOSE;
        } else if (outcomeIsDRAW) {
            winningOutcome = Outcome.HOME_DRAW;
        } else {
            revert("No outcome set yet");
        }
            
     
        console.log("winningOutcome: ", uint8(winningOutcome));
     
        uint256 userBet = userBets[winningOutcome][_user];
        require(userBet > 0, "No winnings to claim");

        // Calculate total winnings pool
        uint256 totalWinningBets = liquidity[winningOutcome];

        uint256 balanceUSDCWinPool = key.currency0.balanceOf(address(this));
        console.log("balanceUSDCWinPool: ", balanceUSDCWinPool/1e18);

        // Calculate user share based on their bet proportion
        uint256 prizePool = balanceUSDCWinPool;
        console.log("userBet: ", userBet/1e18);
         console.log("totalWinningBets: ", totalWinningBets/1e18);
        uint256 userPrice = (userBet * prizePool) / totalWinningBets;
        console.log("user Price: ", userPrice/1e18);


        uint256 userShares = userBets[winningOutcome][_user];
        require(userShares > 0, "Nothing to claim");

        uint256 totalShares = liquidity[winningOutcome];

        // Get USDC balance claimable by this hook
        uint256 payout = (userShares * prizePool) / totalShares;

        console.log("Payout:" , payout/1e18);

        require(payout > 0, "Nothing to send");

        userBets[winningOutcome][_user] = 0;

        IERC20Minimal(Currency.unwrap(key.currency0)).transfer(_user, payout);

        

    }

     // LMSR market pricing: get total cost of current market
    function getMarketCost() public view returns (uint256) {
        uint256 expSum = this.expScaled(liquidity[Outcome.HOME_WINS]) +
                        this.expScaled(liquidity[Outcome.HOME_DRAW]) +
                        this.expScaled(liquidity[Outcome.HOME_LOSE]);

        // The cost of a bet increases exponentially as the bet size increases.

        // Use PRBMath for ln(expSum) directly
        UD60x18 fixedX = ud(expSum);  // Scale x correctly to 18 decimals
     
        uint256 lnExpSum = fixedX.ln().unwrap();
       
        // Return the market cost
        return (liquidityParameter * lnExpSum) / 1e18; // Final scaling
        
    }

   // Scales input by liquidityParameter before computing exp()
    function expScaled(uint256 x) public view returns (uint256) {
        //require(x <= 133e18, "Input too large for exp()");
        
        // Convert x to fixed-point (18 decimals)
        UD60x18 fixedX = ud((x * 1e18) / liquidityParameter);  
        
        return fixedX.exp().unwrap(); // Compute e^x correctly
    }

    
     // Opens betting market with a start and end time
    function openBetMarket(uint256 _startTime, uint256 _endTime) external  {
        require(!betMarketOpen, "Market already open");
        require(_startTime < _endTime, "Invalid time range");
        
        betMarketOpen = true;
        betMarketClosed = false;
        resolved = false;
        startTime = _startTime;
        endTime = _endTime;
    }

    // Function to close the Betting market
    function closeBetMarket() external {
        require(betMarketOpen, "Market is not open");
        require(block.timestamp >= startTime, "Cannot close before start");

        betMarketOpen = false;
        betMarketClosed = true;
    }

     // Resolves the match with a winning outcome
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

        matchSettled = true;
    }

     // Resets all state variables to prepare for a new match
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

    // Public view function for frontend to get market state
    function getMarketState() external view returns (bool, bool, bool, uint256, uint256) {
        return (betMarketOpen, betMarketClosed, resolved, startTime, endTime);
    }

    // Helper function to compute a deterministic pool ID
    function getPoolId(PoolKey memory key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key));
    }

    // Associates pool keys with their respective outcomes
    function registerPools(PoolKey calldata keyWin, PoolKey calldata keyLose, PoolKey calldata keyDraw) external {
        poolToOutcome[getPoolId(keyWin)] = Outcome.HOME_WINS;
        poolToOutcome[getPoolId(keyLose)] = Outcome.HOME_LOSE;
        poolToOutcome[getPoolId(keyDraw)] = Outcome.HOME_DRAW;
    }




}