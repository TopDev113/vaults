// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./external/ERC20.sol";
import "./Vault.sol";

/// @title VaultFactory
/// @author TransmissionsDev + JetJadeja
/// @notice Factory contract, deploying proxy implementations.
contract VaultFactory {
    /// @notice Deploy a new Vault contract.
    /// @param token Address of the ERC20 token that the Vault will earn yield on.
    /// @return vault The Vault contract.
    function deploy(ERC20 token) external returns (Vault vault) {
        // Generate a 32 byte salt for the create2 deployment.
        bytes32 salt = keccak256(abi.encode(token));
        // Use the create2 opcode to deploy the Vault contract.
        vault = new Vault{salt: salt}(token);
    }
}
