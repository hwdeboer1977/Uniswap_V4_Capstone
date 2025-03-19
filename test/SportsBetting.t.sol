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
import {SportsBetting} from "../src/SportsBetting.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {PosmTestSetup} from "v4-periphery/test/shared/PosmTestSetup.sol";
import {Deploy, IPositionDescriptor} from "v4-periphery/test/shared/Deploy.sol";
import {PositionDescriptor} from "lib/v4-periphery/src/PositionDescriptor.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";

contract TestSportsBetting is Test, Deployers, PosmTestSetup  {
     using CurrencyLibrary for Currency;

    uint256 public storedBetCost; // State variable to store bet cost
    MockERC20 tokenUsdc;
    MockERC20 tokenUsdt;

    PoolId poolId;
    uint256 tokenId;
    Currency tokenUsdcCurrency;
    Currency tokenUsdtCurrency;
    address owner = address(this);


    // Sportsbetting hook
    SportsBetting sportsBettingHook;
    bytes hookData = abi.encode(address(this));

	// PositionManager NFT
	IPositionManager posm;
    PoolKey poolKey;

    function setUp() public {
        
        // Deploy PoolManager and Router contracts
        deployFreshManagerAndRouters();
    
        // Deploy an instance of PositionManager
	    deployPosm(manager);
        //posm = lpm;

    


        // Create 2 ERC-20 test tokens
        tokenUsdc = new MockERC20("Test Token 0", "TEST0", 18);
        tokenUsdt = new MockERC20("Test Token 1", "TEST1", 18);
        tokenUsdcCurrency = Currency.wrap(address(tokenUsdc));
        tokenUsdtCurrency = Currency.wrap(address(tokenUsdt));
        console.log("Address token 0: ", address(tokenUsdc));
        console.log("Address token 1: ", address(tokenUsdt));

        // Mint a bunch of TOKEN to ourselves and to address(1)
        tokenUsdc.mint(address(this), 1000 ether);
        tokenUsdc.mint(address(1), 1000 ether);
        tokenUsdt.mint(address(this), 1000 ether);
        tokenUsdt.mint(address(1), 1000 ether);
        console.log("Tokens 0 and 1 has been minted!");

        tokenUsdc.approve(address(this), type(uint256).max);
        tokenUsdt.approve(address(this), type(uint256).max);

        approvePosmCurrency(tokenUsdcCurrency);
        approvePosmCurrency(tokenUsdtCurrency);

        // Deploy hook to an address that has the proper flags set
        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG 
        );
        deployCodeTo(
            "SportsBetting.sol",
             //abi.encode(manager, tokenUsdc, tokenUsdt, "Points Token", "TEST_POINTS"),
             abi.encode(manager, address(this), 10, lpm, tokenUsdc, tokenUsdt, "Points Token", "TEST_POINTS"),
            address(flags)
        );


          

        // Deploy our hook
        sportsBettingHook = SportsBetting(address(flags));
        


        // // Create the pool
        poolKey  = PoolKey(tokenUsdtCurrency, tokenUsdcCurrency, 3000, 60, IHooks(sportsBettingHook));
        
        
        (key, ) = initPool(
			tokenUsdtCurrency,
			tokenUsdcCurrency,
			sportsBettingHook, 
			3000,
			SQRT_PRICE_1_1
		);
        

    }

     function testPlaceBet() public {
            uint256 amountIn = 200 * 1e18; // 20 USDC
            //uint256 amountIn = 20; // 20 USDC

            // Approve the contract to spend USDC
            tokenUsdc.approve(address(sportsBettingHook), amountIn);

            // console.log("Approved USDC for betting contract");
            // console.log("Who is sending the LP:" , msg.sender);
            // console.log("Address SwapRouter:", address(swapRouter));
            // console.log("Address modifyLiquidityRouter:", address(modifyLiquidityRouter));


            // Call placeBet()
            sportsBettingHook.placeBet(SportsBetting.Outcome.LIV_WINS, amountIn);
            
            console.log("Bet amount:", sportsBettingHook.betAmount());
            console.log("Initial cost:", sportsBettingHook.initialCost());   
            console.log("New liquidity:", sportsBettingHook.newLiquidity());   
            console.log("New cost:", sportsBettingHook.newCost());   
            
            // Retrieve bet cost from public state variable
            storedBetCost = sportsBettingHook.betCost();

            // Log bet cost
            console.log("Bet cost calculated by LMSR:", storedBetCost, "USDC");

            // Assertions to ensure `betCost` updated correctly
            assertGt(storedBetCost, 0, "Bet cost should be greater than zero");


        }


        // Add liquidity after user places bet
        function test_AddRemoveLiquidity() public {

            // First we add liquidity
            console.log("Adding Liquidity", "USDC and USDT...");
        
            bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));
            bytes[] memory params = new bytes[](2);

            uint256 balanceToken0BeforeThis = tokenUsdt.balanceOf(address(this));
            uint256 balanceToken1BeforeThis = tokenUsdc.balanceOf(address(this));
            console.log("balanceToken0BeforeThis:", balanceToken0BeforeThis);
             console.log("balanceToken1BeforeThis:", balanceToken1BeforeThis);

            int24 tickLower = -60;
            int24 tickUpper = 60;
            uint128 amountToAdd = 1 ether;
            uint128 amount0Max = amountToAdd;
            uint128 amount1Max = 10000000000000000000;
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

            params[1] = abi.encode(tokenUsdtCurrency, tokenUsdcCurrency);

            lpm.modifyLiquidities{value: valueToPass}(
                abi.encode(actions, params),
                deadline
            );

            //console.log("TokenID:" , lpm.positionInfo(1));

            uint128 currentLiquidity = lpm.getPositionLiquidity(1);
            console.log("currentLiquidity:", currentLiquidity);



            uint256 balanceToken0AfterThis = tokenUsdt.balanceOf(address(this));
            uint256 balanceToken1AfterThis = tokenUsdc.balanceOf(address(this));
            console.log("balanceToken0AfterThis:", balanceToken0AfterThis);
            console.log("balanceToken1AfterThis:", balanceToken1AfterThis);

            uint256 myLiquidity = lpm.getPositionLiquidity(1);
            console.log("myLiquidity:", myLiquidity);

            // Then we test the removal of its liquidity
            console.log("Removing Liquidity", "USDC and USDT...");

            bytes memory actions2 = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR));
            bytes[] memory params2 = new bytes[](2);

          
              
            // Roll to end of match
            vm.roll(block.number + 10); // Move forward 10 blocks
            console.log("Block number: ", block.number);

            
            uint256 amount0Min = 0;
            uint256 amount1Min = 0;
            uint256 liquidity = myLiquidity;
            
            params2[0] = abi.encode(1, liquidity, amount0Min, amount1Min, hookData);

          
            params2[1] = abi.encode(tokenUsdtCurrency, tokenUsdcCurrency, address(this));

            uint256 deadline2 = block.timestamp + 60;

            uint256 valueToPass2 =  0;

            lpm.modifyLiquidities{value: valueToPass2}(
                abi.encode(actions2, params2),
                deadline2
            );

            uint256 balanceToken0FinalThis = tokenUsdt.balanceOf(address(this));
            uint256 balanceToken1FinalThis = tokenUsdc.balanceOf(address(this));
            console.log("balanceToken0FinalThis:", balanceToken0FinalThis);
            console.log("balanceToken1FinalThis:", balanceToken1FinalThis);

 
        }


}