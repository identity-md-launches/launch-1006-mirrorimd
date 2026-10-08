// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {MirrorIMD} from "../src/MirrorIMD.sol";

contract DeployTest is Test {
    Deploy private script;

    function setUp() public {
        script = new Deploy();
    }

    function test_localRehearsal() public {
        vm.chainId(31337);
        _checkDeployment(0);
    }

    function test_explicitLocalChain() public {
        vm.chainId(31337);
        _checkDeployment(31337);
    }

    function test_explicitSepoliaChain() public {
        vm.chainId(11155111);
        _checkDeployment(11155111);
    }

    function test_missingSepoliaConfirmationReverts() public {
        vm.chainId(11155111);
        vm.expectRevert(abi.encodeWithSelector(Deploy.ChainIdMismatch.selector, 0, 11155111));
        script.deploy(0);
    }

    function test_chainMismatchReverts() public {
        vm.chainId(31337);
        vm.expectRevert(abi.encodeWithSelector(Deploy.ChainIdMismatch.selector, 11155111, 31337));
        script.deploy(11155111);
    }

    function test_unsupportedChainReverts() public {
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(Deploy.UnsupportedChain.selector, 1));
        script.deploy(1);
    }

    function _checkDeployment(uint256 expectedChainId) private {
        vm.recordLogs();
        MirrorIMD token = script.deploy(expectedChainId);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(token));
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        // Discover the simulated broadcaster from the mint; do not assume Foundry's caller.
        address recipient = address(uint160(uint256(logs[0].topics[2])));
        assertTrue(recipient != address(0));
        assertEq(token.balanceOf(recipient), 1_000_000_000 ether);
        assertEq(token.totalSupply(), 1_000_000_000 ether);
    }
}
