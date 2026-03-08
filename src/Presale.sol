// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ISecureChainlinkOracle.sol";

/// @title Presale
/// @author Javier Herrador
/// @notice Manages a multi-phase token presale accepting ERC20 tokens and native ETH as payment.
/// @dev Inherits from OpenZeppelin's `Ownable`. Integrates Chainlink price feeds via
///      `ISecureChainlinkOracle` to compute token prices on-chain. Supports a blacklist
///      to block specific addresses from participating, and a whitelist of accepted ERC20
///      payment tokens. Each phase has its own token cap and price.
contract Presale is Ownable {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // State Variables
    // -------------------------------------------------------------------------

    /// @notice Address that receives all funds raised during the presale.
    address public fundsReceiverAddress;

    /// @notice Address of the ERC20 token being sold in the presale.
    address public sellingTokenAddress;

    /// @notice Maximum total number of tokens available for sale across all phases.
    /// @dev Expressed in the selling token's smallest unit.
    uint256 public maxSellingAmount;

    /// @notice Unix timestamp at which the presale starts accepting purchases.
    uint256 public startingTime;

    /// @notice Unix timestamp at which the presale stops accepting purchases.
    uint256 public endingTime;

    /// @notice Index of the currently active presale phase (0-based).
    /// @dev Incremented automatically when a phase's token cap is reached.
    uint256 public currentPhase;

    /// @notice Mapping from ERC20 token address to its whitelist configuration.
    /// @dev Only tokens present here with `whitelisted = true` are accepted as payment.
    mapping(address => ERC20WhitelistedToken) public whitelistedTokens;

    /// @notice Three-phase presale configuration.
    /// @dev Each entry is a dynamic array with at least two elements:
    ///      - [0]: Cumulative token cap for the phase.
    ///      - [1]: Token price for the phase (in USD with 6 decimals, i.e. 1e6 = $1).
    ///      - [2] (phase 2 only): Unix timestamp deadline for the final phase.
    uint256[][3] public phases;

    /// @notice Mapping from user address to blacklist status.
    /// @dev Blacklisted addresses cannot call `buyWithERC20` or `buyWithEther`.
    mapping(address => bool) public blacklistedUsers;

    /// @notice Mapping from user address to the number of presale tokens allocated.
    /// @dev Tokens are claimable after the presale ends via `claim()`.
    mapping(address => uint256) public userTokenBalance;

    /// @notice Total number of presale tokens sold so far across all phases.
    uint256 public totalSold;

    // -------------------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------------------

    /// @notice Configuration for a whitelisted ERC20 payment token.
    /// @param whitelisted Whether the token is accepted as payment.
    /// @param priceFeed Address of the Chainlink price feed for this token.
    /// @param threshold Maximum acceptable age (in seconds) of the Chainlink price data.
    struct ERC20WhitelistedToken {
        bool whitelisted;
        address priceFeed;
        uint256 threshold;
    }

    /// @notice Configuration for the native ETH Chainlink price feed.
    /// @param priceFeed Address of the Chainlink ETH/USD price feed.
    /// @param threshold Maximum acceptable age (in seconds) of the Chainlink price data.
    struct EtherPriceFeed {
        address priceFeed;
        uint256 threshold;
    }

    // -------------------------------------------------------------------------
    // Private / Internal State
    // -------------------------------------------------------------------------

    /// @notice ETH price feed configuration used when purchasing with native ETH.
    EtherPriceFeed etherPriceFeed;

    /// @notice Address of the deployed `SecureChainlinkOracle` contract.
    address chainLinkOracleAddress;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a user successfully purchases presale tokens.
    /// @param buyer Address of the user who made the purchase.
    /// @param amount Number of presale tokens allocated to the buyer.
    event TokensPurchased(address buyer, uint256 amount);

    /// @notice Emitted when a new ERC20 payment token is added to the whitelist.
    /// @param tokenAddress Address of the whitelisted ERC20 token.
    /// @param priceFeed Address of the Chainlink price feed associated with the token.
    /// @param threshold Staleness threshold in seconds for the price feed.
    event PermittedTokenAdded(address tokenAddress, address priceFeed, uint256 threshold);

    /// @notice Emitted when an ERC20 payment token is removed from the whitelist.
    /// @param tokenAddress Address of the removed ERC20 token.
    event PermittedTokenDeleted(address tokenAddress);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @notice Initializes the presale contract with all required configuration.
    /// @param fundsReceiverAddress_ Address that will receive all raised funds.
    /// @param maxSellingAmount_ Maximum total number of tokens available for sale.
    /// @param sellingTokenAddress_ Address of the ERC20 token being sold.
    /// @param phases_ Three-phase configuration array. Each element contains
    ///        at minimum a cumulative cap and a phase price (in USD with 6 decimals).
    /// @param startingTime_ Unix timestamp when the presale opens.
    /// @param endingTime_ Unix timestamp when the presale closes. Must be greater than `startingTime_`.
    /// @param chainLinkOracleAddress_ Address of the deployed `SecureChainlinkOracle` contract.
    /// @param etherPriceFeedAddress_ Address of the Chainlink ETH/USD price feed.
    /// @param etherPriceFeedTheshold_ Staleness threshold in seconds for the ETH price feed.
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

    // -------------------------------------------------------------------------
    // External — Purchase Functions
    // -------------------------------------------------------------------------

    /// @notice Purchase presale tokens using a whitelisted ERC20 token.
    /// @param tokenUsedToBuy_ Address of the whitelisted ERC20 token used for payment.
    /// @param amount_ Amount of the payment token to spend, expressed in its smallest unit.
    /// @dev The actual number of presale tokens received is computed from the Chainlink
    ///      price feed of `tokenUsedToBuy_` and the current phase price.
    ///      Excess payment beyond the current phase cap is not charged.
    function buyWithERC20(address tokenUsedToBuy_, uint256 amount_) external {
        require(!blacklistedUsers[msg.sender], "User is blacklisted");
        require(block.timestamp >= startingTime, "Presale not started yet");
        require(block.timestamp <= endingTime, "Presale finished");
        require(totalSold < maxSellingAmount, "Sold out");
        require(amount_ > 0, "Amount cannot be zero");

        uint256 price =
            _getPrice(whitelistedTokens[tokenUsedToBuy_].priceFeed, whitelistedTokens[tokenUsedToBuy_].threshold);

        (uint256 spentAmount, uint256 tokenAmountToReceive) = _getTokenAmountCurrentPhaseTokenBuy(amount_, price);

        _checkCurrentPhase(tokenAmountToReceive);

        totalSold += tokenAmountToReceive;

        require(totalSold <= maxSellingAmount, "Max available selling amount exceeded");

        userTokenBalance[msg.sender] += tokenAmountToReceive;

        IERC20(tokenUsedToBuy_).safeTransferFrom(msg.sender, fundsReceiverAddress, spentAmount);
    }

    /// @notice Purchase presale tokens using native ETH.
    /// @dev The ETH/USD price is fetched from the Chainlink feed configured at construction.
    ///      Any excess ETH beyond the cost of available tokens is refunded to the caller.
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

    // -------------------------------------------------------------------------
    // External — Owner Functions
    // -------------------------------------------------------------------------

    /// @notice Withdraws the full balance of an ERC20 token held by this contract to the owner.
    /// @param tokenAddres_ Address of the ERC20 token to withdraw.
    function emergencyERC20Withdraw(address tokenAddres_) external onlyOwner {
        uint256 contractERC20Balance = IERC20(tokenAddres_).balanceOf(address(this));

        require(contractERC20Balance > 0, "No pending balance to withdraw");

        IERC20(tokenAddres_).safeTransfer(msg.sender, contractERC20Balance);
    }

    /// @notice Withdraws the full ETH balance held by this contract to the owner.
    function emergencyEtherWithdraw() external onlyOwner {
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0, "No pending balance to withdraw");

        (bool success,) = msg.sender.call{value: contractBalance}("");
        require(success, "Transfer failed");
    }

    /// @notice Adds an ERC20 token to the whitelist of accepted payment tokens.
    /// @param tokenAddress_ Address of the ERC20 token to whitelist.
    /// @param priceFeedAddress_ Address of the Chainlink price feed for this token.
    /// @param threshold_ Maximum acceptable age (in seconds) of the price feed data.
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

    /// @notice Removes an ERC20 token from the whitelist of accepted payment tokens.
    /// @param tokenAddress_ Address of the ERC20 token to remove.
    function removeWhitelistedToken(address tokenAddress_) external onlyOwner {
        require(tokenAddress_ != address(0), "Token Address cannot be Zero");
        require(whitelistedTokens[tokenAddress_].whitelisted, "TokenAddress not added");

        delete whitelistedTokens[tokenAddress_];

        emit PermittedTokenDeleted(tokenAddress_);
    }

    /// @notice Adds an address to the blacklist, preventing it from purchasing tokens.
    /// @param user_ Address to blacklist.
    function blacklist(address user_) external onlyOwner {
        require(user_ != address(0), "Token Address cannot be Zero");
        require(!blacklistedUsers[user_], "User already blacklisted");
        blacklistedUsers[user_] = true;
    }

    /// @notice Removes an address from the blacklist, re-enabling it to purchase tokens.
    /// @param user_ Address to remove from the blacklist.
    function removeBlacklist(address user_) external onlyOwner {
        require(user_ != address(0), "Token Address cannot be Zero");
        require(blacklistedUsers[user_], "User not in blacklist");

        blacklistedUsers[user_] = false;
    }

    // -------------------------------------------------------------------------
    // External — User Functions
    // -------------------------------------------------------------------------

    /// @notice Allows a buyer to claim their allocated presale tokens after the presale ends.
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

    // -------------------------------------------------------------------------
    // External — View Functions
    // -------------------------------------------------------------------------

    /// @notice Returns the whitelist configuration for a given ERC20 token.
    /// @param tokenAddress_ Address of the ERC20 token to query.
    /// @return whitelisted Whether the token is currently whitelisted.
    /// @return priceFeed Address of the Chainlink price feed associated with this token.
    /// @return threshold Staleness threshold in seconds for this token's price feed.
    function getWhitelistedToken(address tokenAddress_) external view returns (bool, address, uint256) {
        return (
            whitelistedTokens[tokenAddress_].whitelisted,
            whitelistedTokens[tokenAddress_].priceFeed,
            whitelistedTokens[tokenAddress_].threshold
        );
    }

    // -------------------------------------------------------------------------
    // Internal Functions
    // -------------------------------------------------------------------------

    /// @notice Fetches and normalizes the latest price from a Chainlink price feed.
    /// @param priceFeed_ Address of the Chainlink price feed to query.
    /// @param threshold_ Maximum acceptable age (in seconds) for the returned price.
    /// @return price The latest price normalized to 18 decimals (1e18 = $1).
    /// @dev Calls `ISecureChainlinkOracle.getLatestPrice` which enforces the staleness check.
    ///      Normalizes the result from the feed's native decimals to 18 decimals.
    function _getPrice(address priceFeed_, uint256 threshold_) internal view returns (uint256) {
        (int256 latestPrice, uint8 decimals) =
            ISecureChainlinkOracle(chainLinkOracleAddress).getLatestPrice(priceFeed_, threshold_);

        uint256 price = uint256(latestPrice) * (10 ** (18 - decimals));

        return price;
    }

    /// @notice Computes the amount of ETH to charge and presale tokens to allocate for an ETH purchase.
    /// @param amount_ Amount of ETH sent by the buyer (in wei).
    /// @param price_ Current ETH/USD price normalized to 18 decimals.
    /// @return finalAmount The actual amount of ETH to charge (may be less than `amount_` if
    ///         the purchase hits the phase cap).
    /// @return remainingTokens The number of presale tokens to allocate to the buyer.
    /// @dev If the purchase would exceed the current phase's cumulative cap, only the remaining
    ///      tokens in the phase are allocated and the ETH charge is adjusted proportionally.
    ///      Phase caps are cumulative: phase 1 cap includes phase 0 tokens, etc.
    function _getTokenAmountCurrentPhaseEtherBuy(uint256 amount_, uint256 price_)
        internal
        view
        returns (uint256, uint256)
    {
        uint256 usdValue = amount_ * price_ / 1e18;
        uint256 tokenAmountToReceive = usdValue * 1e6 / phases[currentPhase][1];
        uint256 finalAmount = amount_;
        uint256 remainingTokens = tokenAmountToReceive;

        if (totalSold + tokenAmountToReceive > phases[currentPhase][0]) {
            if (currentPhase == 1) {
                remainingTokens = (phases[currentPhase][0] + phases[currentPhase - 1][0]) - totalSold;
            } else if (currentPhase == 2) {
                remainingTokens =
                    (phases[currentPhase][0] + phases[currentPhase - 1][0] + phases[currentPhase - 2][0]) - totalSold;
            } else if (currentPhase == 0) {
                remainingTokens = phases[currentPhase][0] - totalSold;
            }

            uint256 finalAmountinUSD = remainingTokens * phases[currentPhase][1] / 1e6;
            finalAmount = finalAmountinUSD * 1e18 / price_;
        }

        return (finalAmount, remainingTokens);
    }

    /// @notice Computes the amount of ERC20 token to charge and presale tokens to allocate for an ERC20 purchase.
    /// @param amount_ Amount of the ERC20 payment token provided by the buyer (in its smallest unit).
    /// @param price_ Current price of the payment token in USD, normalized to 18 decimals.
    /// @return finalAmount The actual amount of ERC20 tokens to charge (may be less than `amount_`
    ///         if the purchase hits the phase cap).
    /// @return remainingTokens The number of presale tokens to allocate to the buyer.
    /// @dev If the purchase would exceed the current phase's cumulative cap, only the remaining
    ///      tokens in the phase are allocated and the ERC20 charge is adjusted proportionally.
    ///      Phase caps are cumulative across phases.
    function _getTokenAmountCurrentPhaseTokenBuy(uint256 amount_, uint256 price_)
        internal
        view
        returns (uint256, uint256)
    {
        uint256 usdValue = amount_ * price_ / 1e18;
        uint256 tokenAmountToReceive = usdValue * 1e18 / phases[currentPhase][1];
        uint256 finalAmount = amount_;
        uint256 remainingTokens = tokenAmountToReceive;

        if (totalSold + tokenAmountToReceive > phases[currentPhase][0]) {
            if (currentPhase == 0) {
                remainingTokens = phases[currentPhase][0] - totalSold;
            } else if (currentPhase == 1) {
                remainingTokens = (phases[currentPhase][0] + phases[currentPhase - 1][0]) - totalSold;
            } else if (currentPhase == 2) {
                remainingTokens =
                    (phases[currentPhase][0] + phases[currentPhase - 1][0] + phases[currentPhase - 2][0]) - totalSold;
            }

            uint256 finalAmountinUSD = remainingTokens * phases[currentPhase][1] / 1e6;
            finalAmount = finalAmountinUSD * 1e6 / price_;
        }
        return (finalAmount, remainingTokens);
    }

    // -------------------------------------------------------------------------
    // Private Functions
    // -------------------------------------------------------------------------

    /// @notice Advances `currentPhase` if the current phase's token cap has been reached.
    /// @param amount_ Number of tokens about to be allocated in the current transaction.
    /// @dev Compares `totalSold + amount_` against each phase's cumulative cap.
    ///      Phase 2 also advances if the phase deadline (`phases[2][2]`) has passed.
    ///      This function is called before `totalSold` is incremented.
    function _checkCurrentPhase(uint256 amount_) private {
        if (currentPhase == 0 && totalSold + amount_ == phases[currentPhase][0]) {
            currentPhase++;
        }

        if (currentPhase == 1 && totalSold + amount_ == phases[currentPhase][0] + phases[currentPhase - 1][0]) {
            currentPhase++;
        }

        if (
            currentPhase == 2 && (block.timestamp > phases[currentPhase][2])
                || (totalSold + amount_ == phases[0][0] + phases[1][0] + phases[2][0])
        ) {
            currentPhase++;
        }
    }

    // -------------------------------------------------------------------------
    // Receive
    // -------------------------------------------------------------------------

    /// @notice Allows the contract to receive plain ETH transfers (e.g. from `buyWithEther` refunds).
    receive() external payable {}
}
