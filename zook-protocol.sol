// SPDX-License-Identifier: MIT
pragma solidity = 0.8.16;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

contract zook is ERC20, Ownable {
    using SafeMath for uint256;

    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;
    address public constant deadAddress = address(0xdead);
    address public uniV2router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    bool private swapping;

    address public developmentWallet;
    address public liquidityWallet;
    address public marketingWallet;

    uint256 public maxTransaction;
    uint256 public swapTokensAtAmount;
    uint256 public maxWallet;

    bool public limitsInEffect = true;
    bool public tradingActive = false;
    bool public swapEnabled = false;



    // Anti-bot and anti-whale mappings and variables
    mapping(address => uint256) private _holderLastTransferTimestamp;

    bool public transferDelayEnabled = true;
    uint256 private launchBlock;
    mapping(address => bool) public blocked;

    uint256 public buyTotalFees;
    uint256 public buyLiquidityFee;
    uint256 public buyDevelopmentFee;
    uint256 public buyMarketingFee;

    uint256 public sellTotalFees;
    uint256 public sellLiquidityFee;
    uint256 public sellDevelopmentFee;
    uint256 public sellMarketingFee;



    uint256 public tokensForLiquidity;
    uint256 public tokensForDevelopment;
    uint256 public tokensForMarketing;



    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) public _isExcludedmaxTransaction;

    mapping(address => bool) public automatedMarketMakerPairs;

    event UpdateUniswapV2Router(
        address indexed newAddress,
        address indexed oldAddress
    );

    event ExcludeFromFees(address indexed account, bool isExcluded);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event developmentWalletUpdated(
        address indexed newWallet,
        address indexed oldWallet
    );

    event liquidityWalletUpdated(
        address indexed newWallet,
        address indexed oldWallet
    );

    event marketingWalletUpdated(
        address indexed newWallet,
        address indexed oldWallet
    );

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiquidity
    );

    constructor() ERC20("ZOOK PROTOCOL", "ZOOK") {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(uniV2router); 

        excludeFromMaxTransaction(address(_uniswapV2Router), true);
        uniswapV2Router = _uniswapV2Router;

        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());
        excludeFromMaxTransaction(address(uniswapV2Pair), true);
        _setAutomatedMarketMakerPair(address(uniswapV2Pair), true);

        // launch buy fees
        uint256 _buyLiquidityFee = 10;
        uint256 _buyDevelopmentFee = 10;
        uint256 _buyMarketingFee = 10;
        
        // launch sell fees
        uint256 _sellLiquidityFee = 10;
        uint256 _sellDevelopmentFee = 40;
        uint256 _sellMarketingFee = 30;


        uint256 totalSupply = 100_000_000 * 1e18;

        maxTransaction = 1000_000 * 1e18; // 1% max transaction at launch
        maxWallet = 1000_000 * 1e18; // 1% max wallet at launch
        swapTokensAtAmount = (totalSupply * 5) / 10000; // 0.05% swap wallet


        buyLiquidityFee = _buyLiquidityFee;
        buyDevelopmentFee = _buyDevelopmentFee;
        buyMarketingFee = _buyMarketingFee;
        buyTotalFees = buyLiquidityFee + buyDevelopmentFee + buyMarketingFee ;

        sellLiquidityFee = _sellLiquidityFee;
        sellDevelopmentFee = _sellDevelopmentFee;
        sellMarketingFee = _sellMarketingFee;
        sellTotalFees = sellLiquidityFee + sellDevelopmentFee + sellMarketingFee ;

        developmentWallet = address(0x4860da3d48EF5c82c269eE185Dc27Aa9DAfDC1d9); 
        liquidityWallet = address(0x897B2fFCeE9a9611BF465866fD293d9dD931a230); 
        marketingWallet = address(0x2Cec118b9749a659b851cecbe1b5a8c0C417773f);

        // exclude from paying fees or having max transaction amount
        excludeFromFees(owner(), true);
        excludeFromFees(address(this), true);
        excludeFromFees(address(0xdead), true);

        excludeFromMaxTransaction(owner(), true);
        excludeFromMaxTransaction(address(this), true);
        excludeFromMaxTransaction(address(0xdead), true);

        _mint(msg.sender, totalSupply);
    }

    receive() external payable {}

    function enableTrading() external onlyOwner {
        require(!tradingActive, "Token launched");
        tradingActive = true;
        launchBlock = block.number;
        swapEnabled = true;
    }

    // remove limits after token is stable
    function removeLimits() external onlyOwner returns (bool) {
        limitsInEffect = false;
        return true;
    }

    // disable Transfer delay - cannot be reenabled
    function disableTransferDelay() external onlyOwner returns (bool) {
        transferDelayEnabled = false;
        return true;
    }

    // change the minimum amount of tokens to sell from fees
    function updateSwapTokensAtAmount(uint256 newAmount)
        external
        onlyOwner
        returns (bool)
    {
        require(
            newAmount >= (totalSupply() * 1) / 100000,
            "Swap amount cannot be lower than 0.001% total supply."
        );
        require(
            newAmount <= (totalSupply() * 5) / 1000,
            "Swap amount cannot be higher than 0.5% total supply."
        );
        swapTokensAtAmount = newAmount;
        return true;
    }

    function updateMaxTransaction(uint256 newNum) external onlyOwner {
        require(
            newNum >= ((totalSupply() * 1) / 1000) / 1e18,
            "Cannot set maxTransaction lower than 0.1%"
        );
        maxTransaction = newNum * (10**18);
    }

    function updateMaxWallet(uint256 newNum) external onlyOwner {
        require(
            newNum >= ((totalSupply() * 5) / 1000) / 1e18,
            "Cannot set maxWallet lower than 0.5%"
        );
        maxWallet = newNum * (10**18);
    }

    function excludeFromMaxTransaction(address updAds, bool isEx)
        public
        onlyOwner
    {
        _isExcludedmaxTransaction[updAds] = isEx;
    }

    // only use to disable contract sales if absolutely necessary (emergency use only)
    function updateSwapEnabled(bool enabled) external onlyOwner {
        swapEnabled = enabled;
    }

    function updateBuyFees(
        uint256 _liquidityFee,
        uint256 _developmentFee,
        uint256  _marketingFee
    ) external onlyOwner {
        buyLiquidityFee = _liquidityFee;
        buyDevelopmentFee = _developmentFee;
        buyMarketingFee =  _marketingFee;
        buyTotalFees =  buyLiquidityFee + buyDevelopmentFee + buyMarketingFee ;
        require(buyTotalFees <= 5);
    }

    function updateSellFees(
        uint256 _liquidityFee,
        uint256 _developmentFee,
        uint256  _marketingFee
    ) external onlyOwner {
        sellLiquidityFee = _liquidityFee;
        sellDevelopmentFee = _developmentFee;
        sellMarketingFee =  _marketingFee;
        sellTotalFees = sellLiquidityFee + sellDevelopmentFee + sellMarketingFee ;
        require(sellTotalFees <= 5); 
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        _isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function setAutomatedMarketMakerPair(address pair, bool value)
        public
        onlyOwner
    {
        require(
            pair != uniswapV2Pair,
            "The pair cannot be removed from automatedMarketMakerPairs"
        );

        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        automatedMarketMakerPairs[pair] = value;

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function updatedevelopmentWallet(address newWallet) external onlyOwner {
        emit developmentWalletUpdated(newWallet, developmentWallet);
        developmentWallet = newWallet;
    }

    function updatemarketingWallet (address newWallet) external onlyOwner{
        emit marketingWalletUpdated(newWallet,marketingWallet);
       marketingWallet = newWallet;
    }

    function updateliquidityWallet(address newliquidityWallet) external onlyOwner {
        emit liquidityWalletUpdated(newliquidityWallet, liquidityWallet);
        liquidityWallet = newliquidityWallet;
    }

    function isExcludedFromFees(address account) public view returns (bool) {
        return _isExcludedFromFees[account];
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(!blocked[from], "Sniper blocked");

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        if (limitsInEffect) {
            if (
                from != owner() &&
                to != owner() &&
                to != address(0) &&
                to != address(0xdead) &&
                !swapping
            ) {
                if (!tradingActive) {
                    require(
                        _isExcludedFromFees[from] || _isExcludedFromFees[to],
                        "Trading is not active."
                    );
                }

                // at launch if the transfer delay is enabled, ensure the block timestamps for purchasers is set -- during launch.
                if (transferDelayEnabled) {
                    if (
                        to != owner() &&
                        to != address(uniswapV2Router) &&
                        to != address(uniswapV2Pair)
                    ) {
                        require(
                            _holderLastTransferTimestamp[tx.origin] <
                                block.number,
                            "_transfer:: Transfer Delay enabled.  Only one purchase per block allowed."
                        );
                        _holderLastTransferTimestamp[tx.origin] = block.number;
                    }
                }

                //when buy
                if (
                    automatedMarketMakerPairs[from] &&
                    !_isExcludedmaxTransaction[to]
                ) {
                    require(
                        amount <= maxTransaction,
                        "Buy transfer amount exceeds the maxTransaction."
                    );
                    require(
                        amount + balanceOf(to) <= maxWallet,
                        "Max wallet exceeded"
                    );
                }
                //when sell
                else if (
                    automatedMarketMakerPairs[to] &&
                    !_isExcludedmaxTransaction[from]
                ) {
                    require(
                        amount <= maxTransaction,
                        "Sell transfer amount exceeds the maxTransaction."
                    );
                } else if (!_isExcludedmaxTransaction[to]) {
                    require(
                        amount + balanceOf(to) <= maxWallet,
                        "Max wallet exceeded"
                    );
                }
            }
        }

        uint256 contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if (
            canSwap &&
            swapEnabled &&
            !swapping &&
            !automatedMarketMakerPairs[from] &&
            !_isExcludedFromFees[from] &&
            !_isExcludedFromFees[to]
        ) {
            swapping = true;

            swapBack();

            swapping = false;
        }

        bool takeFee = !swapping;

        // if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        uint256 fees = 0;
        // only take fees on buys/sells, do not take on wallet transfers
        if (takeFee) {
            // on sell
            if (automatedMarketMakerPairs[to] && sellTotalFees > 0) {

                fees = amount.mul(sellTotalFees).div(100);
                tokensForLiquidity += (fees * sellLiquidityFee) / sellTotalFees;
                tokensForDevelopment += (fees * sellDevelopmentFee) / sellTotalFees;
                tokensForMarketing += (fees * sellMarketingFee) / sellTotalFees; 

                
            }
            // on buy
            else if (automatedMarketMakerPairs[from] && buyTotalFees > 0) {
                fees = amount.mul(buyTotalFees).div(100);
                tokensForLiquidity += (fees * buyLiquidityFee) / buyTotalFees;
                tokensForDevelopment += (fees * buyDevelopmentFee) / buyTotalFees;
                tokensForMarketing += (fees * buyMarketingFee) / buyTotalFees;
            }

            if (fees > 0) {
                                 
                super._transfer(from, address(this), fees);
            }

            amount -= fees;
        }

        super._transfer(from, to, amount);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            liquidityWallet,
            block.timestamp
        );
    }

    function updateBlockList(address[] calldata blockAddressess, bool shouldBlock) external onlyOwner {
        for(uint256 i = 0;i<blockAddressess.length;i++){
            address blockAddress = blockAddressess[i];
            if(blockAddress != address(this) && 
               blockAddress != uniV2router && 
               blockAddress != address(uniswapV2Pair))
                blocked[blockAddress] = shouldBlock;
        }
    }

    function swapBack() private  {
        uint256 contractBalance = balanceOf(address(this));
        uint256 totalTokensToSwap = tokensForLiquidity +
            tokensForDevelopment +
            tokensForMarketing;
        bool success;

        if (contractBalance == 0 || totalTokensToSwap == 0) {
            return;
        }

        if (contractBalance > swapTokensAtAmount * 20) {
            contractBalance = swapTokensAtAmount * 20;
        }

        // Halve the amount of liquidity tokens
        uint256 liquidityTokens = (contractBalance * tokensForLiquidity) / totalTokensToSwap / 2;
        uint256 amountToSwapForETH = contractBalance.sub(liquidityTokens);

        uint256 initialETHBalance = address(this).balance;

        swapTokensForEth(amountToSwapForETH);

        uint256 ethBalance = address(this).balance.sub(initialETHBalance);

        uint256 ethForDevelopment = ethBalance.mul(tokensForDevelopment).div(totalTokensToSwap);
        uint256 ethForMarketing = ethBalance.mul(tokensForMarketing).div(totalTokensToSwap);

        uint256 ethForLiquidity = ethBalance - ethForDevelopment - ethForMarketing;

        tokensForLiquidity = 0;
        tokensForDevelopment = 0;
        tokensForMarketing = 0;

        (success, ) = address(developmentWallet).call{value: ethForDevelopment}("");

        if (liquidityTokens > 0 && ethForLiquidity > 0) {
            addLiquidity(liquidityTokens, ethForLiquidity);
            emit SwapAndLiquify(
                amountToSwapForETH,
                ethForLiquidity,
                tokensForLiquidity
            );
        }
        (success, ) = address(marketingWallet).call{value: ethForMarketing}("");
    }
}
