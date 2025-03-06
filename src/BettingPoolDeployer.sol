// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "lib/v4-core/src/types/Currency.sol";
import {IHooks} from "lib/v4-core/src/interfaces/IHooks.sol"; 
import {PoolKey} from "lib/v4-core/src/types/PoolKey.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BettingPoolDeployer is Ownable {

    IPoolManager public manager;
    Currency public usdc;
    Currency public livWin;
    Currency public livDraw;
    Currency public livLose;



    constructor(
        address _manager,
        address _usdc,
        address _livWin,
        address _livDraw,
        address _livLose
    ) Ownable(msg.sender) {
        manager = IPoolManager(_manager);
        usdc = Currency.wrap(_usdc);
        livWin = Currency.wrap(_livWin);
        livDraw = Currency.wrap(_livDraw);
        livLose = Currency.wrap(_livLose);
    }
 
     function createPools() external onlyOwner {
   

        // ✅ Explicitly cast address(0) to IHooks
        IHooks noHooks = IHooks(address(0));

        PoolKey memory poolWinKey = PoolKey({
            currency0: usdc,
            currency1: livWin,
            fee: 3000,
            tickSpacing: 60,
            hooks: noHooks
        });

         // require(poolWin == address(0), "Pools already created");

         uint160 sqrtPriceX96 = 79228162514264337593543950336; // 1:1 initial price
         manager.initialize(poolWinKey, sqrtPriceX96);
     }

    // function createPools() external onlyOwner {
    //   PoolKey memory poolWin = PoolKey({
    //         currency0: CurrencyLibrary.toCurrency(address(usdc)) < CurrencyLibrary.toCurrency(address(livWin)) ? usdc : livWin,
    //         currency1: CurrencyLibrary.toCurrency(address(usdc)) > CurrencyLibrary.toCurrency(address(livWin)) ? usdc : livWin,
    //         fee: 3000,
    //         tickSpacing: 60,
    //         hooks: address(0)
    //     });
    // }

    // PoolKey memory pool = PoolKey({
    //     currency0: currency0,
    //     currency1: currency1,
    //     fee: lpFee,
    //     tickSpacing: tickSpacing,
    //     hooks: hookContract
    // });

// //     event Initialize(
//     //     PoolId indexed id,
//     //     Currency indexed currency0,
//     //     Currency indexed currency1,
//     //     uint24 fee,
//     //     int24 tickSpacing,
//     //     IHooks hooks,
//     //     uint160 sqrtPriceX96,
//     //     int24 tick
//     // );

//     function createPools() external onlyOwner {
//         // require(poolWin == address(0), "Pools already created");

//         // poolWin = IPoolManager.initialize(key, sqrtPriceX96);(livWin, usdc, feeTier);
//         // poolDraw = IPoolManager.initializey(factory).createPool(livDraw, usdc, feeTier);
//         // poolLose = IUniswapV4Factory(factory).createPool(livLose, usdc, feeTier);
//     }

//     // function addInitialLiquidity(
//     //     uint256 usdcAmountWin,
//     //     uint256 livWinAmount,
//     //     uint256 usdcAmountDraw,
//     //     uint256 livDrawAmount,
//     //     uint256 usdcAmountLose,
//     //     uint256 livLoseAmount
//     // ) external onlyOwner {
//     //     IERC20(usdc).transferFrom(msg.sender, poolWin, usdcAmountWin);
//     //     IERC20(livWin).transferFrom(msg.sender, poolWin, livWinAmount);

//     //     IERC20(usdc).transferFrom(msg.sender, poolDraw, usdcAmountDraw);
//     //     IERC20(livDraw).transferFrom(msg.sender, poolDraw, livDrawAmount);

//     //     IERC20(usdc).transferFrom(msg.sender, poolLose, usdcAmountLose);
//     //     IERC20(livLose).transferFrom(msg.sender, poolLose, livLoseAmount);
//     // }
}
