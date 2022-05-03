// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.9;

import "../interfaces/IERC20.sol";
import "./MerkleLib.sol";

/// @title A factory pattern for merkledrops, that is, airdrops using merkleproofs to compute eligibility
/// @author metapriest, adrian.wachel, marek.babiarz, radoslaw.gorecki
/// @notice This contract is permissionless and public facing. Any fees must be included in the data of the merkle tree.
/// @dev The contract cannot introspect into the contents of the merkle tree, except when provided a merkle proof,
/// @dev therefore the total liabilities of the merkle tree are untrusted and tree balances must be managed separately
contract MerkleDropFactory {
    using MerkleLib for bytes32;

    // the number of airdrops in this contract
    uint public numTrees = 0;

    // this represents a single airdrop
    struct MerkleTree {
        bytes32 merkleRoot;  // merkleroot of tree whose leaves are (address,uint) pairs representing amount owed to user
        bytes32 ipfsHash; // ipfs hash of entire dataset, as backup in case our servers turn off...
        address tokenAddress; // address of token that is being airdropped
        uint tokenBalance; // amount of tokens allocated for this tree
        uint spentTokens; // amount of tokens dispensed from this tree
    }

    // withdrawn[recipient][treeIndex] = hasUserWithdrawnAirdrop
    mapping (address => mapping (uint => bool)) public withdrawn;

    // array-like map for all ze merkle trees (airdrops)
    mapping (uint => MerkleTree) public merkleTrees;

    // every time there's a withdraw
    event WithdrawalOccurred(uint indexed treeIndex, address indexed destination, uint value);

    // every time a tree is added
    event MerkleTreeAdded(uint indexed treeIndex, address indexed tokenAddress, bytes32 newRoot, bytes32 ipfsHash);

    // every time a tree is topped up
    event TokensDeposited(uint indexed treeIndex, address indexed tokenAddress, uint amount);

    /// @notice Add a new merkle tree to the contract, creating a new merkle-drop
    /// @dev Anyone may call this function, therefore we must make sure trees cannot affect each other
    /// @param newRoot root hash of merkle tree representing liabilities == (destination, value) pairs
    /// @param ipfsHash the ipfs hash of the entire dataset, used for redundance so that creator can ensure merkleproof are always computable
    /// @param tokenAddress the address of the token contract that is being distributed
    /// @param tokenBalance the amount of tokens user wishes to use to fund the airdrop, note trees can be under/overfunded
    function addMerkleTree(bytes32 newRoot, bytes32 ipfsHash, address tokenAddress, uint tokenBalance) public {
        // prefix operator ++ increments then evaluates
        merkleTrees[++numTrees] = MerkleTree(
            newRoot,
            ipfsHash,
            tokenAddress,
            0,  // ain't no tokens in here yet
            0   // ain't nobody claimed no tokens yet either
        );
        // you don't get to add a tree without funding it
        depositTokens(numTrees, tokenBalance);
        // I guess we should tell people (interfaces) what happened
        emit MerkleTreeAdded(numTrees, tokenAddress, newRoot, ipfsHash);
    }

    /// @notice Add funds to an existing merkle-drop
    /// @dev Anyone may call this function, the only risk here is that the token contract is malicious, rendering the tree malicious
    /// @param treeIndex index into array-like map of merkleTrees
    /// @param value the amount of tokens user wishes to use to fund the airdrop, note trees can be under/overfunded
    function depositTokens(uint treeIndex, uint value) public {
        // storage since we are editing
        MerkleTree storage merkleTree = merkleTrees[treeIndex];

        // bookkeeping to make sure trees don't share tokens
        merkleTree.tokenBalance += value;

        // transfer tokens, if this is a malicious token, then this whole tree is malicious
        // but it does not effect the other trees
        require(IERC20(merkleTree.tokenAddress).transferFrom(msg.sender, address(this), value), "ERC20 transfer failed");
        emit TokensDeposited(treeIndex, merkleTree.tokenAddress, value);
    }

    /// @notice Claim funds as a recipient in the merkle-drop
    /// @dev Anyone may call this function for anyone else, funds go to destination regardless, it's just a question of
    /// @dev who provides the proof and pays the gas, msg.sender is not used in this function
    /// @param treeIndex index into array-like map of merkleTrees, which tree should we apply the proof to?
    /// @param destination recipient of tokens
    /// @param value amount of tokens that will be sent to destination
    /// @param proof array of hashes bridging from leaf (hash of destination | value) to merkle root
    function withdraw(uint treeIndex, address destination, uint value, bytes32[] memory proof) public {
        // no withdrawing from uninitialized merkle trees
        require(treeIndex <= numTrees, "Provided merkle index doesn't exist");
        // no withdrawing same airdrop twice
        require(!withdrawn[destination][treeIndex], "You have already withdrawn your entitled token.");
        // compute merkle leaf, this is first element of proof
        bytes32 leaf = keccak256(abi.encode(destination, value));
        // storage because we edit
        MerkleTree storage tree = merkleTrees[treeIndex];
        // this calls to MerkleLib, will return false if recursive hashes do not end in merkle root
        require(tree.merkleRoot.verifyProof(leaf, proof), "The proof could not be verified.");
        // close re-entrance gate, prevent double claims
        withdrawn[destination][treeIndex] = true;
        // update struct
        tree.tokenBalance -= value;
        tree.spentTokens += value;
        // transfer the tokens
        // NOTE: if the token contract is malicious this call could re-enter this function
        // which will fail because withdrawn will be set to true
        require(IERC20(tree.tokenAddress).transfer(destination, value), "ERC20 transfer failed");
        emit WithdrawalOccurred(treeIndex, destination, value);
    }

}