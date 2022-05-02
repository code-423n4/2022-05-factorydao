// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.9;

/// @title A library for merkle trees
/// @author metapriest
/// @notice This library is used to check merkle proofs very efficiently.
/// @dev Each additional proof element adds ~1000 gas
library MerkleLib {

    /// @notice Check the merkle proof to determine whether leaf data was included in dataset represented by merkle root
    /// @dev Leaf is pre-hashed to allow calling contract to implement whatever hashing scheme they want
    /// @param root root hash of merkle tree that is the destination of the hash chain
    /// @param leaf the pre-hashed leaf data, the starting point of the proof
    /// @param proof the array of hashes forming a hash chain from leaf to root
    /// @return true if proof is correct, else false
    function verifyProof(bytes32 root, bytes32 leaf, bytes32[] memory proof) public pure returns (bool) {
        bytes32 currentHash = leaf;

        // the proof is all siblings of the ancestors of the leaf (including the sibling of the leaf itself)
        // each iteration of this loop steps one layer higher in the merkle tree
        for (uint i = 0; i < proof.length; i += 1) {
            currentHash = parentHash(currentHash, proof[i]);
        }

        // does the result match the expected root? if so this leaf was committed to when the root was posted
        // else we must assume the data was not included
        return currentHash == root;
    }

    /// @notice Compute the hash of the parent node in the merkle tree
    /// @dev The arguments are sorted to remove ambiguity about tree definition
    /// @param a hash of left child node
    /// @param b hash of right child node
    /// @return hash of sorted arguments
    function parentHash(bytes32 a, bytes32 b) public pure returns (bytes32) {
        if (a < b) {
            return keccak256(abi.encode(a, b));
        } else {
            return keccak256(abi.encode(b, a));
        }
    }

}
