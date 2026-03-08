// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ISecureChainlinkOracle.sol";

/**
 * @title Presale
 * @author Javier Herrador
 * @notice Contract that manages a token presale with multiple phases.
 * @dev Inherits from OpenZeppelin Ownable. Includes blacklist and permitted payment tokens logic.
 */
contract Presale is Ownable {
    using SafeERC20 for IERC20;

    /// @notice Address where raised funds will be sent
    address public fundsReceiverAddress;

    /// @notice Address of the token being sold in the presale
    address public sellingTokenAddress;

    /// @notice Maximum amount of tokens available for sale
    uint256 public maxSellingAmount;

    /// @notice Time when the sale starts
    uint256 public startingTime;

    /// @notice Time when the sale ends
    uint256 public endingTime;

    /// @notice Time when the sale ends
    uint256 public currentPhase;

    /// @notice Mapping of allowed ERC20 tokens that can be used to buy
    /// @dev token address => permitted status
    mapping(address => ERC20WhitelistedToken) public whitelistedTokens;

    /// @notice Presale phases configuration
    uint256[][3] public phases;

    /// @notice Mapping of blacklisted users
    /// @dev user address => blacklist status
    mapping(address => bool) public blacklistedUsers;

    mapping(address => uint256) public userTokenBalance;

    uint256 public totalSold;

    struct ERC20WhitelistedToken {
        bool whitelisted;
        address priceFeed;
        uint256 threshold;
    }

    struct EtherPriceFeed {
        address priceFeed;
        uint256 threshold;
    }

    EtherPriceFeed etherPriceFeed;

    address chainLinkOracleAddress;

    event TokensPurchased(address buyer, uint256 amount);
    event PermittedTokenAdded(address tokenAddress, address priceFeed, uint256 threshold);
    event PermittedTokenDeleted(address tokenAddress);

    /**
     * @notice Initializes the presale contract
     * @param fundsReceiverAddress_ Address that will receive raised funds
     * @param maxSellingAmount_ Maximum number of tokens available for sale
     * @param sellingTokenAddress_ Address of the ERC20 token being sold
     * @param phases_ Array containing configuration for all presale phases
     * @dev Reverts if zero addresses are provided
     */
    constructor(
        address fundsReceiverAddress_,
        uint256 maxSellingAmount_,
        address sellingTokenAddress_,
        uint256[][3] memory phases_,
        uint256 startingTime_,
        uint256 endingTime_,
        address chainLinkOracleAddress_,
        address etherPriceFeedAddress_,
        uint256 etherPriceFeedTheshold_
    ) Ownable(msg.sender) {
        require(fundsReceiverAddress_ != address(0), "Wrong receiver address");
        require(sellingTokenAddress_ != address(0), "Wrong receiver address");
        require(endingTime_ > startingTime_, "Incorrect presale times");
        fundsReceiverAddress = fundsReceiverAddress_;
        maxSellingAmount = maxSellingAmount_;
        sellingTokenAddress = sellingTokenAddress_;
        startingTime = startingTime_;
        endingTime = endingTime_;
        chainLinkOracleAddress = chainLinkOracleAddress_;

        phases = phases_;

        etherPriceFeed = EtherPriceFeed({priceFeed: etherPriceFeedAddress_, threshold: etherPriceFeedTheshold_});
    }

    /**
     * @notice Allows users to purchase tokens using a permitted stablecoin
     * @param tokenUsedToBuy_ The address of the token used to buy
     * @param amount_ Amount of tokens for buying
     * @dev Reverts if caller is blacklisted
     */

      

    function buyWithERC20(address tokenUsedToBuy_, uint256 amount_) external {
        require(!blacklistedUsers[msg.sender], "User is blacklisted");
        require(block.timestamp >= startingTime, "Presale not started yet");
        require(block.timestamp <= endingTime, "Presale finished");
        require(totalSold < maxSellingAmount, "Sold out");
        require(amount_ > 0, "Amount cannot be zero");

       uint256 price = _getPrice(whitelistedTokens[tokenUsedToBuy_].priceFeed, whitelistedTokens[tokenUsedToBuy_].threshold);

        (uint256 spentAmount, uint256 tokenAmountToReceive) = _getTokenAmountCurrentPhaseTokenBuy(amount_, price);
       
        _checkCurrentPhase(tokenAmountToReceive);

        totalSold += tokenAmountToReceive;

        require(totalSold <= maxSellingAmount, "Max available selling amount exceeded");

        userTokenBalance[msg.sender] += tokenAmountToReceive;

        IERC20(tokenUsedToBuy_).safeTransferFrom(msg.sender, fundsReceiverAddress, spentAmount);

    }
    function buyWithEther() external payable {
        require(!blacklistedUsers[msg.sender], "User is blacklisted");
        require(block.timestamp >= startingTime, "Presale not started yet");
        require(block.timestamp <= endingTime, "Presale finished");
        require(totalSold < maxSellingAmount, "Sold out");
        require(msg.value > 0, "Amount cannot be zero");

        uint256 price = _getPrice(etherPriceFeed.priceFeed, etherPriceFeed.threshold);
        (uint256 spentAmount, uint256 tokenAmountToReceive) = _getTokenAmountCurrentPhaseEtherBuy(msg.value, price);
       
        _checkCurrentPhase(tokenAmountToReceive);

        totalSold += tokenAmountToReceive;

        require(totalSold <= maxSellingAmount, "Max available selling amount exceeded");

        userTokenBalance[msg.sender] += tokenAmountToReceive;

        (bool success,) = fundsReceiverAddress.call{value: spentAmount}("");
        require(success, "Transfer failed");

        (success,) = msg.sender.call{value: msg.value - spentAmount}("");
        require(success, "Transfer failed");

        emit TokensPurchased(msg.sender, tokenAmountToReceive);
    }

    /**
     * @notice Allows the owner to withdraw ERC20 tokens accidentally sent to this contract
     * @param tokenAddres_ Address of the ERC20 token to withdraw
     * @dev
     * - Only callable by the contract owner.
     * - Reverts if contract balance is zero.
     * - Uses SafeERC20 to safely transfer tokens.
     * @custom:security This function is intended for emergency token recovery only.
     */
    function emergencyERC20Withdraw(address tokenAddres_) external onlyOwner {
        uint256 contractERC20Balance = IERC20(tokenAddres_).balanceOf(address(this));

        require(contractERC20Balance > 0, "No pending balance to withdraw");

        IERC20(tokenAddres_).safeTransfer(msg.sender, contractERC20Balance);
    }

    /**
     * @notice Allows the owner to withdraw all ETH held by the contract
     * @dev
     * - Only callable by the contract owner.
     * - Transfers the entire contract ETH balance.
     * - Reverts if balance is zero.
     * - Uses low-level call to forward ETH.
     * @custom:security This function is intended for emergency ETH recovery only.
     */
    function emergencyEtherWithdraw() external onlyOwner {
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0, "No pending balance to withdraw");

        (bool success,) = msg.sender.call{value: contractBalance}("");
        require(success, "Transfer failed");
    }

    /**
     * @notice Adds an ERC20 token to the whitelisted payment list
     * @param tokenAddress_ Address of the ERC20 token to whitelist
     * @dev Only callable by the owner. Verifies that the address is a contract.
     */
    function addWhitelistedToken(address tokenAddress_, address priceFeedAddress_, uint256 threshold_)
        external
        onlyOwner
    {
        require(tokenAddress_ != address(0), "Token Address cannot be Zero");
        require(priceFeedAddress_ != address(0), "PriceFeed Address cannot be Zero");
        require(!whitelistedTokens[tokenAddress_].whitelisted, "TokenAddress already added");

        whitelistedTokens[tokenAddress_].whitelisted = true;
        whitelistedTokens[tokenAddress_].priceFeed = priceFeedAddress_;
        whitelistedTokens[tokenAddress_].threshold = threshold_;

        emit PermittedTokenAdded(tokenAddress_, priceFeedAddress_, threshold_);
    }

    function removeWhitelistedToken(address tokenAddress_) external onlyOwner {
        require(tokenAddress_ != address(0), "Token Address cannot be Zero");
        require(whitelistedTokens[tokenAddress_].whitelisted, "TokenAddress not added");

        delete whitelistedTokens[tokenAddress_];

        emit PermittedTokenDeleted(tokenAddress_);
    }

    /**
     * @notice Blacklists a user from participating in the presale
     * @param user_ Address of the user to blacklist
     * @dev Only callable by the owner. Reverts if already blacklisted.
     */
    function blacklist(address user_) external onlyOwner {
        require(user_ != address(0), "Token Address cannot be Zero");
        require(!blacklistedUsers[user_], "User already blacklisted");
        blacklistedUsers[user_] = true;
    }

    /**
     * @notice Removes a user from the blacklist
     * @param user_ Address of the user to remove from blacklist
     * @dev Only callable by the owner. Reverts if user is not blacklisted.
     */
    function removeBlacklist(address user_) external onlyOwner {
        require(user_ != address(0), "Token Address cannot be Zero");
        require(blacklistedUsers[user_], "User not in blacklist");

        blacklistedUsers[user_] = false;
    }

    function claim() external {
        require(block.timestamp >= endingTime, "Presale not ended");
        require(userTokenBalance[msg.sender] > 0, "Zero tokens allocated");
        require(
            IERC20(sellingTokenAddress).balanceOf(address(this)) > userTokenBalance[msg.sender], "Not enough tokens"
        );

        uint256 amount = userTokenBalance[msg.sender];
        delete userTokenBalance[msg.sender];

        IERC20(sellingTokenAddress).safeTransfer(msg.sender, amount);
    }

    function getWhitelistedToken(address tokenAddress_) external view returns(bool, address, uint256){
        return (whitelistedTokens[tokenAddress_].whitelisted, whitelistedTokens[tokenAddress_].priceFeed, whitelistedTokens[tokenAddress_].threshold);
    }

    function _getPrice(address priceFeed_, uint256 threshold_) internal view returns (uint256) {
        (int256 latestPrice, uint8 decimals) =
            ISecureChainlinkOracle(chainLinkOracleAddress).getLatestPrice(priceFeed_, threshold_);

        uint256 price = uint256(latestPrice) * (10 ** (18 - decimals));

        return price;
    }

    function _getTokenAmountCurrentPhaseEtherBuy(uint256 amount_, uint256 price_) internal view returns(uint256, uint256){
        uint256 usdValue = amount_ * price_ / 1e18;
        uint256 tokenAmountToReceive = usdValue * 1e6 / phases[currentPhase][1];
        uint256 finalAmount = amount_;
        uint256 remainingTokens = tokenAmountToReceive;
        
        
        if (totalSold + tokenAmountToReceive > phases[currentPhase][0]){
            if(currentPhase == 1)
                remainingTokens = (phases[currentPhase][0] + phases[currentPhase-1][0]) - totalSold;
            else if (currentPhase == 2)
                remainingTokens = (phases[currentPhase][0] + phases[currentPhase-1][0]+ phases[currentPhase-2][0])  - totalSold;
            else if(currentPhase == 0)
                remainingTokens = phases[currentPhase][0] - totalSold;
            
            uint256 finalAmountinUSD = remainingTokens * phases[currentPhase][1] / 1e6;
            finalAmount = finalAmountinUSD * 1e18 / price_;
        }

        return (finalAmount, remainingTokens);
    }

    function _getTokenAmountCurrentPhaseTokenBuy(uint256 amount_, uint256 price_) internal view returns(uint256, uint256){
        uint256 usdValue = amount_ * price_ / 1e18;
        uint256 tokenAmountToReceive = usdValue * 1e18/ phases[currentPhase][1];
        uint256 finalAmount = amount_;
        uint256 remainingTokens = tokenAmountToReceive;

        if (totalSold + tokenAmountToReceive > phases[currentPhase][0]){
            if(currentPhase == 0)
                remainingTokens = phases[currentPhase][0] - totalSold;
            else if(currentPhase == 1)
                remainingTokens = (phases[currentPhase][0] + phases[currentPhase-1][0]) - totalSold;
            else if (currentPhase == 2)
                remainingTokens = (phases[currentPhase][0] + phases[currentPhase-1][0]+ phases[currentPhase-2][0])  - totalSold;

            uint256 finalAmountinUSD = remainingTokens * phases[currentPhase][1] / 1e6;
            finalAmount = finalAmountinUSD * 1e6 / price_;
        }
        return (finalAmount, remainingTokens);
    }

    function _checkCurrentPhase(uint256 amount_) private {
        if (currentPhase == 0 && totalSold + amount_ == phases[currentPhase][0])
            currentPhase++;

        if (currentPhase == 1 && totalSold + amount_ == phases[currentPhase][0] + phases[currentPhase-1][0])
            currentPhase++;

        if (currentPhase == 2 && (block.timestamp > phases[currentPhase][2]) || (totalSold + amount_ == phases[0][0] + phases[1][0] + phases[2][0]))
            currentPhase++;

    }

    receive() external payable {}
}
