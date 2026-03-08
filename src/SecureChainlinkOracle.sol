// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./interfaces/AggregatorV3Interface.sol";

contract SecureChainlinkOracle {
    error PriceFeedUnavailable(address priceFeedAddress);
    constructor() {}

    function getLatestPrice(address primaryFeed_, uint256 staleThreshold_)
        external
        view
        returns (int256 price, uint8 decimals)
    {
        require(primaryFeed_ != address(0), "Primary feed address required");
        require(staleThreshold_ > 0, "Stale threshold must be positive");

        try AggregatorV3Interface(primaryFeed_).latestRoundData() {
            (, int256 answer,, uint256 updatedAt,) = AggregatorV3Interface(primaryFeed_).latestRoundData();

            require(answer > 0, "Primary feed: price <= 0");
            require(updatedAt > 0, "Primary feed: invalid timestamp");
            require(block.timestamp - updatedAt <= staleThreshold_, "Primary feed: stale");

            price = answer;
            decimals = AggregatorV3Interface(primaryFeed_).decimals();
        } catch {
            revert PriceFeedUnavailable(primaryFeed_);
        }
    }
}
