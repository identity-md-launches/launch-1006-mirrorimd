// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MirrorIMD
/// @notice Fixed-supply MIRROR token. The entire supply belongs to the constructor caller.
/// @dev When deployed through a factory, the factory receives the supply for distribution.
contract MirrorIMD is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("MirrorIMD", "MIRROR") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}

