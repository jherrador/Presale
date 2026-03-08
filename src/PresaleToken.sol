// SPDX-License-Identifier: LGPL-3.0

pragma solidity 0.8.30;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/// @title PresaleToken
/// @author Javier Herrador
/// @notice ERC20 token used as the asset sold during the presale.
contract PresaleToken is ERC20 {
    /// @notice Deploys the PresaleToken with a given name and symbol.
    /// @param name_ The full name of the token (e.g. "My Presale Token").
    /// @param symbol_ The ticker symbol of the token (e.g. "MPT").
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    /// @notice Mints new tokens to the caller's address.
    /// @param amount_ The amount of tokens to mint, expressed in the token's smallest unit (wei).
    function mint(uint256 amount_) external {
        _mint(msg.sender, amount_);
    }
}
