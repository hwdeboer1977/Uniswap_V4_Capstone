// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { UD60x18, ud } from "prb-math/UD60x18.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import "forge-std/console.sol";

contract SportsBetting is BaseHook, ERC20 {
    IERC20 public usdc;
    IERC20 public usdt;
    address public admin;
    uint256 public liquidityParameter = 500e18;

    // Temporary as public state variables
    uint256 public initialCost;
    uint256 public newLiquidity;
    uint256 public newCost;
    uint256 public betCost;
    uint256 public betAmount;

    // Address protocolOwner (only one who can add/remove liquidity)
    address public protocolOwner;
    uint256 public matchStartTime; // starting time match

    IPositionManager posm;

    enum Outcome { LIV_WINS, LIV_DRAW, LIV_LOSE }

    mapping(Outcome => uint256) public liquidity;
    mapping(Outcome => mapping(address => uint256)) public userBets;
    Outcome public finalOutcome;
    bool public matchSettled;
    uint256 public totalLiquidity;

    event BetPlaced(address indexed user, Outcome outcome, uint256 amount, uint256 cost);
    event MatchSettled(Outcome winningOutcome);
    event PayoutClaimed(address user, uint256 userStake, uint256 totalPool, uint256 contractBalance, uint256 reward);

    constructor(
        IPoolManager _manager,
         address _protocolOwner,
        uint256 _matchStartTime,
        IPositionManager _posm,
        address _usdc,
        address _usdt,
        string memory _name,
        string memory _symbol
    ) BaseHook(_manager) ERC20(_name, _symbol, 18) {
        protocolOwner = _protocolOwner;
        matchStartTime=_matchStartTime;
        posm = _posm;
        usdc = IERC20(_usdc);
        usdt = IERC20(_usdt);
        liquidity[Outcome.LIV_WINS] = 0;
        liquidity[Outcome.LIV_DRAW] = 0;
        liquidity[Outcome.LIV_LOSE] = 0;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeSwap: false,
            afterSwap: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeInitialize: false,
            afterInitialize: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }


    function placeBet(Outcome _outcome, uint256 _amount) external {
        require(!matchSettled, "Betting is closed");
        require(_amount <= 2000e18, "Bet too large for liquidity");


        // uint256 initialCost = getMarketCost();
        // uint256 newLiquidity = liquidity[_outcome] + _amount;
        // liquidity[_outcome] = newLiquidity;

        // uint256 newCost = getMarketCost();
        // uint256 betCost = newCost - initialCost;

        betAmount = _amount;
        initialCost = getMarketCost();
        newLiquidity = liquidity[_outcome] + _amount;
        liquidity[_outcome] = newLiquidity;

        newCost = getMarketCost();
        betCost = newCost - initialCost;

        require(usdc.transferFrom(msg.sender, address(this), betCost), "USDC transfer failed");
        userBets[_outcome][msg.sender] += _amount;

        emit BetPlaced(msg.sender, _outcome, _amount, betCost);

        // Swap half of USDC for USDT using Uniswap V4
        uint256 halfUSDC = betCost / 2;

        //uint256 usdtReceived = swapUSDCForUSDT_V4(halfUSDC);

        // Add USDC/USDT liquidity to Uniswap V4
        //addLiquidityToUniswap(halfUSDC, usdtReceived);
    }

    
    // function _afterSwap(
    //     address,
    //     PoolKey calldata key,
    //     IPoolManager.SwapParams calldata,
    //     BalanceDelta delta,
    //     bytes calldata
    // ) internal override returns (bytes4, int128) {
    //     return (BaseHook.afterSwap.selector, 0);
    // }

   //event DebugSender(address sender, address protocolOwner);

    function _beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4) {
        
        // Log
        console.log("Sender:", sender); // this is address modifyLiquidityRouter
        console.log("Protocol Owner:", protocolOwner);

        // Ensure only the protocol can add liquidity
        //require(sender == protocolOwner, "Only the protocol can provide liquidity");

        // Ensure the match is still open (betting period is active)
        console.log("Block Timestamp:", block.timestamp);
        console.log("matchStartTime:", matchStartTime);
        require(block.timestamp < matchStartTime, "Cannot add liquidity after match starts");

        return BaseHook.beforeAddLiquidity.selector;
    }
    

    function _beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4) {
        
        // Log
        console.log("Sender:", sender); // this is address modifyLiquidityRouter
        console.log("Protocol Owner:", protocolOwner);

        // Ensure only the protocol can add liquidity
        //require(sender == protocolOwner, "Only the protocol can provide liquidity");

        // Ensure the match is still open (betting period is active)
        console.log("Block Timestamp:", block.timestamp);
        console.log("matchStartTime:", matchStartTime);
        //require(block.timestamp >= matchStartTime, "Cannot remove liquidity before match ends");

        return BaseHook.beforeRemoveLiquidity.selector;
    }

    // function _afterAddLiquidity(
    //     address,
    //     PoolKey calldata key,
    //     IPoolManager.ModifyLiquidityParams calldata,
    //     BalanceDelta delta,
    //     BalanceDelta,
    //     bytes calldata hookData
    // ) internal override onlyPoolManager returns (bytes4, BalanceDelta) {
    //     return (this.afterAddLiquidity.selector, delta);
    // }

    //function swapUSDCForUSDT_V4(uint256 amountIn) internal returns (uint256 amountOut) {
    //     usdc.approve(address(manager), amountIn);

    //     IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
    //         zeroForOne: true, // USDC -> USDT
    //         amountSpecified: int256(amountIn),
    //         sqrtPriceLimitX96: 0
    //     });

    //     BalanceDelta delta = manager.swap(address(this), params, "");
    //     amountOut = uint256(int256(delta.amount1())); // Get received USDT amount
   // }



    function getMarketCost() public view returns (uint256) {
        uint256 expSum = this.expScaled(liquidity[Outcome.LIV_WINS]) +
                        this.expScaled(liquidity[Outcome.LIV_DRAW]) +
                        this.expScaled(liquidity[Outcome.LIV_LOSE]);

        // The cost of a bet increases exponentially as the bet size increases.

        // Use PRBMath for ln(expSum) directly
        UD60x18 fixedX = ud(expSum);  // Scale x correctly to 18 decimals
     
        uint256 lnExpSum = fixedX.ln().unwrap();
       
        // Return the market cost
        return (liquidityParameter * lnExpSum) / 1e18; // Final scaling
        
    }

    function expScaled(uint256 x) public view returns (uint256) {
        //require(x <= 133e18, "Input too large for exp()");
        
        // Convert x to fixed-point (18 decimals)
        UD60x18 fixedX = ud((x * 1e18) / liquidityParameter);  
        
        return fixedX.exp().unwrap(); // Compute e^x correctly
    }

  

}