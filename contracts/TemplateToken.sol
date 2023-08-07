// SPDX-License-Identifier: UNLICENSED

/*
    https://t.me/ElonBaseOfficial
    DEV: https://t.me/BambiDev
*/

//Template with fees

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

contract TemplateToken is Context, IERC20, Ownable2Step {
    using SafeMath for uint256;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    address payable private _taxWallet;

    uint256 public _buyTax = 4;
    uint256 public _sellTax = 4;

    uint8 private constant _DECIMALS = 9;
    uint256 private constant _SUPPLY = 1000000 * 10 ** _DECIMALS;
    string private constant _NAME = "ElonBase";
    string private constant _SYMBOL = "$EBASE";
    uint256 public _maxTxAmount = _SUPPLY.div(100); //1%
    uint256 public _maxWalletSize = _SUPPLY.div(50); //2%
    uint256 public _taxSwapThreshold = _SUPPLY.div(2000); //0.05%
    uint256 public _maxTaxSwap = _SUPPLY.div(1000); //0.1%
    bool public limitsEnabled = true;

    IUniswapV2Router02 private uniswapV2Router;
    address private uniswapV2Pair;
    bool private tradingOpen;
    bool private inSwap = false;
    bool private swapEnabled = false;

    modifier lockTheSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor() {
        _taxWallet = payable(_msgSender());
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

        uint256 taxAmount = 0;
        if (from != owner() && to != owner()) {
            taxAmount = amount.mul(_buyTax).div(100);

            if (to == uniswapV2Pair && from != address(this)) {
                taxAmount = amount.mul(_sellTax).div(100);
            }

            uint256 contractTokenBalance = balanceOf(address(this));
            if (!inSwap && to == uniswapV2Pair && swapEnabled && contractTokenBalance > _taxSwapThreshold) {
                swapTokensForEth(min(amount, min(contractTokenBalance, _maxTaxSwap)));
                uint256 contractETHBalance = address(this).balance;
                if (contractETHBalance > 0) {
                    sendETHToFee(address(this).balance);
                }
            }
        }

        if (taxAmount > 0) {
            _balances[address(this)] = _balances[address(this)].add(taxAmount);
            emit Transfer(from, address(this), taxAmount);
        }

        _balances[from] = _balances[from].sub(amount);
        _balances[to] = _balances[to].add(amount.sub(taxAmount));
        emit Transfer(from, to, amount.sub(taxAmount));
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return (a > b) ? b : a;
    }

    function swapTokensForEth(uint256 tokenAmount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function sendETHToFee(uint256 amount) private {
        _taxWallet.transfer(amount);
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
        swapEnabled = true;
        tradingOpen = true;
    }

    function reduceFee(uint256 _newFee) external {
        require(_msgSender() == _taxWallet, "Only tax receiver can modify this");
        require(_newFee <= _buyTax && _newFee <= _sellTax, "Tax only can be decreased, not increased");
        _buyTax = _newFee;
        _sellTax = _newFee;
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

    function manualSwap() external {
        require(_msgSender() == _taxWallet, "Only tax wallet can run swap manually");
        uint256 tokenBalance = balanceOf(address(this));
        if (tokenBalance > 0) {
            swapTokensForEth(tokenBalance);
        }
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            sendETHToFee(ethBalance);
        }
    }

    /* solhint-disable-next-line no-empty-blocks */
    receive() external payable {}
}
