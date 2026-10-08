// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/IERC6093.sol";
import {MirrorIMD} from "../src/MirrorIMD.sol";

/// @dev Test-only factory: models constructor ownership and subsequent launch transfers.
contract TokenFactoryHarness {
    function deploy(bytes32 salt) external returns (MirrorIMD) {
        return new MirrorIMD{salt: salt}();
    }

    function send(MirrorIMD token, address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }
}

contract MirrorIMDTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    MirrorIMD private token;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new MirrorIMD();
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
    }

    function test_metadataAndSupply() public view {
        assertEq(token.name(), "MirrorIMD");
        assertEq(token.symbol(), "MIRROR");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_constructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        MirrorIMD fresh = new MirrorIMD();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_factoryCreate2ReceivesEverything() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        MirrorIMD launched = factory.deploy(keccak256("launch"));
        assertEq(launched.totalSupply(), SUPPLY);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(address(this)), 0);
        assertEq(launched.balanceOf(address(launched)), 0);
    }

    function test_launchAndClaimTransfersArriveWhole() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        MirrorIMD launched = factory.deploy(keccak256("launch-flows"));
        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("pool-manager");
        uint256 swarm = SUPPLY / 10;
        // Illustrative pool allocation, not a launch economic parameter.
        uint256 seed = SUPPLY / 4;
        uint256 remainder = SUPPLY - swarm - seed;
        assertTrue(factory.send(launched, distributor, swarm));
        assertTrue(factory.send(launched, poolManager, seed));
        assertTrue(factory.send(launched, alice, remainder));
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), swarm);
        assertEq(launched.balanceOf(poolManager), seed);
        assertEq(launched.balanceOf(alice), remainder);

        vm.prank(distributor);
        assertTrue(launched.transfer(bob, swarm));
        assertEq(launched.balanceOf(distributor), 0);
        assertEq(launched.balanceOf(bob), swarm);

        // Exercise the token legs of a purchase and resale, without claiming AMM integration.
        uint256 bought = 1_000 ether;
        vm.prank(poolManager);
        assertTrue(launched.transfer(bob, bought));
        assertEq(launched.balanceOf(bob), swarm + bought);
        vm.prank(bob);
        assertTrue(launched.transfer(poolManager, bought));
        assertEq(launched.balanceOf(poolManager), seed);
        assertEq(launched.balanceOf(bob), swarm);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_transferFullSupplyEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, SUPPLY);
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_selfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferToZeroReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferToZeroAlsoReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
    }

    function test_transferAboveBalanceReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(alice, SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_approveEmitsEventAndOverwrites() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 100);
        assertTrue(token.approve(spender, 100));
        assertEq(token.allowance(address(this), spender), 100);
        assertTrue(token.approve(spender, 25));
        assertEq(token.allowance(address(this), spender), 25);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_transferFromSpendsExactAllowanceAndEmitsTransfer() public {
        assertTrue(token.approve(spender, 100));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 100);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 100));
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY - 100);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_infiniteAllowanceIsPreserved() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_revokedAllowanceCannotBeSpent() public {
        assertTrue(token.approve(spender, 100));
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_unapprovedSpenderCannotMoveTokens() public {
        assertTrue(token.approve(spender, 100));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 100);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromToZeroRollsBackAllowance() public {
        assertTrue(token.approve(spender, 100));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 100);
        assertEq(token.allowance(address(this), spender), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_transferFromInsufficientBalanceRollsBackAllowance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 100));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 100));
        vm.prank(spender);
        token.transferFrom(alice, bob, 100);
        assertEq(token.allowance(alice, spender), 100);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromSelfStillConsumesAllowance() public {
        assertTrue(token.approve(spender, 100));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 60));
        assertEq(token.allowance(address(this), spender), 40);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_zeroTransferFromNeedsNoAllowance() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_noMintBurnPauseSeizeOrUpgradeEntryPoints() public {
        assertTrue(token.transfer(alice, 100));
        string[15] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "pause()",
            "blacklist(address)",
            "freeze(address)",
            "seize(address)",
            "transferOwnership(address)",
            "setMinter(address)",
            "initialize(address)",
            "upgradeTo(address)",
            "setTransfersEnabled(bool)",
            "rebase(uint256)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], alice, 100);
            (bool deployerOk,) = address(token).call(data);
            assertFalse(deployerOk, signatures[i]);
            vm.prank(bob);
            (bool strangerOk,) = address(token).call(data);
            assertFalse(strangerOk, signatures[i]);
        }
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);
        assertEq(token.balanceOf(alice), 100);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));
        assertEq(token.balanceOf(bob), 100);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_runtimeContainsNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
        }
    }

    function testFuzz_transferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_delegatedTransferConservesSupply(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY);
        amount = bound(amount, 0, approved);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), approved - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_overdrawRevertsWithoutMutation(uint256 balance, uint256 excess) public {
        balance = bound(balance, 0, SUPPLY);
        excess = bound(excess, 1, type(uint256).max - balance);
        assertTrue(token.transfer(alice, balance));
        uint256 attempted = balance + excess;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, attempted)
        );
        vm.prank(alice);
        token.transfer(bob, attempted);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_excessAllowanceSpendRevertsWithoutMutation(uint256 allowed, uint256 excess) public {
        allowed = bound(allowed, 0, SUPPLY - 1);
        excess = bound(excess, 1, SUPPLY - allowed);
        assertTrue(token.approve(spender, allowed));
        uint256 attempted = allowed + excess;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, attempted)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, attempted);
        assertEq(token.allowance(address(this), spender), allowed);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }
}
