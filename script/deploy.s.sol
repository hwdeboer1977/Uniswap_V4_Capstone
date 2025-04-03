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
import {TickMath} from "v4-core/libraries/TickMath.sol";

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

    PoolKey internal storedPoolKeyWin;
    PoolKey internal storedPoolKeyDraw;
    PoolKey internal storedPoolKeyLose;

    // Betting amounts
    int256 amountUser1 = 200e18;
    int256 amountUser2 = 100e18;
    int256 amountUser3 = 150e18;

    bool zeroForOneWinDummy;
    bool zeroForOneDrawDummy;
    bool zeroForOneLoseDummy;

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

        console.log("USDC address: ", address(usdcToken));
        console.log("WIN address: ", address(winToken));

        // Initialize the pool
        // Starting price of the pool, in sqrtPriceX96
        uint160 startingPrice = 79228162514264337593543950336; // floor(sqrt(1) * 2^96)

         int24 tickSpacing = 60;
        // 1st pool: WIN/USDC
        // Sort the tokens in correct order
         (MockERC20 t0, MockERC20 t1) = sortTokens(usdcToken, winToken, 0); // 0 = pool WIN
        
        PoolKey memory poolKeyWin =
            PoolKey(Currency.wrap(address(t0)), Currency.wrap(address(t1)), 3000, tickSpacing, IHooks(sportsBettingHook));
        manager.initialize(poolKeyWin, startingPrice);
         storedPoolKeyWin = poolKeyWin; // Store for later reuse

        // 2nd pool: DRAW/USDC
        // Sort the tokens in correct order
       (MockERC20 t2, MockERC20 t3) = sortTokens(usdcToken, drawToken, 1); // 1 = pool DRAW
        
        PoolKey memory poolKeyDraw =
            PoolKey(Currency.wrap(address(t2)), Currency.wrap(address(t3)), 3000, tickSpacing, IHooks(sportsBettingHook));
        manager.initialize(poolKeyDraw, startingPrice);
         storedPoolKeyDraw = poolKeyDraw; // Store for later reuse

        // 3rd pool: LOSE/USDC
        // Sort the tokens in correct order
          (MockERC20 t4, MockERC20 t5) = sortTokens(usdcToken, loseToken, 2); // // 2 = pool Lose
        
        PoolKey memory poolKeyLose =
            PoolKey(Currency.wrap(address(t4)), Currency.wrap(address(t5)), 3000, tickSpacing, IHooks(sportsBettingHook));
        manager.initialize(poolKeyLose, startingPrice);
        storedPoolKeyLose = poolKeyLose; // Store for later reuse


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
        sportsBettingHook.addLiquidity(storedPoolKeyWin, 1000 ether);
        sportsBettingHook.addLiquidity(storedPoolKeyDraw, 1000 ether);
        sportsBettingHook.addLiquidity(storedPoolKeyLose, 1000 ether);
       
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

        
        /////////////////////////// SOME CODE FOR TESTING BELOW //////////////////////////////////
        // Settings swap 
        // PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
        //     takeClaims: false,
        //     settleUsingBurn: false
        // });

        // // Open the betting market (runs for 7 days)
        // sportsBettingHook.openBetMarket(block.timestamp, block.timestamp + 7 days);

          
        //      vm.stopBroadcast();


        // // Sample user addresses for placing bets
        // address user1 = address(0x1111); 

        // // --- User 1 bets on WIN outcome ---
        // vm.startPrank(user1);

        // usdcToken.mint(address(user1), 1_000 ether);

        // // Approve tokens
        // IERC20Minimal(Currency.unwrap(currencyUsdc)).approve(address(swapRouter), type(uint256).max);
        // IERC20Minimal(Currency.unwrap(currencyWin)).approve(address(swapRouter), type(uint256).max);

        // // Check balances before swap
        // console.log("Balance USDC user 1, before swap :", usdcToken.balanceOf(address(user1))/1e18);
        // console.log("Balance WIN user 1, before swap :", winToken.balanceOf(address(user1))/1e18);
        // console.log(zeroForOneWinDummy);
        // // Swap token 
        // swapRouter.swap(
        //     storedPoolKeyWin,
        //     IPoolManager.SwapParams({
        //         zeroForOne: zeroForOneWinDummy,
        //         amountSpecified: amountUser1,
        //         sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        //     }),
        //     settings,
        //     abi.encode(user1)
        //     //ZERO_BYTES
        // );

        // // Check balances after swap
        // console.log("Balance USDC user 1, after swap :", usdcToken.balanceOf(address(user1))/1e18);
        // console.log("Balance WIN user 1, after swap :", winToken.balanceOf(address(user1))/1e18);

        // vm.stopPrank();


        // vm.startPrank(deployer);
        // sportsBettingHook.closeBetMarket();
        // vm.stopPrank();
        
        // vm.startPrank(deployer);
        // sportsBettingHook.resolveMarket(1); // 1 = WIN, 2 = LOSE, 3 = DRAW
        // vm.stopPrank();

        // // --- Payout: user1 claims winnings ---
        // uint256 user1ClaimBefore = IERC20Minimal(Currency.unwrap(currencyUsdc)).balanceOf(user1);
        // console.log("user1ClaimBefore: ", user1ClaimBefore);
        // sportsBettingHook.claimWinnings(storedPoolKeyWin, user1);
        // uint256 user1ClaimAfter = IERC20Minimal(Currency.unwrap(currencyUsdc)).balanceOf(user1);
        // console.log("user1ClaimAfter: ", user1ClaimAfter);
 
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
        MockERC20 tokenInput1,
        int16 poolNumber
    ) internal returns (MockERC20 token0, MockERC20 token1) {
        if (uint160(address(tokenInput0)) < uint160(address(tokenInput1))) {
            console.log("Token 0 is first token");
            if (poolNumber == 0) {
                zeroForOneWinDummy = true;
            } else if (poolNumber == 1) {
                zeroForOneDrawDummy = true;
            } else if (poolNumber == 2) {
                zeroForOneLoseDummy = true;
            }
            token0 = tokenInput0;
            token1 = tokenInput1;
        } else {
             console.log("Token 1 is first token");
            if (poolNumber == 0) {
                zeroForOneWinDummy = false;
            } else if (poolNumber == 1) {
                zeroForOneDrawDummy = false;
            } else if (poolNumber == 2) {
                zeroForOneLoseDummy = false;
            }
            token0 = tokenInput1;
            token1 = tokenInput0;
        }
    }

    


}