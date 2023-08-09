/*
    Developed by <TG: @campermon>
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

/*solhint-disable no-console */
/*solhint-disable const-name-snakecase */

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IWETH} from "./Libraries/IWETH.sol";
import {IUniswapV3Pool} from "./UniswapV3/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "./UniswapV3/IUniswapV3Factory.sol";
import {TickMath} from "./Libraries/TickMath.sol";
import {console} from "hardhat/console.sol";

/// @author <TG: @campermon>
/// @title Simple contract to perform buys, sells and honey checks against UniswapV3 liquidity pools, with or without slippage
/// @notice Each call will require the 'factory', it is the contract that creates the liquidity pool contracts, only contracts UniswapV3 factory or clones are allowed
/// @dev The contract is 'bot friendly' in comparison with UniversalRouter and RouterProcessorV3
/// @custom:experimental This is an experimental contract
contract SimpleRouterV3 is Context, Ownable2Step, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeMath for uint160;

    // DEBUG (only used for testing)
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

    // Pair fees
    uint24 internal constant liqPairFee001 = 100;
    uint24 internal constant liqPairFee005 = 500;
    uint24 internal constant liqPairFee030 = 3000;
    uint24 internal constant liqPairFee100 = 10000;

    // Pair fees dynamic
    uint24[] internal liqPairFeeX;

    // Amount for tax check
    uint256 constant internal amountForCheck = 10;
    uint256 constant internal baseForCheck = 10000;
    uint256 constant internal amountForBuying = baseForCheck - amountForCheck;

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

    // region INTERNAL VIEWS

    function min(uint256 el1, uint256 el2) internal pure returns(uint256){
        return el1 > el2 ? el2 : el1;
    }

    function max(uint256 el1, uint256 el2) internal pure returns(uint256){
        return el1 > el2 ? el1 : el2;
    }

    /**     
    *@notice Try find the most liquid pair for the token0 and token1 specified, if not liq pair is found then previous liq pair address will be returned 
    *@dev On arguments it receives previous liq pair address (lastLiqPair) and his liq available (lastLiqBal)
    *@return The pair address and the liq amount available
    */
    function improveLiqPair(
        address factory,
        address token0,
        address token1,
        bool pairZero,
        uint24 liqPairFee,
        address lastLiqPair,
        uint256 lastLiqBal
    ) internal view returns (address, uint256) {
        IUniswapV3Factory _factory = IUniswapV3Factory(factory);
        address liqPair = _factory.getPool(token0, token1, liqPairFee);
        uint256 liqBal = IERC20(pairZero ? token0 : token1).balanceOf(liqPair);

        if (liqBal > lastLiqBal) {
            return (liqPair, liqBal);
        } else {
            return (lastLiqPair, lastLiqBal);
        }
    }

    /**     
    *@notice Try find the most liquid pair for the token0 and token1 specified, if not liq pair is found then ZERO address will be returned 
    *@return The pair address and the liq amount available
    */
    function searchLiqPairBase(
        address factory,
        address token0,
        address token1,
        bool pairZero
    ) internal view returns (address, uint256) {
        (address liqPair, uint256 liqBal) = improveLiqPair(
            factory,
            token0,
            token1,
            pairZero,
            liqPairFee001,
            address(0),
            0
        );
        (liqPair, liqBal) = improveLiqPair(factory, token0, token1, pairZero, liqPairFee005, liqPair, liqBal);
        (liqPair, liqBal) = improveLiqPair(factory, token0, token1, pairZero, liqPairFee030, liqPair, liqBal);
        (liqPair, liqBal) = improveLiqPair(factory, token0, token1, pairZero, liqPairFee100, liqPair, liqBal);

        // Check for other pools
        if (liqPairFeeX.length > 0) {
            for (uint24 _i = 0; _i < liqPairFeeX.length; _i++) {
                (liqPair, liqBal) = improveLiqPair(
                    factory,
                    token0,
                    token1,
                    pairZero,
                    liqPairFeeX[_i],
                    liqPair,
                    liqBal
                );
            }
        }

        return (liqPair, liqBal);
    }

    // endregion

    // region VIEWS

    /**     
    *@notice Try find the most liquid pair for the tokens specified, if not liq pair is found then ZERO address will be returned 
    *@return The pair address and the liq amount available
    */
    function searchLiqPair(address factory, address token, address pair) external view returns (address) {
        (address liqPair, uint256 liqBal) = searchLiqPairBase(factory, token, pair, false);
        (address liqPair2, uint256 liqBal2) = searchLiqPairBase(factory, pair, token, true);
        return liqBal > liqBal2 ? liqPair : liqPair2;
    }

    /**
    *@notice Calculates the estimated output amount (token) on a trade pair -> token
    *@return The estimated token amount you would receive
    */
    function calcAmountReceived(
        address factory,
        address token,
        address pair,
        uint256 amountIn
    ) external view returns (uint256) {
        // SEARCH LIQ PAIR
        address liqPair = this.searchLiqPair(factory, token, pair);
        require(liqPair != address(0), "V3 liq pair not found on factory");

        // V3 LIQ CONTRACT
        (, int24 tick, , , , , ) = IUniswapV3Pool(liqPair).slot0();
        uint160 sqrtRatioAtTick = TickMath.getSqrtRatioAtTick(tick);
        uint256 ratioAtTick = uint256(sqrtRatioAtTick).mul(uint256(sqrtRatioAtTick));
        bool _zeroForOne = pair == IUniswapV3Pool(liqPair).token0();

        // PRICE PRECISION
        uint256 _decimals = 6;
        (bool valid,) = ratioAtTick.tryMul(10 ** _decimals);
        if(!valid) {
            while(!valid && _decimals > 0) {
                _decimals--;
                (valid,) = ratioAtTick.tryMul(10 ** _decimals);
            }
        }
        require(valid, "INVALID PRECISSION DECIMALS");
        uint256 precision = (2 ** 192 > ratioAtTick ? uint256(2 ** 192).mul(10 ** _decimals).div(ratioAtTick) : ratioAtTick.mul(10 ** _decimals).div(uint256(2 ** 192)));
        (valid,) = precision.tryMul(ratioAtTick);
        if(!valid) {
            precision = 10 ** 6;
            (valid,) = precision.tryMul(ratioAtTick);
            while(!valid && precision >= 10) {
                precision = precision.div(10);
                (valid,) = precision.tryMul(ratioAtTick);
            }
        }
        require(valid, "INVALID PRECISSION VALUE");

        uint256 amountOutput = 0;
        if (!_zeroForOne) {
            amountOutput = amountIn.mul(precision).div(ratioAtTick.mul(precision).div(2 ** 192));            
        } else {
            amountOutput = amountIn.mul(ratioAtTick.mul(precision).div(2 ** 192)).div(precision);
        }

        return amountOutput;
    }

    // endregion

    // region INTERNALS

    function setBasicVariables(
        address factory,
        address tokenBuy,
        address pair,
        uint256 amountPair,
        uint256 minTokensReceived,
        address _recipient,
        bool _isEthOp                
    ) internal {
        recipient = _recipient;
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
        isEthOp = _isEthOp;
    }

    function performSwap() internal {
        currentLiqPool.swap(
            recipient,
            zeroForOne,
            int256(currentTokensPair),
            zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1,
            abi.encode(0) /*abi.encode(path, payer)*/
        );
    }

    function performBuyTokenInternal(
        address factory,
        address tokenBuy,
        address pair,
        uint256 amountPair,
        uint256 amountETH,
        address _recipient,
        uint256 minTokensReceived
    ) internal {
        setBasicVariables(factory, tokenBuy, pair, amountPair, minTokensReceived, _recipient, amountETH > 0);

        if(amountETH > 0) {
            // WRAP ETH
            IWETH wethI = IWETH(zeroForOne ? currentLiqPool.token0() : currentLiqPool.token1());
            wethI.deposit{value: currentTokensPair}();
        }

        // SWAP
        performSwap();
    }

    function performBuyAndSellTokenInternal(
        address factory,
        address tokenBuy,
        address pair,
        uint256 amountPair,
        uint256 amountETH      
    ) internal returns(uint256, uint256) {
        if(amountETH > 0) {
            amountPair = amountETH;
            pair = weth;
        }

        //// CHECK BUY
        uint256 estimatedOutput = this.calcAmountReceived(factory, tokenBuy, pair, amountPair);
        performBuyTokenInternal(factory, tokenBuy, pair, amountPair, amountETH, msg.sender, 0);
        uint256 realOutput = IERC20(currentToken).balanceOf(recipient).sub(currentLastTokens);        

        //// CHECK SELL
        uint256 estimatedOutputSell = this.calcAmountReceived(factory, pair, tokenBuy, realOutput);
        performBuyTokenInternal(factory, pair, tokenBuy, realOutput, 0, msg.sender, 0);
        uint256 realOutputSell = IERC20(pair).balanceOf(recipient).sub(currentLastTokens);

        //// CALCULATE TAX
        uint256 buyTax = uint256(10000).sub(realOutput.mul(10000).div(estimatedOutput));
        uint256 sellTax = uint256(10000).sub(realOutputSell.mul(10000).div(estimatedOutputSell));

        return (buyTax, sellTax);
    }

    // endregion

    // region EXTERNALS

    // region BUY/SELL

    /// @notice Buy token using ETH payment
    function performBuyTokenETH(
        address factory,
        address tokenBuy,
        uint256 minTokensReceived
    ) external payable nonReentrant {
        performBuyTokenInternal(factory, tokenBuy, weth, msg.value, msg.value, msg.sender, minTokensReceived);
    }

    /// @notice Buy token using another token (pair)
    function performBuyToken(
        address factory,
        address tokenBuy,
        address pair,
        uint256 amountPair,
        uint256 minTokensReceived
    ) external nonReentrant {
        performBuyTokenInternal(factory, tokenBuy, pair, amountPair, 0, msg.sender, minTokensReceived);
    }

    /// @notice Buy token using ETH payment after previous tax checking
    /// @dev 0.1% of amount is used for tax check, it is also substracted from param 'minTokensReceived' (99.9%)
    /// @param maxTaxBuy is base 10000 (100% = 10000, 99.99% = 9999)
    /// @param maxTaxSell is base 10000 (100% = 10000, 99.99% = 9999)
    function performBuyTokenETHWithCheck(
        address factory,
        address tokenBuy,
        uint256 minTokensReceived,
        uint256 maxTaxBuy,
        uint256 maxTaxSell
    ) external payable nonReentrant {
        (uint256 taxBuy, uint256 taxSell) = performBuyAndSellTokenInternal(factory, tokenBuy, weth /* will be overriden */, 0 /* will be overriden */, msg.value.mul(amountForCheck).div(baseForCheck));
        if(debugMode){
            console.log("Buy tax: %s, Sell tax: %s", taxBuy, taxSell);
        }
        require(taxBuy <= maxTaxBuy, "Buy tax too high");
        require(taxSell <= maxTaxSell, "Sell tax too high");
        performBuyTokenInternal(factory, tokenBuy, weth, msg.value.mul(amountForBuying).div(baseForCheck), msg.value.mul(amountForBuying).div(baseForCheck), msg.sender, minTokensReceived.mul(amountForBuying).div(baseForCheck));
    }

    /// @notice Buy token using another token (pair) after previous tax checking
    /// @dev 0.1% of amount is used for tax check, it is also substracted from param 'minTokensReceived' (99.9%)
    /// @param maxTaxBuy is base 10000 (100% = 10000, 99.99% = 9999)
    /// @param maxTaxSell is base 10000 (100% = 10000, 99.99% = 9999)
    function performBuyTokenWithCheck(
        address factory,
        address tokenBuy,
        address pair,
        uint256 amountPair,
        uint256 minTokensReceived,
        uint256 maxTaxBuy,
        uint256 maxTaxSell
    ) external payable nonReentrant {
        (uint256 taxBuy, uint256 taxSell) = performBuyAndSellTokenInternal(factory, tokenBuy, pair, amountPair.mul(amountForCheck).div(baseForCheck), 0);
        if(debugMode){
            console.log("Buy tax: %s, Sell tax: %s", taxBuy, taxSell);
        }
        require(taxBuy <= maxTaxBuy, "Buy tax too high");
        require(taxSell <= maxTaxSell, "Sell tax too high");
        performBuyTokenInternal(factory, tokenBuy, pair, amountPair.mul(amountForBuying).div(baseForCheck), 0, msg.sender, minTokensReceived.mul(amountForBuying).div(baseForCheck));
    }

    /// @notice This function is called by the UniswapV3 liquidity pools, here we check if the required tokens were received and in that case the payment is sent
    function uniswapV3SwapCallback(int256, int256, bytes calldata) external nonReentrantCallback {
        require(msg.sender == currentLiqPair, "Only liq pairs allowed");

        // Check amount of tokens received if slip
        require(IERC20(currentToken).balanceOf(recipient).sub(currentLastTokens) >= currentMinTokens, "Slippage error");

        if (debugMode) {
            console.log(
                "Token holdings before tx: %s, tokens that will be send for payment %s",
                currentLastTokens,
                currentTokensPair
            );
            console.log(
                "Tokens received: %s, min tokens: %s, liq pool: %s",
                IERC20(currentToken).balanceOf(recipient).sub(currentLastTokens),
                currentMinTokens,
                msg.sender
            );
        }

        // Send payment
        if (isEthOp) {
            bool success = IERC20(currentPair).transfer(address(currentLiqPool), currentTokensPair);
            if (debugMode) console.log("Transfer success? %s", success);
            require(success, "Transfer error (payment) (ethOP)");
        } else {
            bool success = IERC20(currentPair).transferFrom(recipient, address(currentLiqPool), currentTokensPair);
            if (debugMode) console.log("Transfer success? %s", success);
            require(success, "Transfer error (payment) (notEthOP)");
        }
    }    

    // endregion

    // region HONEY CHECKS

    /// @notice Buy and sell the specified token using ETH payment and returns the buy and sell taxes
    /// @dev You can use this to check if a token is a honeypot with a static call
    function performBuyAndSellTokenETH(
        address factory,
        address tokenBuy
    ) external nonReentrant payable returns(uint256, uint256) {
        return performBuyAndSellTokenInternal(factory, tokenBuy, weth /* will be overriden */, 0 /* will be overriden */, msg.value);
    }

    /// @notice Buy and sell the specified token using another token (pair) and returns the buy and sell taxes
    /// @dev You can use this to check if a token is a honeypot with a static call
    function performBuyAndSellToken(
        address factory,
        address tokenBuy,
        address pair,
        uint256 amountPair
    ) external nonReentrant returns(uint256, uint256) {
        return performBuyAndSellTokenInternal(factory, tokenBuy, pair, amountPair, 0);
    }

    // endregion

    // region ADMIN

    function addliqPairFeeX(uint24 dynFee) external onlyOwner {
        liqPairFeeX.push(dynFee);
    }

    function clearStuckToken(address _tokenAddress, uint256 _tokens) public onlyOwner returns (bool) {
        if (_tokens == 0) {
            _tokens = IERC20(_tokenAddress).balanceOf(address(this));
        }
        return IERC20(_tokenAddress).transfer(msg.sender, _tokens);
    }

    function clearStuckBalance() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    //endregion

    //endregion
}
