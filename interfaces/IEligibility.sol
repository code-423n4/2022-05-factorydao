// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.9;

/// @title Interface for eligibility gates, this specifies address-specific requirements for being eligible
/// @notice Anything resembling a whitelist for minting should use an eligibility gate
/// @author metapriest, adrian.wachel, marek.babiarz, radoslaw.gorecki
/// @dev There are a couple of functions I wanted to add here but they just don't have uniform enough structure
interface IEligibility {

//    function getGate(uint) external view returns (struct Gate)
//    function addGate(uint...) external

    /// @notice Is the given user eligible? Concerns the address, not whether or not they have the funds
    /// @dev The bytes32[] argument is for merkle proofs of eligibility
    /// @return eligible true if the user can mint
    function isEligible(uint, address, bytes32[] memory) external view returns (bool eligible);

    /// @notice This function is called by MerkleIdentity to make any state updates like counters
    /// @dev This function should typically call isEligible, since MerkleIdentity does not
    function passThruGate(uint, address, bytes32[] memory) external;
}
