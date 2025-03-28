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

     // Initialize bets
    uint256 amountInUser1 = 20 * 1e18; // 20 WIN Tokens
    uint256 public storedBetCost; // State variable to store bet cost

    function setUp() public {
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployMintAndApprove2Currencies();

        address hookAddress = address(
            uint160(
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                    Hooks.BEFORE_SWAP_FLAG |
                    Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
            )
        );
        deployCodeTo("SportsBettingHook.sol", abi.encode(manager), hookAddress);
        hook = SportsBettingHook(hookAddress);

        (key, ) = initPool(
            currency0,
            currency1,
            hook,
            3000,
            SQRT_PRICE_1_1
            // ZERO_BYTES
        );

        // Add some initial liquidity through the custom `addLiquidity` function
        IERC20Minimal(Currency.unwrap(key.currency0)).approve(
            hookAddress,
            1000 ether
        );
        IERC20Minimal(Currency.unwrap(key.currency1)).approve(
            hookAddress,
            1000 ether
        );

        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);
        console.log("Address token 0: ", token0);
         console.log("Address token 1: ", token1);

        // Cast to mock token interface if needed
        MockERC20(token0).mint(user1, 1000 ether);
        MockERC20(token1).mint(user1, 1000 ether);


        hook.addLiquidity(key, 1000e18);
        // console.log("Address hook: ", address(hook));
        // console.log("Currency 0 address: ", Currency.unwrap(key.currency0));
        // console.log("Currency 1 address: ", Currency.unwrap(key.currency1));

        // uint256 balanceHook0 = currency0.balanceOf(address(hook));
        // uint256 balancePM0 = currency0.balanceOf(address(manager));
        // uint256 balanceHook1 = currency1.balanceOf(address(hook));
        // uint256 balancePM1 = currency1.balanceOf(address(manager));  
        // console.log("Balance Hook currency 0: ", balanceHook0);
        // console.log("Balance Hook currency 1: ", balanceHook1);  
        // console.log("Balance PM currency 0: ", balancePM0);
        // console.log("Balance PM currency 1: ", balancePM1);  

    }

    function test_claimTokenBalances() public view {
        // We add 1000 * (10^18) of liquidity of each token to the CSMM pool
        // The actual tokens will move into the PM
        // But the hook should get equivalent amount of claim tokens for each token
        uint token0ClaimID = CurrencyLibrary.toId(currency0);
        uint token1ClaimID = CurrencyLibrary.toId(currency1);
        console.log("token0ClaimID: ", token0ClaimID);
        console.log("token1ClaimID: ", token1ClaimID);


        uint token0ClaimsBalance = manager.balanceOf(
            address(hook),
            token0ClaimID
        );
        uint token1ClaimsBalance = manager.balanceOf(
            address(hook),
            token1ClaimID
        );
        // console.log("Address PM:" , address(manager));
        console.log("Balance token0ClaimsBalance Hook:" , token0ClaimsBalance);
        console.log("Balance token1ClaimsBalance Hook:" , token1ClaimsBalance);



        assertEq(token0ClaimsBalance, 1000e18);
        assertEq(token1ClaimsBalance, 1000e18);
    }



    // function test_cannotModifyLiquidity() public {
    //     vm.expectRevert();
    //     modifyLiquidityRouter.modifyLiquidity(
    //         key,
    //         IPoolManager.ModifyLiquidityParams({
    //             tickLower: -60,
    //             tickUpper: 60,
    //             liquidityDelta: 1e18,
    //             salt: bytes32(0)
    //         }),
    //         ZERO_BYTES
    //     );
    // }

    

    function test_swap_exactOutput_zeroForOne() public {

       

        vm.startPrank(user1);

        
        uint256 balancePM0Before = currency0.balanceOf(address(manager));
        uint256 balancePM1Before = currency1.balanceOf(address(manager));  
        console.log("Balance PM currency 0 before swap: ", balancePM0Before);
        console.log("Balance PM currency 1 before swap: ", balancePM1Before);  




        uint256 balanceHook0Before = currency0.balanceOf(address(hook));
        uint256 balanceHook1Before = currency1.balanceOf(address(hook));  
        console.log("Balance Hook currency 0 before swap: ", balanceHook0Before);
        console.log("Balance Hook currency 1 before swap: ", balanceHook1Before);  


        uint256 balanceUserToken0 = currency0.balanceOf(user1);
        uint256 balanceUserToken1 = currency1.balanceOf(user1);
        console.log("balanceUserToken0 before swap: ", balanceUserToken0);
        console.log("balanceUserToken1 before swap: ", balanceUserToken1);

        IERC20Minimal(Currency.unwrap(key.currency0)).approve(address(manager), type(uint256).max);
        IERC20Minimal(Currency.unwrap(key.currency1)).approve(address(manager), type(uint256).max);
        IERC20Minimal(Currency.unwrap(key.currency0)).approve(address(swapRouter), type(uint256).max);
        IERC20Minimal(Currency.unwrap(key.currency1)).approve(address(swapRouter), type(uint256).max);

        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

    

        // Swap token 
        swapRouter.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: 200e18,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            settings,
            abi.encode(user1)
            //ZERO_BYTES
        );

        
   
         // In real world dApp: 
         // const encodedUser = ethers.utils.defaultAbiCoder.encode(["address"], [wallet.address]);
         // await router.swap(key, swapParams, settings, encodedUser);


        uint256 balancePM0 = currency0.balanceOf(address(manager));
        uint256 balancePM1 = currency1.balanceOf(address(manager));  
        console.log("Balance PM currency 0 after swap: ", balancePM0);
        console.log("Balance PM currency 1 after swap: ", balancePM1);  




        uint256 balanceHook0 = currency0.balanceOf(address(hook));
        uint256 balanceHook1 = currency1.balanceOf(address(hook));  
        console.log("Balance Hook currency 0 after swap: ", balanceHook0);
        console.log("Balance Hook currency 1 after swap: ", balanceHook1);  



         uint token0ClaimID = CurrencyLibrary.toId(currency0);
        uint token1ClaimID = CurrencyLibrary.toId(currency1);
        uint token0ClaimsBalance = manager.balanceOf(
            address(hook),
            token0ClaimID
        );
        uint token1ClaimsBalance = manager.balanceOf(
            address(hook),
            token1ClaimID
        );
        // console.log("Address PM:" , address(manager));
        console.log("Balance token0ClaimsBalance Hook after swap:" , token0ClaimsBalance);
        console.log("Balance token1ClaimsBalance Hook after swap:" , token1ClaimsBalance);

        uint256 newBalanceUserToken0 = currency0.balanceOf(user1);
        uint256 newBalanceUserToken1 = currency1.balanceOf(user1);
        console.log("newBalanceUserToken0 after swap: ", newBalanceUserToken0);
        console.log("newBalanceUserToken1 after swap: ", newBalanceUserToken1);

       

        // Trigger the payout from the hook
       hook.sendUSDCToWinner(key, user1);
        
        // Call function to determine the betting outcome
        // Call function to claim the winnings
        //hook.claimWinnings(key, user1);

         vm.stopPrank();
        //
    }

   

    function getLMSRPrice() public {
        
            // Swap functionality here
            // vm.startPrank(user1);

            // Determine price of token HomeWin based on LMSR
            
            // 1. Open Bet Market
            hook.openBetMarket(1,10);
            bool betMarketOpen = hook.betMarketOpen();
            console.log("Status Bet Market: ", betMarketOpen);

            // 3 users with different bets
            // tokenUsdc.approve(address(sportsBettingHook), amountInUser1);
            //hook.placeBet(SportsBettingHook.Outcome.HOME_WINS, amountInUser1);
            hook.placeBet(SportsBettingHook.Outcome.HOME_WINS, amountInUser1, address(user1));
            
            console.log("Bet amount user 1:", hook.betAmount());
            console.log("Initial cost :", hook.initialCost());   
            console.log("New liquidity:", hook.newLiquidity());   
            console.log("New cost:", hook.newCost()); 

            // Retrieve bet cost from public state variable
            storedBetCost = hook.betCost();

            // Log bet cost
            console.log("Bet cost User 1, calculated by LMSR:", storedBetCost, "USDC");

            // Assertions to ensure `betCost` updated correctly
            assertGt(storedBetCost, 0, "Bet cost should be greater than zero");

            
   
    }
}