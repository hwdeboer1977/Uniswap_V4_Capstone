// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {PoolManager} from "lib/v4-periphery/lib/v4-core/src/PoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {SportsBettingHook} from "../src/SportsBettingHook.sol";

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
    function run() external {
    //     // Load the private key from the environment
         
         uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
         console.log("deployerPrivateKey:", deployerPrivateKey);
         address _deployer = vm.addr(deployerPrivateKey);
         console.log("address _deployer:", _deployer); 

         // 1. Deploy the manager and routers
         deployFreshManagerAndRouters();

        address CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
        IPoolManager manager;

        vm.broadcast();
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


        vm.broadcast();
        SportsBettingHook sportsBettingHook = new SportsBettingHook{salt: salt}(manager);
        require(address(sportsBettingHook) == hookAddress, "CounterScript: hook address mismatch");
        console.log("Address sportsBettingHook: ", address(sportsBettingHook));

    }

    // -----------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------
    function deployPoolManager() internal returns (IPoolManager) {
        return IPoolManager(address(new PoolManager(address(0))));
    }
}