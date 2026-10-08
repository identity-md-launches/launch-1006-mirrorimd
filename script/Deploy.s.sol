// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {MirrorIMD} from "../src/MirrorIMD.sol";

/// @notice Direct deployment rehearsal; the network launch uses the token creation code instead.
contract Deploy is Script {
    error UnsupportedChain(uint256 chainId);
    error ChainIdMismatch(uint256 expected, uint256 actual);

    function run() external returns (MirrorIMD token) {
        return deploy(vm.envOr("EXPECTED_CHAIN_ID", uint256(0)));
    }

    /// @notice Zero permits local chain 31337 only; Sepolia requires its explicit chain ID.
    /// @dev Tests call this function directly without reading or changing environment variables.
    function deploy(uint256 expectedChainId) public returns (MirrorIMD token) {
        uint256 actual = block.chainid;
        if (actual != 31337 && actual != 11155111) revert UnsupportedChain(actual);
        if (expectedChainId != actual && !(expectedChainId == 0 && actual == 31337)) {
            revert ChainIdMismatch(expectedChainId, actual);
        }

        vm.startBroadcast();
        token = new MirrorIMD();
        vm.stopBroadcast();
    }
}
