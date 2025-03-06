// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "lib/v4-core/src/types/Currency.sol";
import {Currency, CurrencyLibrary} from "lib/v4-core/src/types/Currency.sol";
import {PoolKey} from "lib/v4-core/src/types/PoolKey.sol";
import {IHooks} from "lib/v4-core/src/interfaces/IHooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// forge script script/AddLiquidity.s.sol --rpc-url sepolia --broadcast

contract AddLiquidity is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get addresses from .env
        IPoolManager poolManager = IPoolManager(vm.envAddress("POOL_MANAGER"));
        IERC20 usdc = IERC20(vm.envAddress("TEST_USDC"));
        IERC20 livWin = IERC20(vm.envAddress("LIV_WIN"));
        IERC20 livDraw = IERC20(vm.envAddress("LIV_DRAW"));
        IERC20 livLose = IERC20(vm.envAddress("LIV_LOSE"));

        uint256 initialUSDC = 1_000 * 10**18; // 1000 USDC (assuming 6 decimals)
        uint256 initialLIV_WIN = 1_600 * 10**18; // 1600 LIV_WIN (18 decimals)
        uint256 initialLIV_DRAW = 2_200 * 10**18; // 2200 LIV_DRAW
        uint256 initialLIV_LOSE = 3_200 * 10**18; // 3200 LIV_LOSE

        // Approve tokens for PoolManager
        usdc.approve(address(poolManager), initialUSDC * 3); // Approve enough USDC for all pools
        livWin.approve(address(poolManager), initialLIV_WIN);
        livDraw.approve(address(poolManager), initialLIV_DRAW);
        livLose.approve(address(poolManager), initialLIV_LOSE);


        // Define Hooks (None for now)
        IHooks noHooks = IHooks(address(0));

        // Define PoolKeys
        Currency currency0Win = Currency.wrap(address(usdc));
        Currency currency1Win = Currency.wrap(address(livWin));

        PoolKey memory poolWinKey = PoolKey({
            currency0: currency0Win,
            currency1: currency1Win,
            fee: 3000,
            tickSpacing: 60,
            hooks: noHooks
        });

        // PoolKey memory poolDrawKey = PoolKey({
        //     currency0: currency0Draw,
        //     currency1: currency1Draw,
        //     fee: 3000,
        //     tickSpacing: 60,
        //     hooks: noHooks
        // });

        // PoolKey memory poolLoseKey = PoolKey({
        //     currency0: currency0Lose,
        //     currency1: currency1Lose,
        //     fee: 3000,
        //     tickSpacing: 60,
        //     hooks: noHooks
        // });

        // Define ModifyLiquidityParams
        int24 tickLower = -887272; // Set wide range (full range liquidity)
        int24 tickUpper = 887272;
        bytes32 salt = keccak256("LIV_POOL_SALT"); // Optional unique identifier

        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: int256(initialLIV_WIN), // Adjust based on token
            salt: salt
        });

        // Add Liquidity to Each Pool
        poolManager.modifyLiquidity(poolWinKey, params, "");
        // params.liquidityDelta = int256(initialLIV_DRAW);
        // poolManager.modifyLiquidity(poolDrawKey, params, "");
        // params.liquidityDelta = int256(initialLIV_LOSE);
        // poolManager.modifyLiquidity(poolLoseKey, params, "");

        // console.log("Liquidity added to all pools!");

        vm.stopBroadcast();
    }
}
