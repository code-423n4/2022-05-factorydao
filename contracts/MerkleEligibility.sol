// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.9;

import "../interfaces/IEligibility.sol";
import "./MerkleLib.sol";

/// @title This is an eligibility gate based on merkle trees, basically a scaled up whitelist
/// @author metapriest, adrian.wachel, marek.babiarz, radoslaw.gorecki
/// @notice This gate also allows max withdrawals per address and max withdrawals total
/// @dev Anyone can add a gate, but it doesn't effect anything if it's not connected to a tree in MerkleIdentity
contract MerkleEligibility is IEligibility {
    using MerkleLib for bytes32;

    // the address of the MerkleIdentity contract
    address public gateMaster;

    // This represents a single gate or whitelist
    struct Gate {
        bytes32 root;  // merkle root of whitelist
        uint maxWithdrawalsAddress; // maximum amount of withdrawals per address
        uint maxWithdrawalsTotal;  // maximum total withdrawals allowed, summed across all addresses
        uint totalWithdrawals;  // number of withdrawals already made
    }

    // array-like mapping of gate structs
    mapping (uint => Gate) public gates;
    // count withdrawals per address timesWithdrawn[gateIndex][user] = count
    mapping(uint => mapping(address => uint)) public timesWithdrawn;
    // count the gates
    uint public numGates = 0;

    /// @notice Deployer connects it to MerkleIdentity
    /// @param _gateMaster address of MerkleIdentity contract, which has exclusive right to call passThruGate
    constructor(address _gateMaster) {
        gateMaster = _gateMaster;
    }

    /// @notice Add an gate, or set of eligibility criteria
    /// @dev Anyone may call this, but without connecting it to MerkleIdentity (which only management can do) nothing happens
    /// @param merkleRoot this is the root of the merkle tree with addresses as the leaf data
    /// @param maxWithdrawalsAddress the maximum mints allowed per address by this gate
    /// @param maxWithdrawalsTotal the maximum mints allowed across all addresses
    /// @return index the index of the gate added
    function addGate(bytes32 merkleRoot, uint maxWithdrawalsAddress, uint maxWithdrawalsTotal) external returns (uint index) {
        // increment the number of roots
        numGates += 1;

        gates[numGates] = Gate(merkleRoot, maxWithdrawalsAddress, maxWithdrawalsTotal, 0);
        return numGates;
    }

    /// @notice Get the fields of a particular gate
    /// @param index the index into the gates mapping, which gate are you talking about?
    /// @return root the merkle root for this gate
    /// @return maxWithdrawalsAddress the maximum withdrawals allowed per address
    /// @return maxWithdrawalsTotal the maximum number of withdrawals across all addresses
    /// @return totalWithdrawals the number of withdrawals already made thru this gate
    function getGate(uint index) external view returns (bytes32, uint, uint, uint) {
        Gate memory gate = gates[index];
        return (gate.root, gate.maxWithdrawalsAddress, gate.maxWithdrawalsTotal, gate.totalWithdrawals);
    }

    /// @notice Find out if a given address may pass thru the gate
    /// @dev Note this is called by passThruGate and represents enforcement of the eligibility criteria
    /// @param index which gate are we talking about?
    /// @param recipient the address that wishes to pass thru the gate
    /// @param proof the array of hashes connecting the leaf data to the merkle root
    /// @return eligible true if recipient may pass thru gate
    function isEligible(uint index, address recipient, bytes32[] memory proof) public override view returns (bool eligible) {
        Gate memory gate = gates[index];
        // We need to pack the 20 bytes address to the 32 bytes value, so we call abi.encode
        bytes32 leaf = keccak256(abi.encode(recipient));
        // Check the per-address count first
        bool countValid = timesWithdrawn[index][recipient] < gate.maxWithdrawalsAddress;
        // Then check global count and merkle proof
        return countValid && gate.totalWithdrawals < gate.maxWithdrawalsTotal && gate.root.verifyProof(leaf, proof);
    }

    /// @notice Pass thru the gate, incrementing the counters
    /// @dev This should only be called by the gatemaster, which should be MerkleIdentity
    /// @param index which gate are we passing thru?
    /// @param recipient who is passing thru it?
    /// @param proof merkle proof of whitelist inclusion
    function passThruGate(uint index, address recipient, bytes32[] memory proof) external override {
        require(msg.sender == gateMaster, "Only gatemaster may call this.");

        // close re-entrance gate, prevent double withdrawals
        require(isEligible(index, recipient, proof), "Address is not eligible");

        timesWithdrawn[index][recipient] += 1;
        Gate storage gate = gates[index];
        gate.totalWithdrawals += 1;
    }
}