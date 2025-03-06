// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Script} from "forge-std/Script.sol";
import {BettingPoolDeployer} from "../src/BettingPoolDeployer.sol";

// DEPLOY TOKENS WITH:

// forge script script/DeployPools.s.sol --rpc-url sepolia --broadcast --private-key $PRIVATE_KEY



contract DeployPools is Script {
    // Uniswap V4 Sepolia addresses
    address constant POOL_MANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
    address constant POSITION_MANAGER = 0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4;
   
    // Replace with your deployed token addresses
    address livWin = 0xF3D3667Ca3E38F1aD7587c8e5B99dCD15EA56f64;
    address livDraw = 0x6E47e77a102cA69b4B3cdFd2c677E334bd301455;
    address livLose = 0xd0dfe36E01432C29adF484Ec10Fd5e7c9e797B43;
    address testUSDC = 0x89ddB3244030A643d22CAc6874f34f7cac85CaE7;

    function run() external {
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy BettingPoolDeployer
        BettingPoolDeployer bettingPoolDeployer = new BettingPoolDeployer(
            POOL_MANAGER,
            testUSDC,
            livWin,
            livDraw,
            livLose
        );

        console.log("BettingPoolDeployer deployed at:", address(bettingPoolDeployer));

        // ✅ Call createPools()
        bettingPoolDeployer.createPools();
        console.log("Pools initialized!");

        vm.stopBroadcast();
   

    //      IPoolManager poolManager = IPoolManager(POOL_MANAGER);

    // //     Create Pools (3000 basis points = 0.3% Fee Tier)
    //      address poolLIVWIN = poolManager.createPool(livWin, testUSDC, 3000);
    // //     address poolLIVDRAW = poolManager.createPool(livDraw, WETH, 3000);
    // //     address poolLIVLOSE = poolManager.createPool(livLose, WETH, 3000);

    //      console.log("LIV_WIN Pool:", poolLIVWIN);
    //     console.log("LIV_DRAW Pool:", poolLIVDRAW);
    //     console.log("LIV_LOSE Pool:", poolLIVLOSE);

    //     // ✅ Initialize Pools with an arbitrary price ratio (1:1 for now)
    //     initializePool(poolLIVWIN, 1 ether);
    //     initializePool(poolLIVDRAW, 1 ether);
    //     initializePool(poolLIVLOSE, 1 ether);

    //     // ✅ Provide initial liquidity
    //     addLiquidity(poolLIVWIN, 100 ether, 1 ether);
    //     addLiquidity(poolLIVDRAW, 100 ether, 1 ether);
    //     addLiquidity(poolLIVLOSE, 100 ether, 1 ether);

    //     vm.stopBroadcast();
    // }

    // function initializePool(address pool, uint160 sqrtPriceX96) internal {
    //     IPoolManager(pool).initialize(sqrtPriceX96);
    // }

    // function addLiquidity(address pool, uint256 tokenAmount, uint256 ethAmount) internal {
    //     IERC20(livWin).approve(POSITION_MANAGER, tokenAmount);
    //     IERC20(WETH).approve(POSITION_MANAGER, ethAmount);
    //     IPoolManager(pool).modifyLiquidity(
    //         address(this),
    //         tokenAmount,
    //         ethAmount
    //     );
     }
}
