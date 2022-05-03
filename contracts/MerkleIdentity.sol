// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.9;

import "../interfaces/IVoterID.sol";
import "../interfaces/IPriceGate.sol";
import "../interfaces/IEligibility.sol";
import "./MerkleLib.sol";

/// @title A generalized NFT minting system using merkle trees to pre-commit to metadata posted to ipfs
/// @author metapriest, adrian.wachel, marek.babiarz, radoslaw.gorecki
/// @notice This contract is permissioned, it requires a treeAdder key to add trees
/// @dev Merkle trees are used at this layer to prove the correctness of metadata added to newly minted NFTs
/// @dev A single NFT contract may have many merkle trees with the same or different roots added here
/// @dev Each tree added has a price gate (specifies price schedule) and an eligibility gate (specifies eligibility criteria)
/// @dev Double minting of the same NFT is prevented by the NFT contract (VoterID)
contract MerkleIdentity {
    using MerkleLib for bytes32;

    // this represents a mint of a single NFT contract with a fixed price gate and eligibility gate
    struct MerkleTree {
        bytes32 metadataMerkleRoot;  // root of merkle tree whose leaves are uri strings to be assigned to minted NFTs
        bytes32 ipfsHash; // ipfs hash of complete uri dataset, as redundancy so that merkle proof remain computable
        address nftAddress; // address of NFT contract to be minted
        address priceGateAddress;  // address price gate contract
        address eligibilityAddress;  // address of eligibility gate contract
        uint eligibilityIndex; // enables re-use of eligibility contracts
        uint priceIndex; // enables re-use of price gate contracts
    }

    // array-like mapping of index to MerkleTree structs
    mapping (uint => MerkleTree) public merkleTrees;
    // count the trees
    uint public numTrees;

    // management key used to set ipfs hashes and treeAdder addresses
    address public management;
    // treeAdder is address that can add trees, separated from management to prevent switching it to a broken contract
    address public treeAdder;

    // every time a merkle tree is added
    event MerkleTreeAdded(uint indexed index, address indexed nftAddress);

    // simple call gate
    modifier managementOnly() {
        require (msg.sender == management, 'Only management may call this');
        _;
    }

    /// @notice Whoever deploys the contract sets the two privileged keys
    /// @param _mgmt key that will initially be both management and treeAdder
    constructor(address _mgmt) {
        management = _mgmt;
        treeAdder = _mgmt;
    }

    /// @notice Change the management key
    /// @dev Only the current management key can change this
    /// @param newMgmt the new management key
    function setManagement(address newMgmt) external managementOnly {
        management = newMgmt;
    }

    /// @notice Change the treeAdder key
    /// @dev Only the current management key can call this
    /// @param newAdder new addres that will be able to add trees, old address will not be able to
    function setTreeAdder(address newAdder) external managementOnly {
        treeAdder = newAdder;
    }

    /// @notice Set the ipfs hash of a specific tree
    /// @dev Only the current management key can call this
    /// @param merkleIndex which merkle tree are we talking about?
    /// @param hash the new ipfs hash summarizing this dataset, written as bytes32 omitting the first 2 bytes "Qm"
    function setIpfsHash(uint merkleIndex, bytes32 hash) external managementOnly {
        MerkleTree storage tree = merkleTrees[merkleIndex];
        tree.ipfsHash = hash;
    }

    /// @notice Create a new merkle tree, opening a mint to an existing contract
    /// @dev Only treeAdder can call this
    /// @param metadataMerkleRoot merkle root of the complete metadata set represented as mintable by this tree
    /// @param ipfsHash ipfs hash of complete dataset (note that you can post hash here without posting to network aka "submarining"
    /// @param nftAddress address of NFT contract to be minted (must conform to IVoterID interface)
    /// @param priceGateAddress address of price gate contract (must conform to IPriceGate interface)
    /// @param eligibilityAddress address of eligibility gate contract (must conform to IEligibility interface)
    /// @param eligibilityIndex index passed to eligibility gate, which in general will have many gates, to select which parameters
    /// @param priceIndex index passed to price gate to select which parameters to use
    function addMerkleTree(
        bytes32 metadataMerkleRoot,
        bytes32 ipfsHash,
        address nftAddress,
        address priceGateAddress,
        address eligibilityAddress,
        uint eligibilityIndex,
        uint priceIndex) external {
        require(msg.sender == treeAdder, 'Only treeAdder can add trees');
        MerkleTree storage tree = merkleTrees[++numTrees];
        tree.metadataMerkleRoot = metadataMerkleRoot;
        tree.ipfsHash = ipfsHash;
        tree.nftAddress = nftAddress;
        tree.priceGateAddress = priceGateAddress;
        tree.eligibilityAddress = eligibilityAddress;
        tree.eligibilityIndex = eligibilityIndex;
        tree.priceIndex = priceIndex;
        emit MerkleTreeAdded(numTrees, nftAddress);
    }

    /// @notice Mint a new NFT
    /// @dev Anyone may call this, but they must pass thru the two gates
    /// @param merkleIndex which merkle tree are we withdrawing the NFT from?
    /// @param tokenId the id number of the NFT to be minted, this data is bound to the uri in each leaf of the metadata merkle tree
    /// @param uri the metadata uri that will be associated with the minted NFT
    /// @param addressProof merkle proof proving the presence of msg.sender's address in an eligibility merkle tree
    /// @param metadataProof sequence of hashes from leaf hash (tokenID, uri) to merkle root, proving data validity
    function withdraw(uint merkleIndex, uint tokenId, string memory uri, bytes32[] memory addressProof, bytes32[] memory metadataProof) external payable {
        MerkleTree storage tree = merkleTrees[merkleIndex];
        IVoterID id = IVoterID(tree.nftAddress);

        // mint an identity first, this keeps the token-collision gas cost down
        id.createIdentityFor(msg.sender, tokenId, uri);

        // check that the merkle index is real
        require(merkleIndex <= numTrees, 'merkleIndex out of range');

        // verify that the metadata is real
        require(verifyMetadata(tree.metadataMerkleRoot, tokenId, uri, metadataProof), "The metadata proof could not be verified");

        // check eligibility of address
        IEligibility(tree.eligibilityAddress).passThruGate(tree.eligibilityIndex, msg.sender, addressProof);

        // check that the price is right
        IPriceGate(tree.priceGateAddress).passThruGate{value: msg.value}(tree.priceIndex, msg.sender);

    }

    /// @notice Get the current price for minting an NFT from a particular tree
    /// @dev This does not take tokenId as an argument, if you want different tokenIds to have different prices, use different trees
    /// @return ethCost the cost in wei of minting an NFT (could represent token cost if price gate takes tokens)
    function getPrice(uint merkleIndex) public view returns (uint) {
        MerkleTree memory tree = merkleTrees[merkleIndex];
        uint ethCost = IPriceGate(tree.priceGateAddress).getCost(tree.priceIndex);
        return ethCost;
    }

    /// @notice Is the given address eligibile to mint from the given tree
    /// @dev If the eligibility gate does not use merkle trees, the proof can be left empty or used for anything else
    /// @param merkleIndex which tree are we talking about?
    /// @param recipient the address about which we are querying eligibility
    /// @param proof merkle proof linking recipient to eligibility merkle root
    /// @return eligibility true if recipient is currently eligible
    function isEligible(uint merkleIndex, address recipient, bytes32[] memory proof) public view returns (bool) {
        MerkleTree memory tree = merkleTrees[merkleIndex];
        return IEligibility(tree.eligibilityAddress).isEligible(tree.eligibilityIndex, recipient, proof);
    }

    /// @notice Is the provided metadata included in tree?
    /// @dev This is public for interfaces, called internally by withdraw function
    /// @param root merkle root (proof destination)
    /// @param tokenId index of NFT being queried
    /// @param uri intended uri of NFT being minted
    /// @param proof sequence of hashes linking leaf data to merkle root
    function verifyMetadata(bytes32 root, uint tokenId, string memory uri, bytes32[] memory proof) public pure returns (bool) {
        bytes32 leaf = keccak256(abi.encode(tokenId, uri));
        return root.verifyProof(leaf, proof);
    }

}