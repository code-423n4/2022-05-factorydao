// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.12;

import "../interfaces/IERC20.sol";
import "./MerkleLib.sol";

/// @title A factory pattern for user-chosen vesting-schedules, that is, a time release schedule for tokens, using merkle proofs to scale
/// @author metapriest, adrian.wachel, marek.babiarz, radoslaw.gorecki
/// @notice This contract is permissionless and public facing. Any fees must be included in the data of the merkle tree.
/// @dev The contract cannot introspect into the contents of the merkle tree, except when provided a merkle proof.
/// @dev User chosen vesting schedules means the contract has parameters that define a line segment that
/// @dev describes a range of vesting-schedule parameters within which the user can negotiate tradeoffs
/// @dev More tokens => longer vesting time && slower drip, when used correctly, but the contract does not enforce
/// @dev coherence of vesting schedules, so someone could make a range of vesting schedules in which
/// @dev more tokens => longer vesting time && faster drip, but this is a user error, also we wouldn't catch it until
/// @dev after the tree has been initialized and funded, so we just let them do it.
/// @dev The choice of which parameters to initialize at tree-creation-time versus at schedule-initialization-time is
/// @dev somewhat arbitrary, but we choose to have min/max end times at tree scope and min/max total payments at first-withdrawal-time
contract MerkleResistor {
    using MerkleLib for bytes32;

    // tree (vesting schedule) counter
    uint public numTrees;

    // this represents a user chosen vesting schedule, post initiation
    struct Tranche {
        address recipient;
        uint totalCoins; // total coins released after vesting complete
        uint currentCoins; // unclaimed coins remaining in the contract, waiting to be vested
        uint startTime; // start time of the vesting schedule
        uint endTime;   // end time of the vesting schedule
        uint coinsPerSecond;  // how many coins are emitted per second, this value is cached to avoid recomputing it
        uint lastWithdrawalTime; // keep track of last time user claimed coins to compute coins owed for this withdrawal
    }

    // this represents an arbitrarily large set of token recipients with partially-initialized vesting schedules
    struct MerkleTree {
        bytes32 merkleRoot; // merkle root of tree whose leaves are ranges of vesting schedules for each recipient
        bytes32 ipfsHash; // ipfs hash of the entire data set represented by the merkle root, in case our servers go down
        uint minEndTime; // minimum length (offset, not absolute) of vesting schedule in seconds
        uint maxEndTime; // maximum length (offset, not absolute) of vesting schedule in seconds
        uint pctUpFront; // percent of vested coins that will be available and withdrawn upon initialization
        address tokenAddress; // address of token to be distributed
        uint tokenBalance; // amount of tokens allocated to this tree (this prevents trees from sharing tokens)
        uint numTranchesInitialized;
        mapping (uint => Tranche) tranches;
        mapping (bytes32 => bool) initialized;
    }

    // basically an array of vesting schedules, but without annoying solidity array syntax
    mapping (uint => MerkleTree) public merkleTrees;

    // precision factory used to handle floating point arithmetic
    uint constant public PRECISION = 1000000;

    // every time a withdrawal occurs
    event WithdrawalOccurred(uint indexed treeIndex, address indexed destination, uint numTokens, uint tokensLeft);

    // every time a tree is added
    event MerkleTreeAdded(uint indexed treeIndex, address indexed tokenAddress, bytes32 newRoot, bytes32 ipfsHash);

    // every time a tree is topped up
    event TokensDeposited(uint indexed treeIndex, address indexed tokenAddress, uint amount);
    event TrancheInitialized(uint indexed treeIndex, uint indexed trancheIndex, address indexed recipient);

    error InvalidPct(uint pct);
    error IncoherentTimes(uint min, uint max);
    error AlreadyInitialized(uint treeIndex, bytes32 leaf);
    error BadProof(uint treeIndex, bytes32 leaf, bytes32[] proof);
    error BadVestingSchedule(uint treeIndex, uint vestingTime, uint minTotalPayments, uint maxTotalPayments);
    error UninitializedAccount(uint treeIndex, uint trancheIndex);
    error AccountEmpty(uint treeIndex, uint trancheIndex);

    /// @notice Add a new merkle tree to the contract, creating a new merkle-vesting-schedule-range
    /// @dev Anyone may call this function, therefore we must make sure trees cannot affect each other
    /// @dev Root hash should be built from (destination, minTotalPayments, maxTotalPayments)
    /// @param newRoot root hash of merkle tree representing vesting schedule ranges
    /// @param ipfsHash the ipfs hash of the entire dataset, used for redundance so that creator can ensure merkleproof are always computable
    /// @param minEndTime a continuous range of possible end times are specified, this is the minimum
    /// @param maxEndTime a continuous range of possible end times are specified, this is the maximum
    /// @param pctUpFront the percent of tokens user will get at initialization time (note this implies no lock time)
    /// @param tokenAddress the address of the token contract that is being distributed
    /// @param tokenBalance the amount of tokens user wishes to use to fund the airdrop, note trees can be under/overfunded
    function addMerkleTree(bytes32 newRoot, bytes32 ipfsHash, uint minEndTime, uint maxEndTime, uint pctUpFront, address tokenAddress, uint tokenBalance) public {
        // check basic coherence of request
        if (pctUpFront >= 100) {
            revert InvalidPct(pctUpFront);
        }

        if (minEndTime >= maxEndTime) {
            revert IncoherentTimes(minEndTime, maxEndTime);
        }

        MerkleTree storage tree = merkleTrees[++numTrees];
        tree.merkleRoot = newRoot;
        tree.ipfsHash = ipfsHash;
        tree.minEndTime = minEndTime;
        tree.maxEndTime = maxEndTime;
        tree.pctUpFront = pctUpFront;
        tree.tokenAddress = tokenAddress;

        // pull tokens from user to fund the tree
        // if tree is insufficiently funded, then some users may not be able to be paid out, this is the responsibility
        // of the tree creator, if trees are not funded, then the UI will not display the tree
        depositTokens(numTrees, tokenBalance);
        emit MerkleTreeAdded(numTrees, tokenAddress, newRoot, ipfsHash);
    }

    /// @notice Add funds to an existing merkle-tree
    /// @dev Anyone may call this function, the only risk here is that the token contract is malicious, rendering the tree malicious
    /// @param treeIndex index into array-like map of merkleTrees
    /// @param value the amount of tokens user wishes to use to fund the airdrop, note trees can be under/overfunded
    function depositTokens(uint treeIndex, uint value) public {
        // storage because we edit
        MerkleTree storage merkleTree = merkleTrees[treeIndex];

        IERC20 token = IERC20(merkleTree.tokenAddress);
        uint balanceBefore = token.balanceOf(address(this));

        // do the transfer from the caller
        // NOTE: it is possible for user to overfund the tree and there is no mechanism to reclaim excess tokens
        // this is because there is no way for the contract to know when a tree has had all leaves claimed.
        // There is also no way for the contract to know the minimum or maximum liabilities represented by the leaves
        // in short, there is no on-chain inspection of any of the leaf data except at initialization time
        // NOTE: a malicious token contract could cause merkleTree.tokenBalance to be out of sync with the token contract
        // this is an unavoidable possibility, and it could render the tree unusable, while leaving other trees unharmed
        token.transferFrom(msg.sender, address(this), value);

        uint balanceAfter = token.balanceOf(address(this));
        // diff may be different from value here, it may even be zero if the transfer failed silently
        uint diff = balanceAfter - balanceBefore;

        // bookkeeping to make sure trees do not share tokens
        merkleTree.tokenBalance += diff;
        emit TokensDeposited(treeIndex, merkleTree.tokenAddress, diff);
    }

    /// @notice Called once per recipient of a vesting schedule to initialize the vesting schedule and fix the parameters
    /// @dev Only the recipient can initialize their own schedule here, because a meaningful choice is made
    /// @dev If the tree is over-funded, excess funds are lost. No clear way to get around this without zk-proofs of global tree stats
    /// @param treeIndex index into array-like map of merkleTrees
    /// @param vestingTime the actual length of the vesting schedule, chosen by the user
    /// @param minTotalPayments the minimum amount of tokens they will receive, if they choose minEndTime as vestingTime
    /// @param maxTotalPayments the maximum amount of tokens they will receive, if they choose maxEndTime as vestingTime
    /// @param proof array of hashes linking leaf hash of (destination, minTotalPayments, maxTotalPayments) to root
    function initialize(
        uint treeIndex,
        uint vestingTime,
        uint minTotalPayments,
        uint maxTotalPayments,
        bytes32[] memory proof) external returns (uint) {
        MerkleTree storage tree = merkleTrees[treeIndex];
        // compute merkle leaf, this is first element of proof
        bytes32 leaf = keccak256(abi.encode(msg.sender, minTotalPayments, maxTotalPayments));

        if (tree.initialized[leaf]) {
            revert AlreadyInitialized(treeIndex, leaf);
        }

        if (tree.merkleRoot.verifyProof(leaf, proof) == false) {
            revert BadProof(treeIndex, leaf, proof);
        }

        (bool valid, uint totalCoins, uint coinsPerSecond, uint startTime) = verifyVestingSchedule(treeIndex, vestingTime, minTotalPayments, maxTotalPayments);

        if (valid == false) {
            revert BadVestingSchedule(treeIndex, vestingTime, minTotalPayments, maxTotalPayments);
        }

        // mark tree as initialized, preventing re-entrance or multiple initializations
        tree.initialized[leaf] = true;


        // fill out the struct for the address' vesting schedule
        // don't have to mark as storage here, it's implied (why isn't it always implied when written to? solc-devs?)
        tree.tranches[++tree.numTranchesInitialized] = Tranche(
            msg.sender,
            totalCoins,    // this is just a cached number for UI, not used
            totalCoins,    // starts out full
            startTime,     // start time will usually be in the past, if pctUpFront > 0
            block.timestamp + vestingTime,  // vesting starts from initialization time
            coinsPerSecond,  // cached value to avoid recomputation
            startTime      // this is lastWithdrawalTime, set to startTime to indicate no withdrawals have occurred yet
        );

        emit TrancheInitialized(treeIndex, tree.numTranchesInitialized, msg.sender);

        withdraw(treeIndex, tree.numTranchesInitialized);

        return tree.numTranchesInitialized;
    }

    /// @notice Move unlocked funds to the destination
    /// @dev Anyone may call this function for anyone else, funds go to destination regardless, it's just a question of
    /// @dev who provides the proof and pays the gas, msg.sender is not used in this function
    /// @param treeIndex index into array-like map of merkleTrees, which tree should we apply the proof to?
    /// @param trancheIndex index into tranche map
    function withdraw(uint treeIndex, uint trancheIndex) public {
        MerkleTree storage tree = merkleTrees[treeIndex];
        Tranche storage tranche = tree.tranches[trancheIndex];

        // checking this way so we don't have to recompute leaf hash
        if (tranche.totalCoins == 0) {
            revert UninitializedAccount(treeIndex, trancheIndex);
        }

        // revert if there's nothing left
        if (tranche.currentCoins == 0) {
            revert AccountEmpty(treeIndex, trancheIndex);
        }

        uint currentWithdrawal;

        // if after vesting period ends, give them the remaining coins, also avoids dust from rounding errors
        if (block.timestamp >= tranche.endTime) {
            currentWithdrawal = tranche.currentCoins;
        } else {
            // compute allowed withdrawal
            // secondsElapsedSinceLastWithdrawal * coinsPerSecond == coinsAccumulatedSinceLastWithdrawal
            currentWithdrawal = (block.timestamp - tranche.lastWithdrawalTime) * tranche.coinsPerSecond;
        }

        // move the time counter up so users can't double-withdraw allocated coins
        // this also works as a re-entrance gate, so currentWithdrawal would be 0 upon re-entrance
        tranche.lastWithdrawalTime = block.timestamp;

        IERC20 token = IERC20(tree.tokenAddress);
        uint balanceBefore = token.balanceOf(address(this));

        // transfer the tokens, brah
        // NOTE: if this is a malicious token, what could happen?
        // 1/ token doesn't transfer given amount to recipient, this is bad for user, but does not effect other trees
        // 2/ token fails for some reason, again bad for user, but this does not effect other trees
        // 3/ token re-enters this function (or other, but this is the only one that transfers tokens out)
        // in which case, lastWithdrawalTime == block.timestamp, so currentWithdrawal == 0
        // Also this could be a misconfigured ERC20 and not return true even if successful, so diff should catch that
        token.transfer(tranche.recipient, currentWithdrawal);

        // compute the diff in case there is a fee-on-transfer or transfer failed silently
        uint balanceAfter = token.balanceOf(address(this));
        uint diff = balanceBefore - balanceAfter;

        // update struct, modern solidity will catch underflow and prevent currentWithdrawal from exceeding currentCoins
        // but it's computed internally anyway, not user generated
        tranche.currentCoins -= diff;
        // handle the bookkeeping so trees don't share tokens, do it before transferring to create one more re-entrance gate
        tree.tokenBalance -= diff;

        emit WithdrawalOccurred(treeIndex, tranche.recipient, diff, tranche.currentCoins);
    }

    /// @notice Determine if the proposed vesting schedule is legit
    /// @dev Anyone may call this to check, but it also returns values used in the initialization of vesting schedules
    /// @param treeIndex index into array-like map of merkleTrees, which tree are we talking about?
    /// @param vestingTime user chosen length of vesting schedule
    /// @param minTotalPayments pre-committed (in the root hash) minimum of possible totalCoins
    /// @param maxTotalPayments pre-committed (in the root hash) maximum of possible totalCoins
    /// @return valid is the proposed vesting-schedule valid
    /// @return totalCoins amount of coins allocated in the vesting schedule
    /// @return coinsPerSecond amount of coins released every second, in the proposed vesting schedule
    /// @return startTime start time of vesting schedule implied by supplied parameters, will always be <= block.timestamp
    function verifyVestingSchedule(uint treeIndex, uint vestingTime, uint minTotalPayments, uint maxTotalPayments) public view returns (bool, uint, uint, uint) {
        // vesting schedules for non-existing trees are invalid, I don't care how much you like uninitialized structs
        if (treeIndex > numTrees) {
            return (false, 0, 0, 0);
        }

        // memory not storage, since we do not edit the tree, and it's a view function anyways
        MerkleTree storage tree = merkleTrees[treeIndex];

        // vesting time must sit within the closed interval of [minEndTime, maxEndTime]
        if (vestingTime > tree.maxEndTime || vestingTime < tree.minEndTime) {
            return (false, 0, 0, 0);
        }

        uint totalCoins;
        if (vestingTime == tree.maxEndTime) {
            // this is to prevent dust accumulation from rounding errors
            // maxEndTime results in max payments, no further computation necessary
            totalCoins = maxTotalPayments;
        } else {
            // remember grade school algebra? slope = Δy / Δx
            // this is the slope of eligible vesting schedules. In general, 0 < m < 1,
            // (longer vesting schedules should result in less coins per second, hence "resistor")
            // so we multiply by a precision factor to reduce rounding errors
            // y axis = total coins released after vesting completed
            // x axis = length of vesting schedule
            // this is the line of valid end-points for the chosen vesting schedule line, see below
            // NOTE: this reverts if minTotalPayments > maxTotalPayments, which is a good thing
            uint paymentSlope = (maxTotalPayments - minTotalPayments) * PRECISION / (tree.maxEndTime - tree.minEndTime);

            // y = mx + b = paymentSlope * (x - x0) + y0
            // divide by precision factor here since we have completed the rounding error sensitive operations
            totalCoins = (paymentSlope * (vestingTime - tree.minEndTime) / PRECISION) + minTotalPayments;
        }

        // this is a different slope, the slope of their chosen vesting schedule
        // y axis = cumulative coins emitted
        // x axis = time elapsed
        // NOTE: vestingTime starts from block.timestamp, so doesn't include coins already available from pctUpFront
        // totalCoins / vestingTime is wrong, we have to multiple by the proportion of the coins that are indexed
        // by vestingTime, which is (100 - pctUpFront) / 100
        uint coinsPerSecond = (totalCoins * (uint(100) - tree.pctUpFront)) / (vestingTime * 100);

        // vestingTime is relative to initialization point
        // endTime = block.timestamp + vestingTime
        // vestingLength = totalCoins / coinsPerSecond
        uint startTime = block.timestamp + vestingTime - (totalCoins / coinsPerSecond);

        return (true, totalCoins, coinsPerSecond, startTime);
    }

    function getTranche(uint treeIndex, uint trancheIndex) view external returns (address, uint, uint, uint, uint, uint, uint) {
        Tranche storage tranche = merkleTrees[treeIndex].tranches[trancheIndex];
        return (tranche.recipient, tranche.totalCoins, tranche.currentCoins, tranche.startTime, tranche.endTime, tranche.coinsPerSecond, tranche.lastWithdrawalTime);
    }

}
