// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SunlessToken is ERC20 {
    constructor(uint256 initialMint) ERC20("Sunless", "SLS") {
        _mint(msg.sender, initialMint * 10**decimals());
    }
}