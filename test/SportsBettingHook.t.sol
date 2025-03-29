// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {SportsBettingHook} from "../src/SportsBettingHook.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import "forge-std/console.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract SportsBettingHookTest is Test, Deployers {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;

    SportsBettingHook hook;

    // Sample user addresses for placing bets
    address user1 = address(0x1111); 
    address user2 = address(0x2222);
    address user3 = address(0x3333);

     // Currency types (ERC20 wrapped into Uniswap's Currency type)
    Currency public currencyUsdc; // USDC
    Currency public currencyWin; // WIN
    Currency public currencyLose; // LOSE
    Currency public currencyDraw; // DRAW

    // Pool keys for each outcome pool
    PoolKey public keyWin;
    PoolKey public keyLose;
    PoolKey public keyDraw;

     // Amount used for test betting
    uint256 amountInUser1 = 20 * 1e18; // 20 WIN Tokens

    // Optional: a storage variable to track last bet cost
    uint256 public storedBetCost; 

     // Setup logic that runs before every test
    function setUp() public {
        // Deploy new Uniswap V4 PoolManager and router
        // Deployers only works with currency0 and currency1
        deployFreshManagerAndRouters();
        

         
        // Manually deploy mock tokens for the test
        MockERC20 usdcToken = new MockERC20("USDC", "USDC", 18);
        usdcToken.mint(address(this), 1_000_000 ether);
        usdcToken.approve(address(hook), type(uint256).max);
        currencyUsdc = Currency.wrap(address(usdcToken));


        MockERC20 winToken = new MockERC20("WIN", "WIN", 18);
        winToken.mint(address(this), 1_000_000 ether);
        winToken.approve(address(hook), type(uint256).max);
        currencyWin = Currency.wrap(address(winToken));

        MockERC20 loseToken = new MockERC20("LOSE", "LOSE", 18);
        loseToken.mint(address(this), 1_000_000 ether);
        loseToken.approve(address(hook), type(uint256).max);
        currencyLose = Currency.wrap(address(loseToken));

       
        MockERC20 drawToken = new MockERC20("DRAW", "DRAW", 18);
        drawToken.mint(address(this), 1_000_000 ether);
        drawToken.approve(address(hook), type(uint256).max);
        currencyDraw = Currency.wrap(address(drawToken));

        // Deploy and configure the hook with required flags
        address hookAddress = address(
            uint160(
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                    Hooks.BEFORE_SWAP_FLAG |
                    Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
            )
        );
        deployCodeTo("SportsBettingHook.sol", abi.encode(manager), hookAddress);
        hook = SportsBettingHook(hookAddress);

        // Initialize pools with each outcome (USDC paired with WIN, LOSE, DRAW)
        (keyWin, ) = initPool(
            currencyUsdc,
            currencyWin,
            hook,
            3000,
            SQRT_PRICE_1_1
            // ZERO_BYTES
        );

        (keyLose, ) = initPool(currencyUsdc, currencyLose, hook, 3000, SQRT_PRICE_1_1);
        (keyDraw, ) = initPool(currencyUsdc, currencyDraw, hook, 3000, SQRT_PRICE_1_1);


        // Approve tokens to the hook so it can add liquidity
        IERC20Minimal(Currency.unwrap(currencyUsdc)).approve(
            hookAddress,
            1_000_000 ether
        );
        IERC20Minimal(Currency.unwrap(currencyWin)).approve(
            hookAddress,
            1_000_000 ether
        );

        IERC20Minimal(Currency.unwrap(currencyLose)).approve(
            hookAddress,
            1_000_000 ether
        );

        IERC20Minimal(Currency.unwrap(currencyDraw)).approve(
            hookAddress,
            1_000_000 ether
        );


        // Check addresses 
        address tokenUsdc = Currency.unwrap(currencyUsdc);
        address tokenWin = Currency.unwrap(currencyWin);
        address tokenLose = Currency.unwrap(currencyLose);
        address tokenDraw = Currency.unwrap(currencyDraw);
        console.log("Address token USDC: ", tokenUsdc);
        console.log("Address token WIN: ", tokenWin);
        console.log("Address token LOSE: ", tokenLose);
        console.log("Address token DRAW: ", tokenDraw);

        // Mint USDC to users for betting
        MockERC20(tokenUsdc).mint(user1, 10000 ether);
        MockERC20(tokenUsdc).mint(user2, 10000 ether);
        MockERC20(tokenUsdc).mint(user3, 10000 ether);
 
        // Add liquidity to 3 outcome pools
        hook.addLiquidity(keyWin, 1000e18);
        hook.addLiquidity(keyLose, 1000e18);
        hook.addLiquidity(keyDraw, 1000e18);
  
        // Log pool balances (optional debug)
        uint256 balancePM0 = currencyUsdc.balanceOf(address(manager));
        uint256 balancePM1 = currencyWin.balanceOf(address(manager)); 
        uint256 balancePM2 = currencyLose.balanceOf(address(manager));  
        uint256 balancePM3 = currencyDraw.balanceOf(address(manager));    
        console.log("Balance PM currency USDC: ", balancePM0);
        console.log("Balance PM currency WIN: ", balancePM1);  
        console.log("Balance PM currency LOSE: ", balancePM2);  
        console.log("Balance PM currency DRAW: ", balancePM3); 

        // Map each pool key to its associated outcome
        hook.registerPools(keyWin, keyLose, keyDraw);


    }



    // Test that liquidity cannot be modified directly through the router (expected revert)
    function test_cannotModifyLiquidity() public {
        vm.expectRevert();
        modifyLiquidityRouter.modifyLiquidity(
            keyWin,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 1e18,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

    }

    
     // Main test: three users place bets on three outcomes, market is resolved, and one claims winnings
     function test_swap_exactOutput_zeroForOne() public {

        // Settings swap 
        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
       
        // --- User 1 bets on WIN outcome ---
         vm.startPrank(user1);

        // Approve tokens
        IERC20Minimal(Currency.unwrap(currencyUsdc)).approve(address(swapRouter), type(uint256).max);
        IERC20Minimal(Currency.unwrap(currencyWin)).approve(address(swapRouter), type(uint256).max);


    
        // Swap token 
        swapRouter.swap(
            keyWin,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: 200e18,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            settings,
            abi.encode(user1)
            //ZERO_BYTES
        );

         vm.stopPrank();


        // --- User 2 bets on LOSE outcome ---
        vm.startPrank(user2);


        IERC20Minimal(Currency.unwrap(currencyUsdc)).approve(address(swapRouter), type(uint256).max);
        IERC20Minimal(Currency.unwrap(currencyWin)).approve(address(swapRouter), type(uint256).max);

    
        // Swap token 
        swapRouter.swap(
            keyLose,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: 100e18,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            settings,
            abi.encode(user2)
            //ZERO_BYTES
        );

         vm.stopPrank();


        // --- User 3 bets on DRAW outcome ---
        vm.startPrank(user3);

        // Approvals
        IERC20Minimal(Currency.unwrap(currencyUsdc)).approve(address(swapRouter), type(uint256).max);
        IERC20Minimal(Currency.unwrap(currencyWin)).approve(address(swapRouter), type(uint256).max);

    
        // Swap token 
        swapRouter.swap(
            keyDraw,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: 150e18,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            settings,
            abi.encode(user3)
            //ZERO_BYTES
        );

         vm.stopPrank();
        
   
         // In real world dApp: 
         // const encodedUser = ethers.utils.defaultAbiCoder.encode(["address"], [wallet.address]);
         // await router.swap(key, swapParams, settings, encodedUser);


        // PM: in a production-ready betting protocol, we should open and close betting with oracle
        // Use an off-chain data feed or API (like an oracle) to
        // Automatically schedule when a match begins (e.g., based on match fixtures).
        // Open betting N hours before kickoff.
        // Close the market and resolve the outcome to WIN
        hook.closeBetMarket();

        hook.resolveMarket(1); // 1 = WIN, 2 = LOSE, 3 = DRAW

         // Let user1 claim their winnings for the WIN pool
         // Call function to claim the winnings
         hook.claimWinnings(keyLose, user1);

         vm.stopPrank();

    }

   
}