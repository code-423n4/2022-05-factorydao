// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.12;

import "../interfaces/IERC20.sol";

/// @title A factory pattern for basic staking, put tokens in, get more tokens (potentially multiple types) out
/// @author metapriest, adrian.wachel, marek.babiarz, radoslaw.gorecki
/// @notice This contract is permissionless and public facing. Anyone can create a pool, and fees are taken out of rewards
/// @dev Maximum possible pool obligations are computed at pool-creation-time and taken from creator at that time
/// @dev Any unclaimed rewards are claimable after the pool has ended, pool funds are accounted for separately
contract PermissionlessBasicPoolFactory {

    // this represents a single deposit into a staking pool, used to withdraw as well
    struct Receipt {
        uint id;   // primary key
        uint amountDepositedWei;  // amount of tokens originally deposited
        uint timeDeposited;  // the time the deposit was made
        uint timeWithdrawn;  // the time the deposit was withdrawn, or 0 if not withdrawn yet
        address owner;  // the owner of the deposit
    }

    // this represents a single staking pool with >= 1 reward tokens
    struct Pool {
        uint id; // primary key
        uint[] rewardsWeiPerSecondPerToken; // array of reward rates, this number gets multiplied by time and tokens (not wei) to determine rewards
        uint[] rewardsWeiClaimed;  // bookkeeping of how many rewards have been paid out for each token
        uint[] rewardFunding;  // bookkeeping of how many rewards have been supplied for each token
        uint maximumDepositWei;  // the size of the pool, maximum sum of all deposits
        uint minimumDepositWei; // the minimum size of a single deposit, used to limit dust attacks
        uint totalDepositsWei;  // current sum of all deposits
        uint numReceipts;  // number of receipts issued
        uint startTime;  // the time that the pool begins
        uint endTime;    // time that the pool ends
        uint taxPerCapita;  // portion of rewards that go to the contract creator
        address depositToken;  // token that user deposits (stakes)
        address excessBeneficiary;  // address that is able to reclaim unused rewards
        address[] rewardTokens;  // array of token contract addresses that stakers will receive as rewards
        mapping (uint => Receipt) receipts;  // mapping of receipt ids to receipt structs
    }

    // simple struct for UI to display relevant data
    struct Metadata {
        bytes32 name;
        bytes32 ipfsHash;
    }

    // the number of staking pools ever created
    uint public numPools;

    uint public immutable MAX_TAX = 100;
    uint public immutable MAX_REWARD_TOKENS = 10;

    // the beneficiary of taxes
    address public globalBeneficiary;

    // this is the settable tax imposed on new pools, fixed at pool creation time
    uint public globalTaxPerCapita;

    // pools[poolId] = poolStruct
    mapping (uint => Pool) public pools;
    // metadatas[poolId] = metadataStruct
    mapping (uint => Metadata) public metadatas;
    // taxes[poolId] = taxesCollected[rewardIndex]
    mapping (uint => uint[]) public taxes;

    // every time a deposit happens
    event DepositOccurred(uint indexed poolId, uint indexed receiptId, address indexed owner);
    // every time a withdrawal happens
    event WithdrawalOccurred(uint indexed poolId, uint indexed receiptId, address indexed owner);
    event EmergencyWithdrawalOccurred(uint indexed poolId, uint indexed receiptId, address indexed owner);
    // every time excess rewards are withdrawn
    event ExcessRewardsWithdrawn(uint indexed poolId, uint transferred);
    // every time a pool is added
    event PoolAdded(uint indexed poolId, bytes32 indexed name, address indexed depositToken);

    error UninitializedPool(uint poolId);
    error UninitializedReceipt(uint poolId, uint receiptId);
    error PoolNotStartedYet(uint poolId);
    error PoolAlreadyClosed(uint poolId);
    error PoolAlreadyFull(uint poolId);
    error PoolNotFinishedYet(uint poolId);
    error MinimumDepositNotMet(uint poolId);
    error UnauthorizedWithdrawal(uint poolId, uint receiptId, address withdrawer);
    error ReceiptAlreadyWithdrawn(uint poolId, uint receiptId);
    error PoolMustBeEmpty(uint poolId);
    error TaxTooHigh(uint attemptedTax);
    error TooManyRewardTokens(address poolCreator, uint numTokens);
    error MismatchedArrays(address poolCreator);
    error GlobalBeneficiaryOnly(address notAuthorized);
    error ReentrancePrevented(address attacker);
    error TokenTransferFailed(uint poolId, uint receiptId);
    error DepositFailed(uint poolId, address depositor);

    uint private unlocked = 1;
    modifier lock() {
        if (unlocked != 1) {
            revert ReentrancePrevented(msg.sender);
        }
        unlocked = 0;
        _;
        unlocked = 1;
    }

    /// @notice Whoever deploys the contract decides who receives how much fees
    /// @param _globalBeneficiary the address that receives the fees and can also set the fees
    /// @param _globalTaxPerCapita the amount of the rewards that goes to the globalBeneficiary * 1000 (perCapita)
    constructor(address _globalBeneficiary, uint _globalTaxPerCapita) {
        globalBeneficiary = _globalBeneficiary;
        if (_globalTaxPerCapita > MAX_TAX) {
            revert TaxTooHigh(_globalTaxPerCapita);
        }
        globalTaxPerCapita = _globalTaxPerCapita;
    }

    /// @notice Create a pool and fund it
    /// @dev Anyone may call this function, but they must fund it, having called approve on all contracts beforehand
    /// @dev Any malicious token contracts included here will make the pool malicious, but not effect other pools
    /// @param startTime time at which pool starts, if in past, it is set to block.timestamp "now"
    /// @param maxDeposit the maximum amount of tokens that can be deposited in this pool
    /// @param rewardsWeiPerSecondPerToken the amount of tokens given out per second per token (not wei) deposited
    /// @param programLengthDays the amount of days the pool will be open, this with the start time determines the end time
    /// @param depositTokenAddress the token that users will put into the pool to receive rewards
    /// @param excessBeneficiary the recipient of any unclaimed funds in the pool
    /// @param rewardTokenAddresses the list of token contracts that will be given out as rewards for staking
    /// @param ipfsHash a hash of any metadata about the pool, may be incorporated into interfaces
    /// @param name name of pool, to be used by interfaces
    function addPool (
        uint startTime,
        uint maxDeposit,
        uint[] calldata rewardsWeiPerSecondPerToken,
        uint programLengthDays,
        address depositTokenAddress,
        address excessBeneficiary,
        address[] calldata rewardTokenAddresses,
        bytes32 ipfsHash,
        bytes32 name
    ) external returns (uint) {
        Pool storage pool = pools[++numPools];
        pool.id = numPools;
        pool.rewardsWeiPerSecondPerToken = rewardsWeiPerSecondPerToken;
        pool.startTime = startTime > block.timestamp ? startTime : block.timestamp;
        pool.endTime = pool.startTime + (programLengthDays * 1 days);
        pool.depositToken = depositTokenAddress;
        pool.excessBeneficiary = excessBeneficiary;
        pool.taxPerCapita = globalTaxPerCapita;

        if (rewardTokenAddresses.length > MAX_REWARD_TOKENS) {
            revert TooManyRewardTokens(msg.sender, rewardTokenAddresses.length);
        }
        if (rewardTokenAddresses.length != rewardsWeiPerSecondPerToken.length) {
            revert MismatchedArrays(msg.sender);
        }

        pool.rewardTokens = rewardTokenAddresses;

        uint arrayLength = rewardTokenAddresses.length;
        pool.rewardsWeiClaimed = new uint[](arrayLength);
        pool.rewardFunding = new uint[](arrayLength);
        taxes[numPools] = new uint[](arrayLength);
        pool.maximumDepositWei = maxDeposit;

        // this must be after pool initialization above
        fundPool(numPools);

        {
            Metadata storage metadata = metadatas[numPools];
            metadata.ipfsHash = ipfsHash;
            metadata.name = name;
        }
        emit PoolAdded(numPools, name, depositTokenAddress);
        return numPools;
    }

    /// @notice Add funds to a pool
    /// @dev This function is internal because pools cannot be underfunded, liabilities are known at pool-creation-time
    /// @param poolId index of pool that is being funded
    function fundPool(uint poolId) internal {
        Pool storage pool = pools[poolId];
        uint arrayLength = pool.rewardFunding.length;
        for (uint i; i < arrayLength; ++i) {
            uint amount = getMaximumRewards(poolId, i);
            fundPoolSpecificReward(poolId, i, amount);
        }
    }

    /// @notice Fund a specific reward token for a specific pool by a user-chosen amount
    /// @param poolId which pool?
    /// @param rewardIndex which reward token is being funded
    /// @param amount how many reward tokens are being added to pool
    function fundPoolSpecificReward(uint poolId, uint rewardIndex, uint amount) public {
        Pool storage pool = pools[poolId];

        // transfer the tokens from pool-creator to this contract
        uint transferred = transferPossiblyMalicious(pool.rewardTokens[rewardIndex], msg.sender, address(this), amount);

        // bookkeeping to make sure pools don't share tokens
        pool.rewardFunding[rewardIndex] += transferred;
    }

    /// @notice Compute the rewards that would be received if the receipt was cashed out now
    /// @dev This function does not inspect whether the receipt has already been cashed out
    /// @param poolId which pool are we talking about?
    /// @param receiptId the id of the receipt that we are querying
    /// @return rewardsLocal array of rewards, one entry for each reward token
    function getRewards(uint poolId, uint receiptId) public view returns (uint[] memory) {
        Pool storage pool = pools[poolId];
        Receipt memory receipt = pool.receipts[receiptId];
        if (pool.id != poolId) {
            revert UninitializedPool(poolId);
        }
        if (receipt.id != receiptId) {
            revert UninitializedReceipt(poolId, receiptId);
        }
        uint nowish = block.timestamp;
        if (nowish > pool.endTime) {
            nowish = pool.endTime;
        }

        uint secondsDiff = nowish - receipt.timeDeposited;
        uint[] memory rewardsLocal = new uint[](pool.rewardsWeiPerSecondPerToken.length);
        uint arrayLength = pool.rewardsWeiPerSecondPerToken.length;
        for (uint i; i < arrayLength; ++i) {
            uint8 decimals = IERC20(pool.rewardTokens[i]).decimals();
            rewardsLocal[i] = (secondsDiff * pool.rewardsWeiPerSecondPerToken[i] * receipt.amountDepositedWei) / (10**decimals);
        }

        return rewardsLocal;
    }

    /// @notice Add funds to a pool
    /// @dev Anyone may call this function, it simply puts tokens in the pool and returns a receipt
    /// @dev If deposit amount causes pool to overflow, amount is decreased so pool is full
    /// @param poolId which pool are we talking about?
    /// @param amount amount of tokens to deposit
    function deposit(uint poolId, uint amount) external {
        Pool storage pool = pools[poolId];
        if (pool.id != poolId) {
            revert UninitializedPool(poolId);
        }
        if (block.timestamp < pool.startTime) {
            revert PoolNotStartedYet(poolId);
        }
        if (block.timestamp >= pool.endTime) {
            revert PoolAlreadyClosed(poolId);
        }
        if (pool.totalDepositsWei == pool.maximumDepositWei) {
            revert PoolAlreadyFull(poolId);
        }
        if (pool.minimumDepositWei > amount) {
           revert MinimumDepositNotMet(poolId);
        }
        if (pool.totalDepositsWei + amount > pool.maximumDepositWei) {
            amount = pool.maximumDepositWei - pool.totalDepositsWei;
        }

        uint transferred = transferPossiblyMalicious(pool.depositToken, msg.sender, address(this), amount);
        if (transferred == 0) {
            revert DepositFailed(poolId, msg.sender);
        }

        pool.totalDepositsWei += transferred;

        Receipt storage receipt = pool.receipts[++pool.numReceipts];
        receipt.id = pool.numReceipts;
        receipt.amountDepositedWei = transferred;
        receipt.timeDeposited = block.timestamp;
        receipt.owner = msg.sender;

        emit DepositOccurred(poolId, pool.numReceipts, msg.sender);
    }

    /// @notice Withdraw funds from pool
    /// @dev Only receipt owner may call this function
    /// @dev If any of the reward tokens are malicious, this function may break
    /// @param poolId which pool are we talking about?
    /// @param receiptId which receipt is being cashed in
    function withdraw(uint poolId, uint receiptId) external {
        Pool storage pool = pools[poolId];
        if (pool.id != poolId) {
            revert UninitializedPool(poolId);
        }
        Receipt storage receipt = pool.receipts[receiptId];
        if (receipt.id != receiptId) {
            revert UninitializedReceipt(poolId, receiptId);
        }

        // If you're not the owner and the pool hasn't ended yet, revert
        if (receipt.owner != msg.sender && block.timestamp <= pool.endTime) {
            revert UnauthorizedWithdrawal(poolId, receiptId, msg.sender);
        }

        if (receipt.timeWithdrawn != 0) {
            revert ReceiptAlreadyWithdrawn(poolId, receiptId);
        }

        // close re-entry gate
        receipt.timeWithdrawn = block.timestamp;

        uint[] memory rewards = getRewards(poolId, receiptId);
        uint transferred;

        // distribute rewards
        uint arrayLength = rewards.length;
        for (uint i; i < arrayLength; ++i) {
            uint tax = (pool.taxPerCapita * rewards[i]) / 1000;
            taxes[poolId][i] += tax;
            uint transferAmount = rewards[i] - tax;
            transferred = transferPossiblyMalicious(pool.rewardTokens[i], address(this), receipt.owner, transferAmount);
            // could make this if (transferred < receipt.amountDepositedWei)...
            if (transferred == 0) {
                revert TokenTransferFailed(poolId, receiptId);
            }
            pool.rewardsWeiClaimed[i] += transferred;
            pool.rewardFunding[i] -= (transferred + tax);
        }

        // return deposit tokens
        transferred = transferPossiblyMalicious(pool.depositToken, address(this), receipt.owner, receipt.amountDepositedWei);

        // could make this if (transferred < receipt.amountDepositedWei)...
        if (transferred == 0) {
            revert TokenTransferFailed(poolId, receiptId);
        }

        pool.totalDepositsWei -= transferred;

        emit WithdrawalOccurred(poolId, receiptId, receipt.owner);
    }

    /// @notice Withdraw a deposit without receiving rewards, in case a reward token is broken
    /// @dev Note this cashes in the receipt and it cannot ever receive the rewards after calling this
    /// @param poolId which pool?
    /// @param receiptId which receipt?
    function withdrawEmergency(uint poolId, uint receiptId) external {
        Pool storage pool = pools[poolId];
        if (pool.id != poolId) {
            revert UninitializedPool(poolId);
        }

        Receipt storage receipt = pool.receipts[receiptId];
        if (receipt.id != receiptId) {
            revert UninitializedReceipt(poolId, receiptId);
        }

        // If you're not the owner and the pool hasn't ended yet, revert
        if (receipt.owner != msg.sender && block.timestamp <= pool.endTime) {
            revert UnauthorizedWithdrawal(poolId, receiptId, msg.sender);
        }

        if (receipt.timeWithdrawn != 0) {
            revert ReceiptAlreadyWithdrawn(poolId, receiptId);
        }

        // close re-entry gate
        receipt.timeWithdrawn = block.timestamp;


        uint transferred = transferPossiblyMalicious(pool.depositToken, address(this), receipt.owner, receipt.amountDepositedWei);

        // could make this if (transferred < receipt.amountDepositedWei)...
        if (transferred == 0) {
            revert TokenTransferFailed(poolId, receiptId);
        }

        pool.totalDepositsWei -= transferred;

        emit EmergencyWithdrawalOccurred(poolId, receiptId, receipt.owner);
    }

    /// @notice Withdraw any unused rewards from the pool, after it has ended
    /// @dev Anyone can call this, as the excess beneficiary is set at pool-creation-time
    /// @param poolId which pool are we talking about?
    function withdrawExcessRewards(uint poolId, uint rewardIndex) external {
        Pool storage pool = pools[poolId];
        if (pool.id != poolId) {
            revert UninitializedPool(poolId);
        }
        if (pool.totalDepositsWei != 0) {
            revert PoolMustBeEmpty(poolId);
        }
        if (block.timestamp < pool.endTime) {
            revert PoolNotFinishedYet(poolId);
        }

        uint rewards = pool.rewardFunding[rewardIndex];
        uint transferred = transferPossiblyMalicious(pool.rewardTokens[rewardIndex], address(this), pool.excessBeneficiary, rewards);
        pool.rewardFunding[rewardIndex] -= transferred;

        emit ExcessRewardsWithdrawn(poolId, transferred);
    }

    /// @notice Withdraw taxes from pool
    /// @dev Anyone may call this, it just moves the taxes from this contract to the globalBeneficiary
    /// @param poolId which pool are we talking about?
    /// @param rewardIndex which token are we withdrawing?
    function withdrawTaxes(uint poolId, uint rewardIndex) external {
        Pool storage pool = pools[poolId];
        if (pool.id != poolId) {
            revert UninitializedPool(poolId);
        }

        uint tax = taxes[poolId][rewardIndex];
        uint transferred = transferPossiblyMalicious(pool.rewardTokens[rewardIndex], address(this), globalBeneficiary, tax);
        taxes[poolId][rewardIndex] -= transferred;
    }

    /// @notice Compute maximum rewards that could be given out by a given pool
    /// @dev This is primarily used by fundPool to compute how many tokens to take from the pool-creator
    /// @param poolId which pool are we talking about?
    /// @param rewardIndex index into the rewards array, to avoid passing arrays around
    /// @return maximumRewardAmount the theoretical maximum that will be paid from this reward token, if pool fills instantly
    function getMaximumRewards(uint poolId, uint rewardIndex) public view returns (uint) {
        Pool storage pool = pools[poolId];
        uint8 decimals = IERC20(pool.rewardTokens[rewardIndex]).decimals();
        // rewardsPerSecondPerToken * tokens * seconds
        return pool.rewardsWeiPerSecondPerToken[rewardIndex] * pool.maximumDepositWei * (pool.endTime - pool.startTime) / (10**decimals);
    }

    /// @notice Get reward data about a pool
    /// @dev This gets all the reward-relevant fields from the struct
    /// @param poolId which pool are we talking about?
    /// @return rewardsWeiPerSecondPerToken reward slope array
    /// @return rewardsWeiClaimed rewards already claimed array
    /// @return rewardTokens array of reward token contract addresses
    /// @return rewardFunding array of amounts of reward tokens already dispensed
    function getRewardData(uint poolId) external view returns (uint[] memory, uint[] memory, address[] memory, uint[] memory) {
        Pool storage pool = pools[poolId];
        return (pool.rewardsWeiPerSecondPerToken, pool.rewardsWeiClaimed, pool.rewardTokens, pool.rewardFunding);
    }

    /// @notice Get data about a specific receipt
    /// @dev This gets all the fields from a receipt
    /// @param poolId which pool are we talking about?
    /// @param receiptId which receipt are we talking about?
    /// @return amountDepositedWei original deposit amount
    /// @return timeDeposited the time of original deposit
    /// @return timeWithdrawn time when receipt was cashed in, if ever
    /// @return owner the beneficiary of the receipt, who deposited the tokens originally?
    function getReceipt(uint poolId, uint receiptId) external view returns (uint, uint, uint, address) {
        Pool storage pool = pools[poolId];
        Receipt storage receipt = pool.receipts[receiptId];
        return (receipt.amountDepositedWei, receipt.timeDeposited, receipt.timeWithdrawn, receipt.owner);
    }

    /// @notice Change the fee factor
    /// @dev This can only be called by the global beneficiary
    /// @param newTaxPerCapita the new fee
    function setGlobalTax(uint newTaxPerCapita) external {
        if (msg.sender != globalBeneficiary) {
            revert GlobalBeneficiaryOnly(msg.sender);
        }
        if (newTaxPerCapita > MAX_TAX) {
            revert TaxTooHigh(newTaxPerCapita);
        }
        globalTaxPerCapita = newTaxPerCapita;
    }

    /// @notice Transfer tokens on an untrusted token contract
    /// @dev This function is internal, since it transfers tokens to and from this contract
    /// @dev If neither from nor to is address(this) then this function is a no-op and returns 0
    /// @param tokenAddress contract address of token
    /// @param from address from which tokens will be transferred
    /// @param to address to which tokens will be transferred
    /// @param amount amount of tokens to be transferred
    /// @return the actual amount of tokens transferred
    function transferPossiblyMalicious(address tokenAddress, address from, address to, uint amount) internal lock returns (uint) {
        IERC20 token = IERC20(tokenAddress);
        uint diff;
        if (from == address(this)) {
            uint balanceBefore = token.balanceOf(address(this));
            token.transfer(to, amount);
            uint balanceAfter = token.balanceOf(address(this));
            diff = balanceBefore - balanceAfter;
        } else if (to == address(this)) {
            uint balanceBefore = token.balanceOf(address(this));
            token.transferFrom(from, to, amount);
            uint balanceAfter = token.balanceOf(address(this));
            diff = balanceAfter - balanceBefore;
        }

        // return the actual amount transferred
        return diff;
    }
}
