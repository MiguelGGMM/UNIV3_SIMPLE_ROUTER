/*
    Developed by Kerry <TG: campermon>
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IWETH} from "./Libraries/IWETH.sol";
import {IUniswapV3Pool} from "./UniswapV3/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "./UniswapV3/IUniswapV3Factory.sol";
import {TickMath} from "./Libraries/TickMath.sol";
/*solhint-disable no-console */
import {console} from "hardhat/console.sol";

/*solhint-disable const-name-snakecase */
contract SimpleRouterV3 is Context, Ownable2Step, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeMath for uint160;

    // DEBUG
    bool private debugMode;

    // Chain weth address
    address private weth;

    // Current liq pools
    IUniswapV3Pool private currentLiqPool;

    // Current tokens and slip
    address private currentToken;
    address private currentPair;
    address private currentLiqPair;
    uint256 private currentMinTokens;
    uint256 private currentTokensPair;
    uint256 private currentLastTokens;

    // Recipient (caller)
    address private recipient;

    // Op type
    bool private isEthOp;
    bool private zeroForOne;

    // The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant MIN_SQRT_RATIO = 4295128739; // ((1.0001^-887220)^(1/2))*2^96
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
    
    // Decimals price precision
    uint8 internal constant decimalsPrecision = 18;

    // Pair fees
    uint24 internal constant liqPairFee001 = 100;
    uint24 internal constant liqPairFee005 = 500;
    uint24 internal constant liqPairFee030 = 3000;
    uint24 internal constant liqPairFee100 = 10000;

    // Pair fees dynamic
    uint24 [] internal liqPairFeeX;

    bool private reentrantCallback;
    modifier nonReentrantCallback() {
        require(!reentrantCallback, "Reentrancy not allowed");
        reentrantCallback = true;
        _;
        reentrantCallback = false;
    }

    /*solhint-disable-next-line no-empty-blocks */
    constructor(address _weth, bool _debugMode) { 
        weth = _weth;
        debugMode = _debugMode;
    }

    // region VIEWS

    function improveLiqPair(address factory, address token0, address token1, bool pairZero, uint24 liqPairFee, address lastLiqPair, uint256 lastLiqBal) external view returns(address, uint256) {
        IUniswapV3Factory _factory = IUniswapV3Factory(factory);
        address liqPair = _factory.getPool(token0, token1, liqPairFee);
        uint256 liqBal = IERC20(pairZero ? token0 : token1).balanceOf(liqPair);
        
        if(liqBal > lastLiqBal) {
            return (liqPair, liqBal);
        } else {
            return (lastLiqPair, lastLiqBal);
        }
    }

    function searchLiqPairBase(address factory, address token0, address token1, bool pairZero) external view returns(address, uint256) {        
        (address liqPair, uint256 liqBal) = this.improveLiqPair(factory, token0, token1, pairZero, liqPairFee001, address(0), 0);
        (liqPair, liqBal) = this.improveLiqPair(factory, token0, token1, pairZero, liqPairFee005, liqPair, liqBal);
        (liqPair, liqBal) = this.improveLiqPair(factory, token0, token1, pairZero, liqPairFee030, liqPair, liqBal);
        (liqPair, liqBal) = this.improveLiqPair(factory, token0, token1, pairZero, liqPairFee100, liqPair, liqBal);

        // Check for other pools
        if(liqPairFeeX.length > 0) {
            for(uint24 _i = 0; _i < liqPairFeeX.length; _i++) {
                (liqPair, liqBal) = this.improveLiqPair(factory, token0, token1, pairZero, liqPairFeeX[_i], liqPair, liqBal);
            }
        }

        return (liqPair, liqBal);
    }

    function searchLiqPair(address factory, address token, address pair) external view returns(address) {
        (address liqPair, uint256 liqBal) = this.searchLiqPairBase(factory, token, pair, false);
        (address liqPair2, uint256 liqBal2) = this.searchLiqPairBase(factory, pair, token, true);
        return liqBal > liqBal2 ? liqPair : liqPair2;
    }

    function calcAmountReceived(address factory, address token, address pair, uint256 amountIn) external view returns(uint256) {
        // SEARCH LIQ PAIR
        address liqPair = this.searchLiqPair(factory, token, pair);
        require(liqPair != address(0), "V3 liq pair not found on factory");

        // V3 LIQ CONTRACT
        (, int24 tick,,,,,) = IUniswapV3Pool(liqPair).slot0();
        uint160 sqrtRatioAtTick = TickMath.getSqrtRatioAtTick(tick);
        uint256 ratioAtTick = uint256(sqrtRatioAtTick).mul(uint256(sqrtRatioAtTick));
        bool _zeroForOne = weth == IUniswapV3Pool(liqPair).token0();

        if(!_zeroForOne) {
            return amountIn.mul(10**decimalsPrecision).div(ratioAtTick.mul(10**decimalsPrecision).div(2**192));
        } else {
            return amountIn.mul(ratioAtTick.mul(10**decimalsPrecision).div(2**192)).div(10**decimalsPrecision);
        }
    }

    // endregion

    // region INTERNALS

    function setBasicVariables(address factory, address tokenBuy, address pair, uint256 amountPair, uint256 minTokensReceived) internal {
        recipient = msg.sender;
        currentToken = tokenBuy;
        currentPair = pair;
        currentMinTokens = minTokensReceived;        

        // Current amount of tokens
        currentLastTokens = IERC20(currentToken).balanceOf(recipient);

        // SEARCH LIQ PAIR
        currentLiqPair = this.searchLiqPair(factory, tokenBuy, pair);

        // V3 LIQ CONTRACT
        currentLiqPool = IUniswapV3Pool(currentLiqPair);

        zeroForOne = pair == currentLiqPool.token0();
        currentTokensPair = amountPair;

        // ETH op?
        isEthOp = msg.value > 0;
    }

    function performSwap() internal {
        currentLiqPool.swap(recipient, zeroForOne, int256(currentTokensPair), zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1, abi.encode(0)/*abi.encode(path, payer)*/);
    }

    // endregion

    function performBuyTokenETH(address factory, address tokenBuy, uint256 minTokensReceived) external payable nonReentrant {
        setBasicVariables(factory, tokenBuy, weth, msg.value, minTokensReceived);

        // WRAP ETH
        IWETH wethI = IWETH(zeroForOne ? currentLiqPool.token0() : currentLiqPool.token1());
        wethI.deposit{value: currentTokensPair}();        

        // SWAP
        performSwap();    
    }

    function performBuyToken(address factory, address tokenBuy, address pair, uint256 amountPair, uint256 minTokensReceived) external nonReentrant {
        setBasicVariables(factory, tokenBuy, pair, amountPair, minTokensReceived);   

        // SWAP
        performSwap();  
    }

    function uniswapV3SwapCallback(int256, int256, bytes calldata) external nonReentrantCallback {
        require(msg.sender == currentLiqPair, "Only liq pairs allowed");

        // Check amount of tokens received if slip
        require(IERC20(currentToken).balanceOf(recipient).sub(currentLastTokens) >= currentMinTokens, "Slippage error");        

        if(debugMode) {
            console.log("Token holdings before tx: %s, tokens that will be send for payment %s", currentLastTokens, currentTokensPair);
            console.log("Tokens received: %s, min tokens: %s, liq pool: %s", IERC20(currentToken).balanceOf(recipient).sub(currentLastTokens), currentMinTokens, msg.sender);
        }

        // Send payment
        if(isEthOp) {
            bool success = IERC20(currentPair).transfer(address(currentLiqPool), currentTokensPair);
            if(debugMode) console.log("Transfer success? %s", success);
            require(success, "Transfer error (payment) (ethOP)");
        } else {
            bool success = IERC20(currentPair).transferFrom(recipient, address(currentLiqPool), currentTokensPair);
            if(debugMode) console.log("Transfer success? %s", success);
            require(success, "Transfer error (payment) (notEthOP)");
        }
    }

    // region ADMIN

    function addliqPairFeeX(uint24 dynFee) external onlyOwner {
        liqPairFeeX.push(dynFee);
    }

    function clearStuckToken(address _tokenAddress, uint256 _tokens) public onlyOwner returns (bool) {
        if(_tokens == 0){
            _tokens = IERC20 (_tokenAddress).balanceOf(address(this));
        }
        return IERC20 (_tokenAddress).transfer(msg.sender, _tokens);
    }    

    function clearStuckBalance() external onlyOwner { payable(msg.sender).transfer(address(this).balance); }  

    //endregion
}