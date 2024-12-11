// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract FinnityPreSale is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    mapping(address => uint256) public tokensBought;

    address public multiSignTreasuryWallet;
    IERC20 immutable finityToken;
    IERC20 immutable usdtToken;
    uint256 public tokenPrice; // Token Price is per USDT eg. 1USDT=2Finity and must be with proper 18 decimals format

    AggregatorV3Interface public priceFeed; // Chainlink price feed;
    uint256 public priceStaleThreshold = 1 hours;
    uint256 public minThresholdLimit; // Minimum buy value in USDT

    event TokensPurchased(address indexed buyer, uint256 amount);
    event FinnityTokenAddressUpdated(address indexed newAddress);
    event AggregatorPairUpdated(address indexed newPairAddress);
    event minThresholdUpdated(uint256 indexed newMinThresholdLimit);
    event TokenPriceUpdated(uint256 oldPrice, uint256 newPrice);
    event TokensWithdrawn(address indexed admin, uint256 amount);
    event ETHWithdrawn(address indexed admin, uint256 amount);
    event TreasuryWalletUpdated(address indexed newWallet);
    
    // _tokenPrice should be in 18 decimals format.
    // _minBuyValueInUSDT value should be in usdt with 6 decimals
    constructor(uint256 _tokenPrice,address multiSigWallet,uint256 _minThresholdLimit,address _finityToken ,address _usdttoken)
        Ownable(multiSigWallet)
    {
        finityToken = IERC20(_finityToken); //FinityToken Contract Address
        usdtToken = IERC20(_usdttoken); // USDT Contract Address
        tokenPrice = _tokenPrice;
        multiSignTreasuryWallet = multiSigWallet;
        minThresholdLimit = _minThresholdLimit;
        priceFeed = AggregatorV3Interface(0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46); // USDT/ETH Pair Price Feed Address on mainnet
    }
    
      function getETHPriceInUSDT() public view returns (uint256) {
        (, int256 price, , uint256 updatedAt, ) = priceFeed.latestRoundData();
        uint256 priceETHInUSDT= 1e24 * uint256(price);
        require(block.timestamp - updatedAt <= priceStaleThreshold,"Price data is stale");
        return uint256(priceETHInUSDT);
    }

    function updateTreasuryWallet(address _multiSigWallet) external onlyOwner {
        require(_multiSigWallet != address(0), "Invalid Treasury Wallet");
        require(multiSignTreasuryWallet != _multiSigWallet, "Use Diff. Wallet");
        multiSignTreasuryWallet = _multiSigWallet;
        emit TreasuryWalletUpdated(_multiSigWallet);
    }

    function buyTokens() external payable whenNotPaused nonReentrant {
        require(msg.value > 0, "Must send some ETH");

        uint256 price = getETHPriceInUSDT();
        uint256 ethAmountInUSDT = price * msg.value / 1e24;
        require(ethAmountInUSDT >= (minThresholdLimit/1e6), "Less Than Threshold");
        uint256 finityTokQty = ethAmountInUSDT * tokenPrice;

        require(finityToken.balanceOf(address(this)) >= finityTokQty,"Insufficient Finity bal");
        finityToken.safeTransfer(msg.sender, finityTokQty);

        (bool success, ) = payable(multiSignTreasuryWallet).call{value: msg.value}("");
        require(success, "Failed to transfer ETH");

        tokensBought[msg.sender] = tokensBought[msg.sender] + finityTokQty;
        emit TokensPurchased(msg.sender, finityTokQty);
    }

    function withdrawProfit() public {
        uint256 totalBalance = address(this).balance;
        (bool sent,)= multiSignTreasuryWallet.call{value:totalBalance }("");
        if(sent == false) revert("ETH Transfer Failed");
    }

    function buyTokenWithUsdt(uint256 usdtAmount)
        external
        whenNotPaused  
        nonReentrant                                
    {
        require(usdtAmount > 0, "Must send some USDT");
        require(usdtAmount >= minThresholdLimit, "Less Than Threshold");
    
        // Calculate the number of FinityTokens to be bought
        uint256 finityTokAmount = usdtAmount * tokenPrice / 1e6; // Adjust for 18 decimals
        require(finityTokAmount > 0, "Finity too Small");

        // Check if there are enough tokens in the contract
        require(
            finityToken.balanceOf(address(this)) >= (finityTokAmount),
            "Insufficient Finity bal"
        );

        // Transfer USDT to the treasury wallet
        usdtToken.safeTransferFrom(
            msg.sender,
            multiSignTreasuryWallet,
            usdtAmount
        );

        // Transfer Finity to the buyer
        finityToken.safeTransfer(msg.sender, finityTokAmount);

        tokensBought[msg.sender] = tokensBought[msg.sender] + finityTokAmount;

        emit TokensPurchased(msg.sender, finityTokAmount);
    }

    function withdrawTokens(address tokenAddress, uint256 amount)
        external
        onlyOwner
    {
        require(amount > 0, "Amount must be greater than 0");
        IERC20 token = IERC20(tokenAddress);
        require(
            token.balanceOf(address(this)) > 0,
            "Insufficient token"
        );
        if (token.balanceOf(address(this)) < amount) {
            amount = token.balanceOf(address(this));
        }
        token.safeTransfer(multiSignTreasuryWallet, amount);
        emit TokensWithdrawn(msg.sender, amount); // Emit event
    }

    // Token Price must be in 18 decimals.
    function setTokenPrice(uint256 _newTokenPrice) external onlyOwner {
        require(_newTokenPrice > 0, "Price must be greater than 0");
        tokenPrice = _newTokenPrice;
        emit TokenPriceUpdated(tokenPrice, _newTokenPrice); // Emit event
    }
    
    // Update the minimum buy value in USDT
    function setMinThreshold(uint256 _minThresholdLimit) external onlyOwner {
        require(_minThresholdLimit > 0, "Threshold must be greater than 0");
        minThresholdLimit = _minThresholdLimit;
        emit minThresholdUpdated(_minThresholdLimit); // Emit event
    }

    function updateAggregatorPairAddress(address _newPairAddress)
        external
        onlyOwner
    {
        require(_newPairAddress != address(0), "Invalid Pair address");
        priceFeed = AggregatorV3Interface(_newPairAddress); // ETH/USDT Pair Price Feed Address
        emit AggregatorPairUpdated(_newPairAddress);
    }

    function getContractBal(address _tokenAddress)
        public
        view
        returns (uint256)
    {
        require(_tokenAddress != address(0), "Invalid user address"); 
        return IERC20(_tokenAddress).balanceOf(address(this));
    }

    receive() external payable {}
}
