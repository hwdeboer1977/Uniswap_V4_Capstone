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

    // Betting amounts
    int256 amountUser1 = 200e18;
    int256 amountUser2 = 100e18;
    int256 amountUser3 = 150e18;

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
        console.log("Balance Pool Manager currency USDC: ", balancePM0/1e18);
        console.log("Balance Pool Manager currency WIN: ", balancePM1/1e18);  
        console.log("Balance Pool Manager currency LOSE: ", balancePM2/1e18);  
        console.log("Balance Pool Manager currency DRAW: ", balancePM3/1e18); 

        // Map each pool key to its associated outcome
        hook.registerPools(keyWin, keyLose, keyDraw);


        // Set the odds before the match starts
        // For now, we are still using the initial liquidity at 0, so prob = 1/3

        // Suppose a bookmaker has the following odds: 1.60 (160), 4.23 (423), 5.30 (530)
        // The function setInitialLiquidityFromOdds then sets the correct amounts of liquidity
        // for all 3 outcomes such that we have the same odds as the bookmakers
        hook.setInitialLiquidityFromOdds(160, 423, 530);

        // Double check the outcome probablities (should be roughly the inverse of the odds above)
        hook.getOutcomeProbabilities();
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

        vm.startPrank(tx.origin);
        // Open the betting market (runs for 7 days)
        hook.openBetMarket(block.timestamp, block.timestamp + 7 days);
        vm.stopPrank();

        // --- User 1 bets on WIN outcome ---
         vm.startPrank(user1);

         
        // Store USDC balance before swap
        uint256 user1UsdcBefore = IERC20Minimal(Currency.unwrap(currencyUsdc)).balanceOf(user1);


        // Approve tokens
        IERC20Minimal(Currency.unwrap(currencyUsdc)).approve(address(swapRouter), type(uint256).max);
        IERC20Minimal(Currency.unwrap(currencyWin)).approve(address(swapRouter), type(uint256).max);


    
        // Swap token 
        swapRouter.swap(
            keyWin,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: amountUser1,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            settings,
            abi.encode(user1)
            //ZERO_BYTES
        );

        // Check USDC was spent
        uint256 user1UsdcAfter = IERC20Minimal(Currency.unwrap(currencyUsdc)).balanceOf(user1);
        assertLt(user1UsdcAfter, user1UsdcBefore); // user spent USDC


         vm.stopPrank();


        // --- User 2 bets on LOSE outcome ---
        vm.startPrank(user2);

        // Store USDC balance before swap
        uint256 user2UsdcBefore = IERC20Minimal(Currency.unwrap(currencyUsdc)).balanceOf(user2);


        // Approve tokens
        IERC20Minimal(Currency.unwrap(currencyUsdc)).approve(address(swapRouter), type(uint256).max);
        IERC20Minimal(Currency.unwrap(currencyWin)).approve(address(swapRouter), type(uint256).max);

    
        // Swap token 
        swapRouter.swap(
            keyLose,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: amountUser2,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            settings,
            abi.encode(user2)
            //ZERO_BYTES
        );

        // Check balance after swap
        uint256 user2UsdcAfter = IERC20Minimal(Currency.unwrap(currencyUsdc)).balanceOf(user2);
        assertLt(user2UsdcAfter, user2UsdcBefore);

         vm.stopPrank();


        // --- User 3 bets on DRAW outcome ---
        vm.startPrank(user3);

        
        // Store USDC balance before swap
        uint256 user3UsdcBefore = IERC20Minimal(Currency.unwrap(currencyUsdc)).balanceOf(user3);

        // Approvals
        IERC20Minimal(Currency.unwrap(currencyUsdc)).approve(address(swapRouter), type(uint256).max);
        IERC20Minimal(Currency.unwrap(currencyWin)).approve(address(swapRouter), type(uint256).max);

    
        // Swap token 
        swapRouter.swap(
            keyDraw,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: amountUser3,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            settings,
            abi.encode(user3)
            //ZERO_BYTES
        );

        // Check balance after swap
        uint256 user3UsdcAfter = IERC20Minimal(Currency.unwrap(currencyUsdc)).balanceOf(user3);
        assertLt(user3UsdcAfter, user3UsdcBefore);

         vm.stopPrank();
        
   
         // In real world dApp: 
         // const encodedUser = ethers.utils.defaultAbiCoder.encode(["address"], [wallet.address]);
         // await router.swap(key, swapParams, settings, encodedUser);


        // PM: in a production-ready betting protocol, we should open and close betting with oracle
        // Use an off-chain data feed or API (like an oracle) to
        // Automatically schedule when a match begins (e.g., based on match fixtures).
        // Open betting N hours before kickoff.
        // Close the market and resolve the outcome to WIN
        
        vm.startPrank(tx.origin);
        hook.closeBetMarket();
        vm.stopPrank();
        
        vm.startPrank(tx.origin);
        hook.resolveMarket(1); // 1 = WIN, 2 = LOSE, 3 = DRAW
        vm.stopPrank();

        // --- Payout: user1 claims winnings ---
        uint256 user1ClaimBefore = IERC20Minimal(Currency.unwrap(currencyUsdc)).balanceOf(user1);
        hook.claimWinnings(keyWin, user1);
        uint256 user1ClaimAfter = IERC20Minimal(Currency.unwrap(currencyUsdc)).balanceOf(user1);

        // Assert that user1 received a payout
        assertGt(user1ClaimAfter, user1ClaimBefore);

        // Assert user1 can't claim again (should revert or no change)
        vm.expectRevert("No winnings to claim");
        hook.claimWinnings(keyWin, user1);

        // --- User 2 tries to claim on LOSE (which was not the winning outcome) ---
        uint256 user2ClaimBefore = IERC20Minimal(Currency.unwrap(currencyUsdc)).balanceOf(user2);

        // Expect revert or no winnings
        vm.expectRevert("No winnings to claim");
        hook.claimWinnings(keyLose, user2);

        uint256 user2ClaimAfter = IERC20Minimal(Currency.unwrap(currencyUsdc)).balanceOf(user2);
        assertEq(user2ClaimAfter, user2ClaimBefore); // No payout occurred

        // --- User 3 tries to claim on DRAW ---
        uint256 user3ClaimBefore = IERC20Minimal(Currency.unwrap(currencyUsdc)).balanceOf(user3);

        vm.expectRevert("No winnings to claim");
        hook.claimWinnings(keyDraw, user3);

        uint256 user3ClaimAfter = IERC20Minimal(Currency.unwrap(currencyUsdc)).balanceOf(user3);
        assertEq(user3ClaimAfter, user3ClaimBefore); // No payout occurred

        vm.stopPrank();

    }

   
}