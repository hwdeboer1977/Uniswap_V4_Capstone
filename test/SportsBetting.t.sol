// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

import "forge-std/console.sol";
import {SportsBetting} from "../src/SportsBetting.sol";

contract TestSportsBetting is Test, Deployers {
    using CurrencyLibrary for Currency;

    uint256 public storedBetCost; // State variable to store bet cost
    MockERC20 token0;
    MockERC20 token1;

    Currency token0Currency;
    Currency token1Currency;

    SportsBetting hook;

    function setUp() public {
        // Step 1 + 2
        // Deploy PoolManager and Router contracts
        deployFreshManagerAndRouters();

        // Create 2 ERC-20 test tokens
        token0 = new MockERC20("Test Token 0", "TEST0", 18);
        token1 = new MockERC20("Test Token 1", "TEST1", 18);
        token0Currency = Currency.wrap(address(token0));
        token1Currency = Currency.wrap(address(token1));
        console.log("Address token 0: ", address(token0));
        console.log("Address token 1: ", address(token1));

        // Mint a bunch of TOKEN to ourselves and to address(1)
        token0.mint(address(this), 1000 ether);
        token0.mint(address(1), 1000 ether);
        token1.mint(address(this), 1000 ether);
        token1.mint(address(1), 1000 ether);
        console.log("Tokens 0 and 1 has been minted!");

        // Deploy hook to an address that has the proper flags set
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG 
        );
        deployCodeTo(
            "SportsBetting.sol",
            abi.encode(manager, token0, token1, "Points Token", "TEST_POINTS"),
            address(flags)
        );


        // Deploy our hook
        hook = SportsBetting(address(flags));

        // Place bet in our hook
        // hook.placeBet(SportsBetting.Outcome.LIV_WINS, 100);
        // console.log(hook.betCost());
    
        // hook.placeBet(SportsBetting.Outcome.LIV_WINS, 20);
        // console.log("totalLiquidity:", hook.totalLiquidity());
        // console.log("Bet cost calculated by LMSR:", hook.initialCost(), "USDC");

 

        // Approve our TOKEN for spending on the swap router and modify liquidity router
        // These variables are coming from the `Deployers` contract
        token0.approve(address(swapRouter), type(uint256).max);
        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);

        
        // (key, ) = initPool(
        //     token0Currency, // Currency 0 = ETH
        //     token1Currency, // Currency 1 = TOKEN
        //     hook, // Hook Contract
        //     3000, // Swap Fees
        //     SQRT_PRICE_1_1 // Initial Sqrt(P) value = 1
        // );
    }

    function testPlaceBet() public {
            uint256 amountIn = 200 * 1e18; // 20 USDC
            //uint256 amountIn = 20; // 20 USDC

            // ✅ Approve the contract to spend USDC
            token0.approve(address(hook), amountIn);

            console.log("Approved USDC for betting contract");

            // Call placeBet()
             hook.placeBet(SportsBetting.Outcome.LIV_WINS, amountIn);
            
             console.log("Bet amount:", hook.betAmount());
              console.log("Initial cost:", hook.initialCost());   
                 console.log("New liquidity:", hook.newLiquidity());   
                 console.log("New cost:", hook.newCost());   
            // Retrieve bet cost from public state variable
            storedBetCost = hook.betCost();

            // Log bet cost
            console.log("Bet cost calculated by LMSR:", storedBetCost, "USDC");

            // Assertions to ensure `betCost` updated correctly
            assertGt(storedBetCost, 0, "Bet cost should be greater than zero");

            uint256 amountToSwap = storedBetCost/2;
            
        }


    // function test_addLiquidityAndSwap() public {
    //     // uint256 pointsBalanceOriginal = hook.balanceOf(address(this));

    //     // // Set user address in hook data
    //     // bytes memory hookData = abi.encode(address(this));

    //     // uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
    //     // uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);
    //     // console.log("sqrtPriceAtTickLower:", sqrtPriceAtTickLower);
    //     // console.log("sqrtPriceAtTickUpper:", sqrtPriceAtTickUpper);
    //     // console.log("SQRT_PRICE_1_1:", SQRT_PRICE_1_1);

    //     // uint256 ethToAdd = 1 ether;
    //     // uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(
    //     //     sqrtPriceAtTickLower,
    //     //     SQRT_PRICE_1_1,
    //     //     ethToAdd
    //     // );
    //     // console.log("Decimals for token0:", token0.decimals());
    //     // console.log("Decimals for token1:", token1.decimals());
    //     // console.log("liquidityDelta:", liquidityDelta);

    //     // uint256 tokenToAdd = LiquidityAmounts.getAmount1ForLiquidity(
    //     //     sqrtPriceAtTickUpper,
    //     //     SQRT_PRICE_1_1,
    //     //     liquidityDelta
    //     // );
    //     // console.log("tokenToAdd:", tokenToAdd);

    //     // modifyLiquidityRouter.modifyLiquidity{value: ethToAdd}(
    //     //     key,
    //     //     IPoolManager.ModifyLiquidityParams({
    //     //         tickLower: -60,
    //     //         tickUpper: 60,
    //     //         liquidityDelta: int256(uint256(liquidityDelta)),
    //     //         salt: bytes32(0)
    //     //     }),
    //     //     hookData
    //     // );
    //     // uint256 pointsBalanceAfterAddLiquidity = hook.balanceOf(address(this));

    //     // assertApproxEqAbs(
    //     //     pointsBalanceAfterAddLiquidity - pointsBalanceOriginal,
    //     //     0.1 ether,
    //     //     0.001 ether // error margin for precision loss
    //     // );

    //     // Now we swap
    //     // We will swap 0.001 ether for tokens
    //     // We should get 20% of 0.001 * 10**18 points
    //     // = 2 * 10**14
    //     // swapRouter.swap{value: 0.001 ether}(
    //     //     key,
    //     //     IPoolManager.SwapParams({
    //     //         zeroForOne: true,
    //     //         amountSpecified: -0.001 ether, // Exact input for output swap
    //     //         sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
    //     //     }),
    //     //     PoolSwapTest.TestSettings({
    //     //         takeClaims: false,
    //     //         settleUsingBurn: false
    //     //     }),
    //     //     hookData
    //     // );
    //     // uint256 pointsBalanceAfterSwap = hook.balanceOf(address(this));
    //     // assertEq(
    //     //     pointsBalanceAfterSwap - pointsBalanceAfterAddLiquidity,
    //     //     2 * 10 ** 14
    //     // );
    // }
}