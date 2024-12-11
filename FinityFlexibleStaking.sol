// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
 
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
 
contract FinityFlexibleStaking is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;
    IERC20 public finityToken;
    uint256 public apy;
    uint256 public totalStaked;
    address public multiSignTreasuryWallet;
 
    struct StakeInfo {
        uint256 amount;
        uint256 startTime;
    }
 
    mapping(address => StakeInfo) public stakes;
 
    event Staked(address indexed user, uint256 amount, uint256 time);
    event Unstaked(address indexed user, uint256 principal, uint256 reward, uint256 time);
    event finityTokenAddressUpdated(address indexed newAddress);
    event APYUpdated(uint256 newAPY);
 
    constructor(address _multiSigWallet, uint256 _initialAPY, address _finityToken) Ownable(_multiSigWallet) {
        require(_multiSigWallet != address(0), "Invalid wallet");
        multiSignTreasuryWallet=_multiSigWallet;
        finityToken = IERC20(_finityToken);
        apy = _initialAPY;
    }
 
    function updateAPY(uint256 _newAPY) external onlyOwner {
        require(_newAPY > 0 && _newAPY<100, "APY > 0");
        apy = _newAPY;
        emit APYUpdated(_newAPY);
    }
 
    function stake(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Amount > 0");
        finityToken.safeTransferFrom(msg.sender, address(this), _amount);
 
        // Calculate any existing reward before updating
        uint256 existingReward = calculateReward(msg.sender);
        StakeInfo storage stakeInfo = stakes[msg.sender];
        // Update principal with new amount and add accurate interest
        stakeInfo.amount += _amount + existingReward;
        stakeInfo.startTime = block.timestamp;
        // Update total staked in the contract
        totalStaked += _amount + existingReward;
 
        emit Staked(msg.sender, _amount, block.timestamp);
    }
 
    // User can unstake tokens and receive their rewards
    function unstake() external nonReentrant {
        StakeInfo storage stakeInfo = stakes[msg.sender];
        require(stakeInfo.amount > 0, "No stake");
 
        // Calculate total reward
        uint256 reward = calculateReward(msg.sender);
        uint256 totalAmount = stakeInfo.amount + reward;
 
        require(
            finityToken.balanceOf(address(this)) >= totalAmount,
            "Low balance in contract"
        );
 
        // Reset user's stake data
        uint256 principal = stakeInfo.amount;
        stakeInfo.amount = 0;
        stakeInfo.startTime = 0;
 
        // Update total staked in the contract
        totalStaked -= principal;
 
        finityToken.safeTransfer(msg.sender, totalAmount);
 
        emit Unstaked(msg.sender, principal, reward, block.timestamp);
    }
 
    function calculateReward(address _user) public view returns (uint256) {
        StakeInfo storage stakeInfo = stakes[_user];
        if (stakeInfo.amount == 0) {
            return 0;
        }
        uint256 stakingDuration = (block.timestamp - stakeInfo.startTime) / 1 days; // staking duration in days
        uint256 dailyReward = (stakeInfo.amount * apy) / 100 / 365;
        return dailyReward * stakingDuration;
    }
 
    function getUserStake(address user) external view returns (uint256 amount, uint256 startTime) {
        require(user != address(0), "Invalid address");
        StakeInfo storage stakeInfo = stakes[user];
        return (stakeInfo.amount, stakeInfo.startTime);
    }
 
    function getContractBal(address _tokenAddress) public view returns (uint256) {
        require(_tokenAddress != address(0), "Invalid token address");
        return IERC20(_tokenAddress).balanceOf(address(this));
    }
 
    function withdrawTokens(address tokenAddress, uint256 amount)
        external
        onlyOwner
    {
        IERC20 token = IERC20(tokenAddress);
        require(
            token.balanceOf(address(this)) > 0,
            "Insufficient token"
        );
        if (token.balanceOf(address(this)) < amount) {
            amount = token.balanceOf(address(this));
        }
 
        token.safeTransfer(multiSignTreasuryWallet, amount);
    }
 
    function updateTokenAddress(address _tokenAddress) external onlyOwner {
        require(_tokenAddress != address(0), "Invalid address");
        finityToken = IERC20(_tokenAddress);
        emit finityTokenAddressUpdated(_tokenAddress);
    }
 
    function withdrawETH(uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "Insufficient ETH balance");
        payable(multiSignTreasuryWallet).transfer(amount);
    }
}
 
 
