// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface ISecureChainlinkOracle {
    function getLatestPrice(address primaryFeed_, uint256 staleThreshold_)
        external
        view
        returns (int256 price, uint8 decimals);
}
