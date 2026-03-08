// SPDX-License-Identifier: LGPL-3.0

pragma solidity 0.8.30;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract PresaleToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(uint256 amount_) external {
        _mint(msg.sender, amount_);
    }
}
