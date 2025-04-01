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

// My V4 SportsBettingHook is created with Foundry (WSL)
// Frontend is created with React

// Use following setup to test hook and frontend interaction

// 1. anvil --host 0.0.0.0 (separate terminal)

// 2. Run deploy script in Foundry with: 
// forge script script/deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
// Get contract address from the deployed Hook and use it in frontend
// Test Hook: cast call 0x7Faa4518bA4B1018976F007094ae304AF4D24888 "getMarketState()" --rpc-url http://127.0.0.1:8545


// /**
//  * Deploys an instance of the Uniswap V4 Pool Manager and the Bond Hook.
//  * @usage forge script script/Development.sol --fork-url $LOCAL_RPC --broadcast --private-key $LOCAL_DEPLOYER_PRIVATE_KEY
//  */
contract DeployManagerAndHook is Script, Deployers {

    using CurrencyLibrary for Currency;
    SportsBettingHook hook;

    // Pool keys for each outcome pool
    PoolKey public keyWin;
    PoolKey public keyLose;
    PoolKey public keyDraw;

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

         // Deploy the manager and routers
         deployFreshManagerAndRouters();

        address CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
        IPoolManager manager;

        vm.startBroadcast(deployerPrivateKey);
        //vm.broadcast(); // Sends with deployer address
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
        hook = SportsBettingHook(hookAddress);
   

        console.log("Address this: ", address(this));
        console.log("Address sportsBettingHook: ", address(sportsBettingHook));
       
        
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

       


        // Sort the currency in the correct order for intializing pools
        if (Currency.unwrap(currencyUsdc) < Currency.unwrap(currencyWin)) {
           (keyWin, ) = initPool(currencyUsdc, currencyWin, hook, 3000, SQRT_PRICE_1_1);
           console.log("currentWin is 2nd token");
        } else {
           (keyWin, ) = initPool(currencyWin, currencyUsdc, hook, 3000, SQRT_PRICE_1_1);
           console.log("currentWin is 1st token");
        }

        if (Currency.unwrap(currencyUsdc) < Currency.unwrap(currencyLose)) {
           (keyLose, ) = initPool(currencyUsdc, currencyLose, hook, 3000, SQRT_PRICE_1_1);
           console.log("currencyLose is 2nd token");
        } else {
           (keyLose, ) = initPool(currencyLose, currencyUsdc, hook, 3000, SQRT_PRICE_1_1);
           console.log("currencyLose is 1st token");
        }

       if (Currency.unwrap(currencyUsdc) < Currency.unwrap(currencyDraw)) {
           (keyDraw, ) = initPool(currencyUsdc, currencyDraw, hook, 3000, SQRT_PRICE_1_1);
           console.log("currencyDraw is 2nd token");
        } else {
           (keyDraw, ) = initPool(currencyDraw, currencyUsdc, hook, 3000, SQRT_PRICE_1_1);
           console.log("currencyDraw is 1st token");
        }


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


        // Check token addresses 
        address tokenUsdc = Currency.unwrap(currencyUsdc);
        address tokenWin = Currency.unwrap(currencyWin);
        address tokenLose = Currency.unwrap(currencyLose);
        address tokenDraw = Currency.unwrap(currencyDraw);
        console.log("Address token USDC: ", tokenUsdc);
        console.log("Address token WIN: ", tokenWin);
        console.log("Address token LOSE: ", tokenLose);
        console.log("Address token DRAW: ", tokenDraw);


        // Check addresses 
        console.log("Address this: ", address(this));
        console.log("Address hook:", address(hook));
        console.log("Address manager:", address(manager));


        console.log("Balance USDC of deployer before adding liq :", usdcToken.balanceOf(address(deployer)));
        console.log("Balance USDC of poolManager before adding liq :", usdcToken.balanceOf(address(manager))/1e18);

        

        // Add liquidity to 3 outcome pools
        hook.addLiquidity(keyWin, 1000e18);
         hook.addLiquidity(keyLose, 1000e18);
         hook.addLiquidity(keyDraw, 1000e18);

        

        console.log("Balance USDC of deployer after adding liq :", usdcToken.balanceOf(address(deployer)));
        console.log("Balance USDC of poolManager after adding liq :", usdcToken.balanceOf(address(manager))/1e18);
        console.log("Balance WIN of poolManager after adding liq :", winToken.balanceOf(address(manager))/1e18);
        console.log("Balance LOSE of poolManager after adding liq :", loseToken.balanceOf(address(manager))/1e18);
        console.log("Balance DRAW of poolManager after adding liq :", drawToken.balanceOf(address(manager))/1e18);


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

         vm.stopBroadcast();

    }

    // -----------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------
    function deployPoolManager() internal returns (IPoolManager) {
        return IPoolManager(address(new PoolManager(address(0))));
    }
}