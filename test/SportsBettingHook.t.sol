// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import "forge-std/console.sol";
import {SportsBettingHook} from "../src/SportsBettingHook.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {PosmTestSetup} from "v4-periphery/test/shared/PosmTestSetup.sol";
import {Deploy, IPositionDescriptor} from "v4-periphery/test/shared/Deploy.sol";
import {PositionDescriptor} from "lib/v4-periphery/src/PositionDescriptor.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";

contract TestSportsBettingHook is Test, Deployers, PosmTestSetup  {
     using CurrencyLibrary for Currency;

    uint256 public storedBetCost; // State variable to store bet cost
    uint256 public priceHomeWinAMM;

    MockERC20 tokenUsdc;
    MockERC20 tokenHomeWin;

    PoolId poolId;
    uint256 tokenId;
    Currency tokenUsdcCurrency;
    Currency tokenHomeWinCurrency;
    address owner = address(this);

    address user1 = address(0x1111); 
    address user2 = address(0x2222);
    address user3 = address(0x3333);

    // Initialize bets
    uint256 amountInUser1 = 20 * 1e18; // 20 WIN Tokens

    // Sportsbetting hook
    SportsBettingHook sportsBettingHook;
    bytes hookData = abi.encode(address(this));
    uint256 matchStartTime = 10;

	// PositionManager NFT
	IPositionManager posm;
    PoolKey poolKey;

    function setUp() public {
        
        // Deploy PoolManager and Router contracts
        deployFreshManagerAndRouters();
    
        // Deploy an instance of PositionManager
	    deployPosm(manager);


        // Create 2 ERC-20 test tokens
        tokenUsdc = new MockERC20("Test Token USDC", "USDC", 18);
        tokenHomeWin = new MockERC20("Test Token HomeWin", "HOMEWIN", 18);
        tokenUsdcCurrency = Currency.wrap(address(tokenUsdc));
        tokenHomeWinCurrency = Currency.wrap(address(tokenHomeWin));
        console.log("Address token 0: ", address(tokenUsdc));
        console.log("Address token 1: ", address(tokenHomeWin));

        // Mint a bunch of TOKEN to ourselves and to address(1)
        tokenUsdc.mint(address(this), 1000000 ether);
        tokenUsdc.mint(user1, 1000 ether);
        tokenUsdc.mint(user2, 1000 ether);
        tokenUsdc.mint(user3, 1000 ether);
        tokenHomeWin.mint(address(this), 1000000 ether);
        tokenHomeWin.mint(user1, 1000 ether);
        tokenHomeWin.mint(user2, 1000 ether);
        tokenHomeWin.mint(user3, 1000 ether);
        console.log("Tokens 0 and 1 has been minted!");


        approvePosmCurrency(tokenUsdcCurrency);
        approvePosmCurrency(tokenHomeWinCurrency);

        // Deploy hook to an address that has the proper flags set
        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG 
        );
        deployCodeTo(
            "SportsBettingHook.sol",
             //abi.encode(manager, tokenUsdc, tokenUsdt, "Points Token", "TEST_POINTS"),
             abi.encode(manager, address(this), matchStartTime, lpm, tokenUsdc, tokenHomeWin),
            address(flags)
        );


        // Deploy our hook
        sportsBettingHook = SportsBettingHook(address(flags));
        
        // // Create the pool
        poolKey  = PoolKey(tokenHomeWinCurrency, tokenUsdcCurrency, 3000, 60, IHooks(sportsBettingHook));
        
        
        (key, ) = initPool(
			tokenHomeWinCurrency,
			tokenUsdcCurrency,
			sportsBettingHook, 
			3000,
			SQRT_PRICE_1_1
		);
        

    }

    function getLMSRPrice() public {
        
            // Swap functionality here

             vm.startPrank(user1);

            tokenUsdc.approve(address(swapRouter), type(uint256).max);
            tokenHomeWin.approve(address(swapRouter), type(uint256).max);

            uint256 balanceUSDCBefore = tokenUsdc.balanceOf(user1);
            uint256 balanceHomeWinBefore = tokenHomeWin.balanceOf(user1);
            // console.log("balanceUSDCBefore User 1:" , balanceUSDCBefore);
            // console.log("balanceHomeWinBefore User 1:" , balanceHomeWinBefore);

            uint256 managerUSDCBalanceBefore = tokenUsdc.balanceOf(address(manager));
            uint256 managerHomeWinBalanceBefore = tokenHomeWin.balanceOf(address(manager));
            // console.log("managerUSDCBalanceBefore:" , managerUSDCBalanceBefore);
            // console.log("managerHomeWinBalanceBefore:" , managerHomeWinBalanceBefore);

            

            // Determine price of token HomeWin based on its liquidity
            // This is a price at the margin
            priceHomeWinAMM = managerUSDCBalanceBefore/managerHomeWinBalanceBefore;
            // console.log("priceHomeWinAMM:", priceHomeWinAMM);



            // Determine price of token HomeWin based on LMSR
            
            // 1. Open Bet Market
            sportsBettingHook.openBetMarket(1,10);
            bool betMarketOpen = sportsBettingHook.betMarketOpen();
            console.log("Status Bet Market: ", betMarketOpen);

          
     

            // 3 users with different bets
            tokenUsdc.approve(address(sportsBettingHook), amountInUser1);
            sportsBettingHook.placeBet(SportsBettingHook.Outcome.LIV_WINS, amountInUser1);
            
            
            console.log("Bet amount user 1:", sportsBettingHook.betAmount());
            console.log("Initial cost :", sportsBettingHook.initialCost());   
            console.log("New liquidity:", sportsBettingHook.newLiquidity());   
            console.log("New cost:", sportsBettingHook.newCost()); 

            // Retrieve bet cost from public state variable
            storedBetCost = sportsBettingHook.betCost();

            // Log bet cost
            console.log("Bet cost User 1, calculated by LMSR:", storedBetCost, "USDC");

            // Assertions to ensure `betCost` updated correctly
            assertGt(storedBetCost, 0, "Bet cost should be greater than zero");

            
   
    }

    function addLiquidity() public {

            // First we add liquidity
            console.log("Adding Liquidity", "USDC and USDT...");
        
            bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));
            bytes[] memory params = new bytes[](2);

            uint256 balanceToken0BeforeThis = tokenHomeWin.balanceOf(address(this));
            uint256 balanceToken1BeforeThis = tokenUsdc.balanceOf(address(this));
             uint256 balanceToken0BeforeManager = tokenHomeWin.balanceOf(address(manager));
            uint256 balanceToken1BeforeManager = tokenUsdc.balanceOf(address(manager));
            // console.log("balanceToken0BeforeThis:", balanceToken0BeforeThis);
            // console.log("balanceToken1BeforeThis:", balanceToken1BeforeThis);
            // console.log("balanceToken0BeforeManager:", balanceToken0BeforeManager);
            // console.log("balanceToken1BeforeManager:", balanceToken1BeforeManager);


            int24 tickLower = -60;
            int24 tickUpper = 60;
            uint128 amountToAdd = 2000 * 1e18; // 2000 USDC;
            uint128 amount0Max = amountToAdd;
            uint128 amount1Max = 2000000000000000000000;
            uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
            uint256 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(
                sqrtPriceAtTickLower,
                SQRT_PRICE_1_1,
                amountToAdd
            );
            uint256 deadline = block.timestamp + 60;
           uint256 valueToPass = 0; // We are not sending ETH

            

            // owner = recipient of minted position
            params[0] = abi.encode(
                poolKey,
                tickLower,
                tickUpper,
                liquidityDelta,
                amount0Max,
                amount1Max,
                owner, 
                hookData
            );

            params[1] = abi.encode(tokenHomeWin, tokenUsdcCurrency);

            lpm.modifyLiquidities{value: valueToPass}(
                abi.encode(actions, params),
                deadline
            );


            uint128 currentLiquidity = lpm.getPositionLiquidity(1);
            console.log("currentLiquidity:", currentLiquidity);



            uint256 balanceToken0AfterThis = tokenHomeWin.balanceOf(address(this));
            uint256 balanceToken1AfterThis = tokenUsdc.balanceOf(address(this));
            uint256 balanceToken0AfterManager = tokenHomeWin.balanceOf(address(manager));
            uint256 balanceToken1AfterManager = tokenUsdc.balanceOf(address(manager));
            // console.log("balanceToken0AfterThis:", balanceToken0AfterThis);
            // console.log("balanceToken1AfterThis:", balanceToken1AfterThis);
            // console.log("balanceToken0AfterManager:", balanceToken0AfterManager);
            // console.log("balanceToken1AfterManager:", balanceToken1AfterManager);

    }

        // Add liquidity after user places bet
        function test_AddRemoveLiquidity() public {
            
           

            // Step 1: Add liquidity
            addLiquidity();

            // Step 2: Get LMSR Price
            getLMSRPrice();


            // Get prices AMM and LMSR
            console.log("storedBetCost: ", storedBetCost);
            console.log("priceHomeWinAMM: ", priceHomeWinAMM);
        
            
            uint256 wrapAmount = amountInUser1;

            PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
            
            uint160 MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
            swapRouter.swap(
                poolKey,
                IPoolManager.SwapParams({
                    // zeroForOne: true, // HOMEWIN (0) to USDC (1)
                    zeroForOne: false, // USDC (1) to HOMEWIN (0)
                    amountSpecified: -int256(wrapAmount),
                    // sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1 // zeroForOne = true
                     sqrtPriceLimitX96: MAX_SQRT_RATIO - 1 // // zeroForOne = false
                }),
                testSettings,
                ""
            );

           

            
            uint256 balanceUSDCAfter = tokenUsdc.balanceOf(user1);
            uint256 balanceHomeWinAfter = tokenHomeWin.balanceOf(user1);
            // console.log("balanceUSDCAfter User 1:" , balanceUSDCAfter);
            // console.log("balanceHomeWinAfter User 1:" , balanceHomeWinAfter);

            uint256 managerUSDCBalanceAfter = tokenUsdc.balanceOf(address(manager));
            uint256 managerHomeWinBalanceAfter = tokenHomeWin.balanceOf(address(manager));
            // console.log("managerUSDCBalanceAfter:" , managerUSDCBalanceAfter);
            // console.log("managerHomeWinBalanceAfter:" , managerHomeWinBalanceAfter);



            vm.stopPrank();
 
         }

    function removeLiquidity() public {
        
        //     uint256 myLiquidity = lpm.getPositionLiquidity(1);
        //     console.log("myLiquidity:", myLiquidity);

        //     // Then we test the removal of its liquidity
        //     console.log("Removing Liquidity", "USDC and USDT...");

        //     bytes memory actions2 = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR));
        //     bytes[] memory params2 = new bytes[](2);

          
                        
        //     // Advance time to after matchStartTime
        //     vm.warp(matchStartTime + 1); // Moves block.timestamp forward

            
        //     uint256 amount0Min = 0;
        //     uint256 amount1Min = 0;
        //     uint256 liquidity = myLiquidity;
            
        //     params2[0] = abi.encode(1, liquidity, amount0Min, amount1Min, hookData);

          
        //     params2[1] = abi.encode(tokenUsdtCurrency, tokenUsdcCurrency, address(this));

        //     uint256 deadline2 = block.timestamp + 60;

        //     uint256 valueToPass2 =  0;

        //     lpm.modifyLiquidities{value: valueToPass2}(
        //         abi.encode(actions2, params2),
        //         deadline2
        //     );

        //     uint256 balanceToken0FinalThis = tokenUsdt.balanceOf(address(this));
        //     uint256 balanceToken1FinalThis = tokenUsdc.balanceOf(address(this));
        //     console.log("balanceToken0FinalThis:", balanceToken0FinalThis);
        //     console.log("balanceToken1FinalThis:", balanceToken1FinalThis);
    }

}