// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.9;

import "../interfaces/IERC20.sol";
import "./MerkleLib.sol";

/// @title A factory pattern for merkle-vesting, that is, a time release schedule for tokens, using merkle proofs to scale
/// @author metapriest, adrian.wachel, marek.babiarz, radoslaw.gorecki
/// @notice This contract is permissionless and public facing. Any fees must be included in the data of the merkle tree.
/// @dev The contract cannot introspect into the contents of the merkle tree, except when provided a merkle proof
contract MerkleVesting {
    using MerkleLib for bytes32;

    // the number of vesting schedules in this contract
    uint public numTrees = 0;
    
    // this represents a single vesting schedule for a specific address
    struct Tranche {
        uint totalCoins;  // total number of coins released to an address after vesting is completed
        uint currentCoins; // how many coins are left unclaimed by this address, vested or unvested
        uint startTime; // when the vesting schedule is set to start, possibly in the past
        uint endTime;  // when the vesting schedule will have released all coins
        uint coinsPerSecond; // an intermediate value cached to reduce gas costs, how many coins released every second
        uint lastWithdrawalTime; // the last time a withdrawal occurred, used to compute unvested coins
        uint lockPeriodEndTime; // the first time at which coins may be withdrawn
    }

    // this represents a set of vesting schedules all in the same token
    struct MerkleTree {
        bytes32 rootHash;  // merkleroot of tree whose leaves are (address,uint,uint,uint,uint) representing vesting schedules
        bytes32 ipfsHash; // ipfs hash of entire dataset, used to reconstruct merkle proofs if our servers go down
        address tokenAddress; // token that the vesting schedules will be denominated in
        uint tokenBalance; // current amount of tokens deposited to this tree, used to make sure trees don't share tokens
    }

    // initialized[recipient][treeIndex] = wasItInitialized?
    mapping (address => mapping (uint => bool)) public initialized;

    // array-like sequential map for all the vesting schedules
    mapping (uint => MerkleTree) public merkleTrees;

    // tranches[recipient][treeIndex] = initializedVestingSchedule
    mapping (address => mapping (uint => Tranche)) public tranches;

    // every time there's a withdrawal
    event WithdrawalOccurred(uint indexed treeIndex, address indexed destination, uint numTokens, uint tokensLeft);

    // every time a tree is added
    event MerkleRootAdded(uint indexed treeIndex, address indexed tokenAddress, bytes32 newRoot, bytes32 ipfsHash);

    // every time a tree is topped up
    event TokensDeposited(uint indexed treeIndex, address indexed tokenAddress, uint amount);

    /// @notice Add a new merkle tree to the contract, creating a new merkle-vesting-schedule
    /// @dev Anyone may call this function, therefore we must make sure trees cannot affect each other
    /// @dev Root hash should be built from (destination, totalCoins, startTime, endTime, lockPeriodEndTime)
    /// @param newRoot root hash of merkle tree representing vesting schedules
    /// @param ipfsHash the ipfs hash of the entire dataset, used for redundance so that creator can ensure merkleproof are always computable
    /// @param tokenAddress the address of the token contract that is being distributed
    /// @param tokenBalance the amount of tokens user wishes to use to fund the airdrop, note trees can be under/overfunded
    function addMerkleRoot(bytes32 newRoot, bytes32 ipfsHash, address tokenAddress, uint tokenBalance) public {
        // prefix operator ++ increments then evaluates
        merkleTrees[++numTrees] = MerkleTree(
            newRoot,
            ipfsHash,
            tokenAddress,
            0    // no funds have been allocated to the tree yet
        );
        // fund the tree now
        depositTokens(numTrees, tokenBalance);
        emit MerkleRootAdded(numTrees, tokenAddress, newRoot, ipfsHash);
    }

    /// @notice Add funds to an existing merkle-vesting-schedule
    /// @dev Anyone may call this function, the only risk here is that the token contract is malicious, rendering the tree malicious
    /// @dev If the tree is over-funded, excess funds are lost. No clear way to get around this without zk-proofs
    /// @param treeIndex index into array-like map of merkleTrees
    /// @param value the amount of tokens user wishes to use to fund the airdrop, note trees can be underfunded
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

    /// @notice Called once per recipient of a vesting schedule to initialize the vesting schedule
    /// @dev Anyone may call this function, the only risk here is that the token contract is malicious, rendering the tree malicious
    /// @dev If the tree is over-funded, excess funds are lost. No clear way to get around this without zk-proofs of global tree stats
    /// @dev The contract has no knowledge of the vesting schedules until this function is called
    /// @param treeIndex index into array-like map of merkleTrees
    /// @param destination address that will receive tokens
    /// @param totalCoins amount of tokens to be released after vesting completes
    /// @param startTime time that vesting schedule starts, can be past or future
    /// @param endTime time vesting schedule completes, can be past or future
    /// @param lockPeriodEndTime time that coins become unlocked, can be after endTime
    /// @param proof array of hashes linking leaf hash of (destination, totalCoins, startTime, endTime, lockPeriodEndTime) to root
    function initialize(uint treeIndex, address destination, uint totalCoins, uint startTime, uint endTime, uint lockPeriodEndTime, bytes32[] memory proof) external {
        // must not initialize multiple times
        require(!initialized[destination][treeIndex], "Already initialized");
        // leaf hash is digest of vesting schedule parameters and destination
        // NOTE: use abi.encode, not abi.encodePacked to avoid possible (but unlikely) collision
        bytes32 leaf = keccak256(abi.encode(destination, totalCoins, startTime, endTime, lockPeriodEndTime));
        // memory because we read only
        MerkleTree memory tree = merkleTrees[treeIndex];
        // call to MerkleLib to check if the submitted data is correct
        require(tree.rootHash.verifyProof(leaf, proof), "The proof could not be verified.");
        // set initialized, preventing double initialization
        initialized[destination][treeIndex] = true;
        // precompute how many coins are released per second
        uint coinsPerSecond = totalCoins / (endTime - startTime);
        // create the tranche struct and assign it
        tranches[destination][treeIndex] = Tranche(
            totalCoins,  // total coins to be released
            totalCoins,  // currentCoins starts as totalCoins
            startTime,
            endTime,
            coinsPerSecond,
            startTime,    // lastWithdrawal starts as startTime
            lockPeriodEndTime
        );
        // if we've passed the lock time go ahead and perform a withdrawal now
        if (lockPeriodEndTime < block.timestamp) {
            withdraw(treeIndex, destination);
        }
    }

    /// @notice Claim funds as a recipient in the merkle-drop
    /// @dev Anyone may call this function for anyone else, funds go to destination regardless, it's just a question of
    /// @dev who provides the proof and pays the gas, msg.sender is not used in this function
    /// @param treeIndex index into array-like map of merkleTrees, which tree should we apply the proof to?
    /// @param destination recipient of tokens
    function withdraw(uint treeIndex, address destination) public {
        // cannot withdraw from an uninitialized vesting schedule
        require(initialized[destination][treeIndex], "You must initialize your account first.");
        // storage because we will modify it
        Tranche storage tranche = tranches[destination][treeIndex];
        // no withdrawals before lock time ends
        require(block.timestamp > tranche.lockPeriodEndTime, 'Must wait until after lock period');
        // revert if there's nothing left
        require(tranche.currentCoins >  0, 'No coins left to withdraw');

        // declaration for branched assignment
        uint currentWithdrawal = 0;

        // if after vesting period ends, give them the remaining coins
        if (block.timestamp >= tranche.endTime) {
            currentWithdrawal = tranche.currentCoins;
        } else {
            // compute allowed withdrawal
            currentWithdrawal = (block.timestamp - tranche.lastWithdrawalTime) * tranche.coinsPerSecond;
        }

        // decrease allocation of coins
        tranche.currentCoins -= currentWithdrawal;
        // this makes sure coins don't get double withdrawn
        tranche.lastWithdrawalTime = block.timestamp;

        // update the tree balance so trees can't take each other's tokens
        MerkleTree storage tree = merkleTrees[treeIndex];
        tree.tokenBalance -= currentWithdrawal;

        // Transfer the tokens, if the token contract is malicious, this will make the whole tree malicious
        // but this does not allow re-entrance due to struct updates and it does not effect other trees.
        // It is also consistent with the ethereum general security model:
        // other contracts do what they want, it's our job to protect our contract
        IERC20(tree.tokenAddress).transfer(destination, currentWithdrawal);
        emit WithdrawalOccurred(treeIndex, destination, currentWithdrawal, tranche.currentCoins);
    }

}