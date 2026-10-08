// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/IERC6093.sol";
import {MirrorIMD} from "src/MirrorIMD.sol";

/// @dev Complements the deployment and basic ERC-20 tests with arithmetic boundaries and retry sequences.
/// forge-config: default.fuzz.runs = 1000
contract MirrorIMDBoundariesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    MirrorIMD private token;
    address private alice;
    address private bob;
    address private spender;

    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new MirrorIMD();
        alice = makeAddr("boundary-alice");
        bob = makeAddr("boundary-bob");
        spender = makeAddr("boundary-spender");
    }

    function test_oneWeiCanRoundTripWithoutRoundingOrFees() public {
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maxUintTransferRevertsWithoutOverflowOrMutation() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maxUintDelegatedTransferCannotCreateTokens() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maxMinusOneAllowanceIsFiniteAcrossRepeatedSpends() public {
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteApprovalCanBeReducedAndRevoked() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 2));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 2));
        assertEq(token.allowance(address(this), spender), 0);
        _expectAllowanceFailure(address(this), alice, 0, 1);

        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));
        _expectAllowanceFailure(address(this), alice, 0, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
    }

    function test_ownerUsingTransferFromStillNeedsSelfApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);

        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_allRolesSameStillConsumesPermissionAndChecksBalance() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(alice, 3));
        vm.prank(alice);
        assertTrue(token.transferFrom(alice, alice, 1));
        assertEq(token.allowance(alice, alice), 2);
        assertEq(token.balanceOf(alice), 1);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(alice);
        token.transferFrom(alice, alice, 2);
        assertEq(token.allowance(alice, alice), 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_emptySelfTransferCannotCreateBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(alice, 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroDelegatedTransferToZeroStillReverts() public {
        assertTrue(token.approve(spender, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroSpenderRejectedEvenForRevocation() public {
        assertTrue(token.approve(spender, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzz_failedDelegatedSpendCanBeRetriedAfterFunding(uint256 balance, uint256 shortfall, bool infinite)
        public
    {
        balance = bound(balance, 0, SUPPLY - 1);
        shortfall = bound(shortfall, 1, SUPPLY - balance);
        uint256 attempted = balance + shortfall;
        uint256 approved = infinite ? type(uint256).max : attempted;
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, attempted)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, attempted);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);

        assertTrue(token.transfer(alice, shortfall));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, attempted));
        assertEq(token.allowance(alice, spender), infinite ? type(uint256).max : 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), attempted);
        assertEq(token.balanceOf(address(this)), SUPPLY - attempted);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_splitSpendingCannotExceedApproval(uint256 approved, uint256 first) public {
        approved = bound(approved, 1, SUPPLY);
        first = bound(first, 0, approved);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        assertEq(token.allowance(address(this), spender), approved - first);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, approved - first));
        assertEq(token.allowance(address(this), spender), 0);

        _expectAllowanceFailure(address(this), bob, 0, 1);
        assertEq(token.balanceOf(alice), first);
        assertEq(token.balanceOf(bob), approved - first);
        assertEq(token.balanceOf(address(this)), SUPPLY - approved);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_directRoundTripPreservesAllowances(uint256 amount, uint256 approved) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.approve(spender, approved));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_replacingApprovalDoesNotAccumulate(uint256 oldApproval, uint256 replacement) public {
        replacement = bound(replacement, 0, SUPPLY - 1);
        assertTrue(token.approve(spender, oldApproval));
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        _expectAllowanceFailure(address(this), alice, replacement, replacement + 1);
        assertEq(token.allowance(address(this), spender), replacement);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, replacement));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), replacement);
        assertEq(token.balanceOf(address(this)), SUPPLY - replacement);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _expectAllowanceFailure(address owner, address recipient, uint256 allowed, uint256 attempted) private {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, attempted)
        );
        vm.prank(spender);
        token.transferFrom(owner, recipient, attempted);
    }
}
