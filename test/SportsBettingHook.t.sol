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

    address user1 = address(0x1111); 
    address user2 = address(0x2222);
    address user3 = address(0x3333);

    Currency public currencyUsdc; // USDC
    Currency public currencyWin; // WIN
    Currency public currencyLose; // LOSE
    Currency public currencyDraw; // DRAW

    PoolKey public keyWin;
    PoolKey public keyLose;
    PoolKey public keyDraw;

     // Initialize bets
    uint256 amountInUser1 = 20 * 1e18; // 20 WIN Tokens
    uint256 public storedBetCost; // State variable to store bet cost

    function setUp() public {
        // Note: Deployers only works with currency0 and currency1
        deployFreshManagerAndRouters();
        // (currency0, currency1) = deployMintAndApprove2Currencies();

         
        // Deploy USDC token manually 
        MockERC20 usdcToken = new MockERC20("USDC", "USDC", 18);
        usdcToken.mint(address(this), 1_000_000 ether);
        usdcToken.approve(address(hook), type(uint256).max);
        currencyUsdc = Currency.wrap(address(usdcToken));

                // Deploy USDC token manually 
        MockERC20 winToken = new MockERC20("WIN", "WIN", 18);
        winToken.mint(address(this), 1_000_000 ether);
        winToken.approve(address(hook), type(uint256).max);
        currencyWin = Currency.wrap(address(winToken));
        
        // Deploy LOSE token manually 
        MockERC20 loseToken = new MockERC20("LOSE", "LOSE", 18);
        loseToken.mint(address(this), 1_000_000 ether);
        loseToken.approve(address(hook), type(uint256).max);
        currencyLose = Currency.wrap(address(loseToken));

        // Deploy DRAW token manually 
        MockERC20 drawToken = new MockERC20("DRAW", "DRAW", 18);
        drawToken.mint(address(this), 1_000_000 ether);
        drawToken.approve(address(hook), type(uint256).max);
        currencyDraw = Currency.wrap(address(drawToken));


        address hookAddress = address(
            uint160(
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                    Hooks.BEFORE_SWAP_FLAG |
                    Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
            )
        );
        deployCodeTo("SportsBettingHook.sol", abi.encode(manager), hookAddress);
        hook = SportsBettingHook(hookAddress);

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


        // Add some initial liquidity through the custom `addLiquidity` function
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

        // Cast to mock token interface if needed
        MockERC20(tokenUsdc).mint(user1, 10000 ether);
        MockERC20(tokenUsdc).mint(user2, 10000 ether);
        MockERC20(tokenUsdc).mint(user3, 10000 ether);
 
        // Add liquidity to 3 outcome pools
        hook.addLiquidity(keyWin, 1000e18);
        hook.addLiquidity(keyLose, 1000e18);
        hook.addLiquidity(keyDraw, 1000e18);
  
        // Check balances
        uint256 balancePM0 = currencyUsdc.balanceOf(address(manager));
        uint256 balancePM1 = currencyWin.balanceOf(address(manager)); 
        uint256 balancePM2 = currencyLose.balanceOf(address(manager));  
        uint256 balancePM3 = currencyDraw.balanceOf(address(manager));    
        console.log("Balance PM currency USDC: ", balancePM0);
        console.log("Balance PM currency WIN: ", balancePM1);  
        console.log("Balance PM currency LOSE: ", balancePM2);  
        console.log("Balance PM currency DRAW: ", balancePM3); 

   
        hook.registerPools(keyWin, keyLose, keyDraw);


    }

    //  function test_claimTokenBalances() public view {
//         // We add 1000 * (10^18) of liquidity of each token to the CSMM pool
//         // The actual tokens will move into the PM
//         // But the hook should get equivalent amount of claim tokens for each token
//         uint token0ClaimID = CurrencyLibrary.toId(currency0);
//         uint token1ClaimID = CurrencyLibrary.toId(currency1);
//         console.log("token0ClaimID: ", token0ClaimID);
//         console.log("token1ClaimID: ", token1ClaimID);


//         uint token0ClaimsBalance = manager.balanceOf(
//             address(hook),
//             token0ClaimID
//         );
//         uint token1ClaimsBalance = manager.balanceOf(
//             address(hook),
//             token1ClaimID
//         );
//         // console.log("Address PM:" , address(manager));
//         console.log("Balance token0ClaimsBalance Hook:" , token0ClaimsBalance);
//         console.log("Balance token1ClaimsBalance Hook:" , token1ClaimsBalance);



//         assertEq(token0ClaimsBalance, 1000e18);
//         assertEq(token1ClaimsBalance, 1000e18);
//     }



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

    

     function test_swap_exactOutput_zeroForOne() public {

        // Settings swap 
        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
       
        // User 1 bets on WIN
         vm.startPrank(user1);

        // IERC20Minimal(Currency.unwrap(currencyUsdc)).approve(address(manager), type(uint256).max);
        // IERC20Minimal(Currency.unwrap(currencyWin)).approve(address(manager), type(uint256).max);
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


        // User 2 bets on LOSE
        vm.startPrank(user2);

        // IERC20Minimal(Currency.unwrap(currencyUsdc)).approve(address(manager), type(uint256).max);
        // IERC20Minimal(Currency.unwrap(currencyWin)).approve(address(manager), type(uint256).max);
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


        // User 3 bets on DRAW
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


        // Close bet market
        hook.closeBetMarket();

        // Set match result
        hook.resolveMarket(1); // 1 = WIN, 2 = LOSE, 3 = DRAW


         // Call function to claim the winnings
         hook.claimWinnings(keyLose, user1);

         vm.stopPrank();

    }

   

//     function getLMSRPrice() public {
        
//             // Swap functionality here
//             // vm.startPrank(user1);

//             // Determine price of token HomeWin based on LMSR
            
//             // 1. Open Bet Market
//             hook.openBetMarket(1,10);
//             bool betMarketOpen = hook.betMarketOpen();
//             console.log("Status Bet Market: ", betMarketOpen);

//             // 3 users with different bets
//             // tokenUsdc.approve(address(sportsBettingHook), amountInUser1);
//             //hook.placeBet(SportsBettingHook.Outcome.HOME_WINS, amountInUser1);
//             hook.placeBet(SportsBettingHook.Outcome.HOME_WINS, amountInUser1, address(user1));
            
//             console.log("Bet amount user 1:", hook.betAmount());
//             console.log("Initial cost :", hook.initialCost());   
//             console.log("New liquidity:", hook.newLiquidity());   
//             console.log("New cost:", hook.newCost()); 

//             // Retrieve bet cost from public state variable
//             storedBetCost = hook.betCost();

//             // Log bet cost
//             console.log("Bet cost User 1, calculated by LMSR:", storedBetCost, "USDC");

//             // Assertions to ensure `betCost` updated correctly
//             assertGt(storedBetCost, 0, "Bet cost should be greater than zero");

            
   
//     }
}