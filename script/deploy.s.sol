// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {PoolManager} from "lib/v4-periphery/lib/v4-core/src/PoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {SportsBettingHook} from "../src/SportsBettingHook.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";


// My V4 SportsBettingHook is created with Foundry (WSL)
// Frontend is created with React

// Use following setup to test hook and frontend interaction

// 1. anvil --host 0.0.0.0 (separate terminal)

// 2. Run deploy script in Foundry with: 
// forge script script/deploy.s.sol --rpc-url  http://localhost:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
// Get contract address from the deployed Hook and use it in frontend
// Test Hook: cast call 0xDbcB8DFC22DFE4A4dfc1156D4A1e070fAf418888 "getMarketState()" --rpc-url http://localhost:8545


// /**
//  * Deploys an instance of the Uniswap V4 Pool Manager and the Bond Hook.
//  * @usage forge script script/Development.sol --fork-url $LOCAL_RPC --broadcast --private-key $LOCAL_DEPLOYER_PRIVATE_KEY
//  */
contract DeployManagerAndHook is Script {

    using CurrencyLibrary for Currency;

    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
    IPoolManager manager;
    PoolSwapTest swapRouter;
 

    // Pool keys for each outcome pool
    PoolKey public PoolKeyWin;
    PoolKey public PoolKeyDraw;
    PoolKey public PoolKeyLose;

    // Currency types (ERC20 wrapped into Uniswap's Currency type)
    Currency public currencyUsdc; // USDC
    Currency public currencyWin; // WIN
    Currency public currencyLose; // LOSE
    Currency public currencyDraw; // DRAW

     

    function run() external {
         // Load the private key from the environment
         
         uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
         console.log("deployerPrivateKey:", deployerPrivateKey);
         address deployer = vm.addr(deployerPrivateKey);
         console.log("address _deployer:", deployer); 


         vm.startBroadcast(deployerPrivateKey);

         // Deploy the PoolManager
         manager = deployPoolManager();
         
         console.log("Address poolmanager: ",address(manager));
      

        // hook contracts must have specific flags encoded in the address
        uint160 permissions = uint160(
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                    Hooks.BEFORE_SWAP_FLAG |
                    Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
            );


        // Mine a salt that will produce a hook address with the correct permissions
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, permissions, type(SportsBettingHook).creationCode, abi.encode(address(manager)));
        

        //vm.broadcast(); // Sends with deployer address
        // Deploying the hook
        SportsBettingHook sportsBettingHook = new SportsBettingHook{salt: salt}(manager);
        require(address(sportsBettingHook) == hookAddress, "hook address mismatch");
       
        console.log("Address this: ", address(this));
        console.log("Address sportsBettingHook: ", address(sportsBettingHook));
     

        // Deploy swapRouter
        (swapRouter) = deployRouters(manager);
        console.log("Address swapRouter: ", address(swapRouter));
      

       
        
        // Manually deploy mock tokens for the test
        MockERC20 usdcToken = new MockERC20("USDC", "USDC", 18);
        usdcToken.mint(address(deployer), 1_000_000 ether);
        currencyUsdc = Currency.wrap(address(usdcToken));

        MockERC20 winToken = new MockERC20("WIN", "WIN", 18);
        winToken.mint(address(deployer), 1_000_000 ether);
        currencyWin = Currency.wrap(address(winToken));

        MockERC20 loseToken = new MockERC20("LOSE", "LOSE", 18);
        loseToken.mint(address(deployer), 1_000_000 ether);
        currencyLose = Currency.wrap(address(loseToken));

        MockERC20 drawToken = new MockERC20("DRAW", "DRAW", 18);
        drawToken.mint(address(deployer), 1_000_000 ether);
        currencyDraw = Currency.wrap(address(drawToken));

        MockERC20 token0;
        MockERC20 token1;
        


        // Initialize the pool
        // Starting price of the pool, in sqrtPriceX96
        uint160 startingPrice = 79228162514264337593543950336; // floor(sqrt(1) * 2^96)

         int24 tickSpacing = 60;
        // 1st pool: WIN/USDC
        // Sort the tokens in correct order
        (token0, token1) = sortTokens(usdcToken, winToken);
        
        PoolKey memory poolKeyWin =
            PoolKey(Currency.wrap(address(token0)), Currency.wrap(address(token1)), 3000, tickSpacing, IHooks(sportsBettingHook));
        manager.initialize(poolKeyWin, startingPrice);

        // 2nd pool: DRAW/USDC
        // Sort the tokens in correct order
        (token0, token1) = sortTokens(usdcToken, drawToken);
        
        PoolKey memory poolKeyDraw =
            PoolKey(Currency.wrap(address(token0)), Currency.wrap(address(token1)), 3000, tickSpacing, IHooks(sportsBettingHook));
        manager.initialize(poolKeyDraw, startingPrice);

        // 3rd pool: LOSE/USDC
        // Sort the tokens in correct order
        (token0, token1) = sortTokens(usdcToken, loseToken);
        
        PoolKey memory poolKeyLose =
            PoolKey(Currency.wrap(address(token0)), Currency.wrap(address(token1)), 3000, tickSpacing, IHooks(sportsBettingHook));
        manager.initialize(poolKeyLose, startingPrice);


        // Approve tokens to the hook so it can add liquidity via Hook
        IERC20Minimal(Currency.unwrap(currencyUsdc)).approve(
            hookAddress,
            1_000_000 ether
        );
        IERC20Minimal(Currency.unwrap(currencyWin)).approve(
            hookAddress,
            1_000_000 ether
        );
        IERC20Minimal(Currency.unwrap(currencyDraw)).approve(
            hookAddress,
            1_000_000 ether
        );
        IERC20Minimal(Currency.unwrap(currencyLose)).approve(
            hookAddress,
            1_000_000 ether
        );

        
       
        console.log("Balance USDC PM, before: ", usdcToken.balanceOf(address(manager))/1e18);
        console.log("Balance WIN PM, before: ", winToken.balanceOf(address(manager))/1e18);
        console.log("Balance DRAW PM, before: ", drawToken.balanceOf(address(manager))/1e18);
        console.log("Balance WIN PM, before: ", loseToken.balanceOf(address(manager))/1e18);

        //  Add liquidity to SportsBettingHook
        sportsBettingHook.addLiquidity(poolKeyWin, 1000 ether);
        sportsBettingHook.addLiquidity(poolKeyDraw, 1000 ether);
        sportsBettingHook.addLiquidity(poolKeyLose, 1000 ether);
       
        console.log("Balance USDC PM, after: ", usdcToken.balanceOf(address(manager))/1e18);
        console.log("Balance WIN PM, after: ", winToken.balanceOf(address(manager))/1e18);
        console.log("Balance DRAW PM, after: ", drawToken.balanceOf(address(manager))/1e18);
        console.log("Balance WIN PM, after: ", loseToken.balanceOf(address(manager))/1e18);

        // Map each pool key to its associated outcome
        sportsBettingHook.registerPools(poolKeyWin, poolKeyDraw, poolKeyLose);

        
        // Set the odds before the match starts
        // For now, we are still using the initial liquidity at 0, so prob = 1/3

        // Suppose a bookmaker has the following odds: 1.60 (160), 4.23 (423), 5.30 (530)
        // The function setInitialLiquidityFromOdds then sets the correct amounts of liquidity
        // for all 3 outcomes such that we have the same odds as the bookmakers
        sportsBettingHook.setInitialLiquidityFromOdds(160, 423, 530);

        // Double check the outcome probablities (should be roughly the inverse of the odds above)
        sportsBettingHook.getOutcomeProbabilities();

         vm.stopBroadcast();




    //     // Sort the currency in the correct order for intializing pools
    //     if (Currency.unwrap(currencyUsdc) < Currency.unwrap(currencyWin)) {
    //        (keyWin, ) = initPool(currencyUsdc, currencyWin, hook, 3000, SQRT_PRICE_1_1);
    //        console.log("currentWin is 2nd token");
    //     } else {
    //        (keyWin, ) = initPool(currencyWin, currencyUsdc, hook, 3000, SQRT_PRICE_1_1);
    //        console.log("currentWin is 1st token");
    //     }

    //     if (Currency.unwrap(currencyUsdc) < Currency.unwrap(currencyLose)) {
    //        (keyLose, ) = initPool(currencyUsdc, currencyLose, hook, 3000, SQRT_PRICE_1_1);
    //        console.log("currencyLose is 2nd token");
    //     } else {
    //        (keyLose, ) = initPool(currencyLose, currencyUsdc, hook, 3000, SQRT_PRICE_1_1);
    //        console.log("currencyLose is 1st token");
    //     }

    //    if (Currency.unwrap(currencyUsdc) < Currency.unwrap(currencyDraw)) {
    //        (keyDraw, ) = initPool(currencyUsdc, currencyDraw, hook, 3000, SQRT_PRICE_1_1);
    //        console.log("currencyDraw is 2nd token");
    //     } else {
    //        (keyDraw, ) = initPool(currencyDraw, currencyUsdc, hook, 3000, SQRT_PRICE_1_1);
    //        console.log("currencyDraw is 1st token");
    //     }


    //     // Approve tokens to the hook so it can add liquidity
    //     IERC20Minimal(Currency.unwrap(currencyUsdc)).approve(
    //         hookAddress,
    //         1_000_000 ether
    //     );
    //     IERC20Minimal(Currency.unwrap(currencyWin)).approve(
    //         hookAddress,
    //         1_000_000 ether
    //     );

    //     IERC20Minimal(Currency.unwrap(currencyLose)).approve(
    //         hookAddress,
    //         1_000_000 ether
    //     );

    //     IERC20Minimal(Currency.unwrap(currencyDraw)).approve(
    //         hookAddress,
    //         1_000_000 ether
    //     );


    //     // Check token addresses 
    //     address tokenUsdc = Currency.unwrap(currencyUsdc);
    //     address tokenWin = Currency.unwrap(currencyWin);
    //     address tokenLose = Currency.unwrap(currencyLose);
    //     address tokenDraw = Currency.unwrap(currencyDraw);
    //     console.log("Address token USDC: ", tokenUsdc);
    //     console.log("Address token WIN: ", tokenWin);
    //     console.log("Address token LOSE: ", tokenLose);
    //     console.log("Address token DRAW: ", tokenDraw);


    //     // Check addresses 
    //     console.log("Address this: ", address(this));
    //     console.log("Address hook:", address(hook));
    //     console.log("Address manager:", address(poolManager));


    //     console.log("Balance USDC of deployer before adding liq :", usdcToken.balanceOf(address(deployer))/1e18);
    //     console.log("Balance USDC of poolManager before adding liq :", usdcToken.balanceOf(address(poolManager))/1e18);

        

    //     // Add liquidity to 3 outcome pools
    //     hook.addLiquidity(keyWin, 1000e18);
    //     hook.addLiquidity(keyDraw, 1000e18);
    //      hook.addLiquidity(keyLose, 1000e18);
         

        

    //     console.log("Balance USDC of deployer after adding liq :", usdcToken.balanceOf(address(deployer)));
    //     console.log("Balance USDC of poolManager after adding liq :", usdcToken.balanceOf(address(manager))/1e18);
    //     console.log("Balance WIN of poolManager after adding liq :", winToken.balanceOf(address(manager))/1e18);
    //     console.log("Balance LOSE of poolManager after adding liq :", loseToken.balanceOf(address(manager))/1e18);
    //     console.log("Balance DRAW of poolManager after adding liq :", drawToken.balanceOf(address(manager))/1e18);


    //     // Map each pool key to its associated outcome
    //     hook.registerPools(keyWin, keyDraw, keyLose);

        
    //     // Set the odds before the match starts
    //     // For now, we are still using the initial liquidity at 0, so prob = 1/3

    //     // Suppose a bookmaker has the following odds: 1.60 (160), 4.23 (423), 5.30 (530)
    //     // The function setInitialLiquidityFromOdds then sets the correct amounts of liquidity
    //     // for all 3 outcomes such that we have the same odds as the bookmakers
    //     hook.setInitialLiquidityFromOdds(160, 423, 530);

    //     // Double check the outcome probablities (should be roughly the inverse of the odds above)
    //     hook.getOutcomeProbabilities();

        // vm.stopBroadcast();

    }

    // -----------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------
    // 1. Deploy PoolManager
    function deployPoolManager() internal returns (IPoolManager) {
        return IPoolManager(address(new PoolManager(address(0))));
    }

    // 2. Deploy Swap Router
    function deployRouters(IPoolManager _manager)
        internal
        returns (PoolSwapTest _swapRouter)
    {
        _swapRouter = new PoolSwapTest(_manager);
    }

    // Function to sort the tokens for different liquidity pools
    function sortTokens(
        MockERC20 tokenInput0,
        MockERC20 tokenInput1
    ) internal pure returns (MockERC20 token0, MockERC20 token1) {
        if (uint160(address(tokenInput0)) < uint160(address(tokenInput1))) {
            token0 = tokenInput0;
            token1 = tokenInput1;
        } else {
            token0 = tokenInput1;
            token1 = tokenInput0;
        }
    }


}