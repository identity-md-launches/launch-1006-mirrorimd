// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {MirrorIMD} from "../src/MirrorIMD.sol";

contract TokenHandler is Test {
    MirrorIMD private immutable token;
    address[4] public actors;

    constructor(MirrorIMD token_) {
        token = token_;
        actors = [makeAddr("holder-0"), makeAddr("holder-1"), makeAddr("holder-2"), makeAddr("holder-3")];
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = token.allowance(owner, spender);
        uint256 available = token.balanceOf(owner);
        amount = bound(amount, 0, allowed < available ? allowed : available);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        assertEq(token.allowance(owner, spender), allowed == type(uint256).max ? allowed : allowed - amount);
    }
}

contract MirrorIMDInvariantTest is Test {
    MirrorIMD private token;
    TokenHandler private handler;

    function setUp() public {
        token = new MirrorIMD();
        handler = new TokenHandler(token);
        assertTrue(token.transfer(handler.actors(0), token.totalSupply()));
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = TokenHandler.move.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.spend.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyAndSumOfBalancesRemainConstant() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        assertEq(sum, token.totalSupply());
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }
}
