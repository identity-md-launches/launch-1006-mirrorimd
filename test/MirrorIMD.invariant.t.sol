// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/IERC6093.sol";
import {MirrorIMD} from "../src/MirrorIMD.sol";

contract TokenHandler is Test {
    MirrorIMD private immutable token;
    address[4] public actors;
    // Independent accounting: initialized from the specification, updated only by requested actions.
    // Using these balances to bound inputs prevents a bad token balance from masking a failure.
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(MirrorIMD token_) {
        token = token_;
        actors = [makeAddr("holder-0"), makeAddr("holder-1"), makeAddr("holder-2"), makeAddr("holder-3")];
        expectedBalance[actors[0]] = 1_000_000_000 ether;
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordMove(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, amount);
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 available = expectedBalance[owner];
        amount = bound(amount, 0, allowed < available ? allowed : available);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        assertEq(token.allowance(owner, spender), allowed == type(uint256).max ? allowed : allowed - amount);
        if (allowed != type(uint256).max) expectedAllowance[owner][spender] -= amount;
        _recordMove(owner, to, amount);
    }

    // Deliberately revisit revocation, one wei, the whole supply, and both sides of infinity.
    function boundaryApproval(uint256 ownerSeed, uint256 spenderSeed, uint8 choice) external {
        uint256[5] memory amounts = [uint256(0), 1, 1_000_000_000 ether, type(uint256).max - 1, type(uint256).max];
        _approve(actors[ownerSeed % actors.length], actors[spenderSeed % actors.length], amounts[choice % 5]);
    }

    function rejectOverdraw(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 attempted = balance + bound(excess, 1, type(uint256).max - balance);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, attempted)
        );
        vm.prank(from);
        token.transfer(to, attempted);
        // No ghost update: every invariant also checks that failures left all accounts unchanged.
    }

    function rejectDelegatedOverdraw(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 excess) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        uint256 attempted = balance + bound(excess, 1, type(uint256).max - balance);
        _approve(owner, spender, attempted);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, attempted)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, attempted);
    }

    function rejectAllowanceOverspend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 allowed)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        allowed = bound(allowed, 0, 1_000_000_000 ether);
        _approve(owner, spender, allowed);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, allowed + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, allowed + 1);
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[owner]);
        if (delegated) _approve(owner, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(delegated ? spender : owner);
        if (delegated) token.transferFrom(owner, address(0), amount);
        else token.transfer(address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        assertEq(token.allowance(owner, spender), amount);
    }

    function _recordMove(address from, address to, uint256 amount) private {
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract MirrorIMDInvariantTest is Test {
    MirrorIMD private token;
    TokenHandler private handler;

    function setUp() public {
        token = new MirrorIMD();
        handler = new TokenHandler(token);
        assertTrue(token.transfer(handler.actors(0), 1_000_000_000 ether));
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = TokenHandler.move.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.spend.selector;
        selectors[3] = TokenHandler.boundaryApproval.selector;
        selectors[4] = TokenHandler.rejectOverdraw.selector;
        selectors[5] = TokenHandler.rejectDelegatedOverdraw.selector;
        selectors[6] = TokenHandler.rejectAllowanceOverspend.selector;
        selectors[7] = TokenHandler.rejectZeroRecipient.selector;
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
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_eachHolderHasExactlyTheirTokens() public view {
        for (uint256 i; i < 4; ++i) {
            address holder = handler.actors(i);
            assertEq(token.balanceOf(holder), handler.expectedBalance(holder), "holder accounting diverged");
        }
    }

    function invariant_allowancesAreIsolatedAndTrackOnlyApprovedSpending() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender), handler.expectedAllowance(owner, spender), "allowance diverged"
                );
            }
            assertEq(token.allowance(owner, address(0)), 0);
        }
    }

    // A reproducible, nonzero sequence checks the model as well as the random campaign.
    function test_handlerSequenceMovesValueAndSurvivesFailures() public {
        handler.boundaryApproval(0, 1, 4);
        handler.spend(0, 1, 2, 100);
        handler.move(2, 3, 40);
        handler.approve(3, 2, 40);
        handler.spend(3, 2, 3, 10); // Self-transfer spends permission, not balance.
        handler.rejectOverdraw(3, 3, 1);
        handler.rejectDelegatedOverdraw(3, 2, 0, 1);
        handler.rejectAllowanceOverspend(2, 3, 0, 0);
        handler.rejectZeroRecipient(0, 1, 1, true);
        handler.rejectZeroRecipient(0, 1, 0, false);
        handler.approve(2, 3, 60);
        handler.spend(2, 3, 0, 60);
        handler.move(3, 0, 40);

        assertEq(token.balanceOf(handler.actors(0)), 1_000_000_000 ether);
        invariant_supplyAndSumOfBalancesRemainConstant();
        invariant_eachHolderHasExactlyTheirTokens();
        invariant_allowancesAreIsolatedAndTrackOnlyApprovedSpending();
    }
}
