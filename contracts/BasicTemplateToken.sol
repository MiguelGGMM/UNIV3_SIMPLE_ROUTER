// SPDX-License-Identifier: UNLICENSED

/*
    🐶 Jiyū Inu - 基于 🇨🇳
    https://t.me/jiyuinubase
*/

/*
    DEV: https://t.me/BambiDev
*/

//Template basic without fees

pragma solidity ^0.8.12;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Router02 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function factory() external pure returns (address);

    /* solhint-disable-next-line func-name-mixedcase */
    function WETH() external pure returns (address);

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}

contract BasicTemplateToken is Context, IERC20, Ownable2Step {
    using SafeMath for uint256;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    uint8 private constant _DECIMALS = 9;
    uint256 private constant _SUPPLY = 1000000 * 10 ** _DECIMALS;
    string private constant _NAME = "Jiyu Inu";
    string private constant _SYMBOL = "$JIYU";
    uint256 public _maxTxAmount = _SUPPLY.div(100); //1%
    uint256 public _maxWalletSize = _SUPPLY.div(25); //4%
    bool public limitsEnabled = true;

    IUniswapV2Router02 private uniswapV2Router;
    address private uniswapV2Pair;
    bool private tradingOpen;

    constructor() {
        _balances[_msgSender()] = _SUPPLY;
        emit Transfer(address(0), _msgSender(), _SUPPLY);
    }

    function name() public pure returns (string memory) {
        return _NAME;
    }

    function symbol() public pure returns (string memory) {
        return _SYMBOL;
    }

    function decimals() public pure returns (uint8) {
        return _DECIMALS;
    }

    function totalSupply() public pure override returns (uint256) {
        return _SUPPLY;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance")
        );
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        if (to != address(this) && limitsEnabled) {
            if (to != uniswapV2Pair && to != owner() && from != owner()) {
                uint256 heldTokens = balanceOf(to);
                require(
                    (heldTokens + amount) <= _maxWalletSize,
                    "Total Holding is currently limited, you can not buy that much."
                );
                require(amount <= _maxTxAmount, "TX Limit Exceeded");
            }
        }

        _balances[from] = _balances[from].sub(amount);
        _balances[to] = _balances[to].add(amount);
        emit Transfer(from, to, amount);
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return (a > b) ? b : a;
    }

    function openTrading() external payable onlyOwner {
        require(!tradingOpen, "trading is already open");
        uniswapV2Router = IUniswapV2Router02(0xfCD3842f85ed87ba2889b4D35893403796e67FF1);
        _approve(address(this), address(uniswapV2Router), _SUPPLY);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Router.addLiquidityETH{value: msg.value}(
            address(this),
            balanceOf(address(this)),
            0,
            0,
            owner(),
            block.timestamp
        );
        IERC20(uniswapV2Pair).approve(address(uniswapV2Router), type(uint).max);
        tradingOpen = true;
    }

    function enableLimits(bool enable) external onlyOwner {
        limitsEnabled = enable;
    }

    function unstuckETH() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function unstuckToken() external onlyOwner {
        _transfer(address(this), msg.sender, balanceOf(address(this)));
    }

    /* solhint-disable-next-line no-empty-blocks */
    receive() external payable {}
}
