# ✨ So you want to sponsor a contest

This `README.md` contains a set of checklists for our contest collaboration.

Your contest will use two repos: 
- **a _contest_ repo** (this one), which is used for scoping your contest and for providing information to contestants (wardens)
- **a _findings_ repo**, where issues are submitted. 

Ultimately, when we launch the contest, this contest repo will be made public and will contain the smart contracts to be reviewed and all the information needed for contest participants. The findings repo will be made public after the contest is over and your team has mitigated the identified issues.

Some of the checklists in this doc are for **C4 (🐺)** and some of them are for **you as the contest sponsor (⭐️)**.

---

# Contest setup

## 🐺 C4: Set up repos
- [ ] Create a new private repo named `YYYY-MM-sponsorname` using this repo as a template.
- [ ] Add sponsor to this private repo with 'maintain' level access.
- [ ] Send the sponsor contact the url for this repo to follow the instructions below and add contracts here. 
- [ ] Delete this checklist and wait for sponsor to complete their checklist.

## ⭐️ Sponsor: Provide contest details

Under "SPONSORS ADD INFO HERE" heading below, include the following:

- [x] Name of each contract and:
  - [x] source lines of code (excluding blank lines and comments) in each
  - [x] external contracts called in each
  - [x] libraries used in each
- [x] Describe any novel or unique curve logic or mathematical models implemented in the contracts
- [x] Does the token conform to the ERC-20 standard? In what specific ways does it differ?
- [x] Describe anything else that adds any special logic that makes your approach unique
- [x] Identify any areas of specific concern in reviewing the code
- [x] Add all of the code to this repo that you want reviewed
- [ ] Create a PR to this repo with the above changes.

---

# Contest prep

## 🐺 C4: Contest prep
- [ ] Rename this repo to reflect contest date (if applicable)
- [ ] Rename contest H1 below
- [ ] Add link to report form in contest details below
- [ ] Update pot sizes
- [ ] Fill in start and end times in contest bullets below.
- [ ] Move any relevant information in "contest scope information" above to the bottom of this readme.
- [ ] Add matching info to the [code423n4.com public contest data here](https://github.com/code-423n4/code423n4.com/blob/main/_data/contests/contests.csv))
- [ ] Delete this checklist.

## ⭐️ Sponsor: Contest prep
- [x] Make sure your code is thoroughly commented using the [NatSpec format](https://docs.soliditylang.org/en/v0.5.10/natspec-format.html#natspec-format).
- [x] Modify the bottom of this `README.md` file to describe how your code is supposed to work with links to any relevent documentation and any other criteria/details that the C4 Wardens should keep in mind when reviewing. ([Here's a well-constructed example.](https://github.com/code-423n4/2021-06-gro/blob/main/README.md))
- [ ] Please have final versions of contracts and documentation added/updated in this repo **no less than 8 hours prior to contest start time.**
- [x] Ensure that you have access to the _findings_ repo where issues will be submitted.
- [ ] Promote the contest on Twitter (optional: tag in relevant protocols, etc.)
- [ ] Share it with your own communities (blog, Discord, Telegram, email newsletters, etc.)
- [ ] Optional: pre-record a high-level overview of your protocol (not just specific smart contract functions). This saves wardens a lot of time wading through documentation.
- [ ] Delete this checklist and all text above the line below when you're ready.

---

# FactoryDAO contest details
- $47,500 DAI main award pot
- $2,500 DAI gas optimization award pot
- Join [C4 Discord](https://discord.gg/code4rena) to register
- Submit findings [using the C4 form](https://code4rena.com/contests/2022-05-factorydao-contest/submit)
- [Read our guidelines for more details](https://docs.code4rena.com/roles/wardens)
- Starts May 4, 2022 00:00 UTC
- Ends May 08, 2022 23:59 UTC

This repo will be made public before the start of the contest. (C4 delete this line when made public)

[ ⭐️ SPONSORS ADD INFO HERE ]

PermissionlessBasicPoolFactory:  193 lines of code, 6 calls to external ERC20, 0 libraries
VoterID:  173 lines of code, 1 call to external contract, 0 libraries
MerkleResistor: 107 lines of code, 2 calls to external ERC20, 1 library
MerkleVesting: 82 lines of code, 2 calls to external ERC20, 1 library
MerkleIdentity: 81 lines of code, 3 calls to external contracts, 1 library
MerkleDropFactory: 48 lines of code, 2 calls to external ERC20, 1 library
SpeedBumpPriceGate: 43 lines of code, 1 call to external address, 0 libraries
MerkleEligibility: 41 lines of code, 0 external calls, 1 library
FixedPricePassThruGate: 27 lines of code, 1 call to external address, 0 libraries
MerkleLib: 17 lines of code, 0 external calls, 0 libraries

Total: 812 lines of code 

These contracts make extensive use of merkle trees, it is advised to review this data structure before auditing. The suggested order of audit:

PermissionlessBasicPoolFactory

MerkleLib
MerkleDropFactory
MerkleVesting
MerkleResistor

MerkleIdentity
MerkleEligibility
FixedPricePassThruGate
SpeedBumpPriceGate
VoterID 

They are grouped above according to application. 


There are a couple of unusual calculations to consider. First, in MerkleResistor, the creator of a tree specifies a range of vesting schedules that the user may choose from. This is expressed as a line, a diagonal of a rectangle from (minEndTime, minTotalPayments) to (maxEndTime, maxTotalPayments). Each point on this line represents a valid end point of another line, the vesting schedule line, which is drawn from (startTime, 0) to (endTime, totalCoins). So it's just 2d linear algebra, but there's two lines working together, so it can be confusing. Additionaly, the first line has a positive slope < 1, so we have to multiply by a precision factor to simulate floating point arithmetic. The second bit of unusual math is in SpeedBumpPriceGate, in which each purchase multiplies the price by a factor (exponential increase), after which the price decays linearly. 


A particular concern with these contracts is their largely permissionless nature. Anyone can add merkledrops or staking pools, etc. so we must consider the possibility of malicious ERC20 contracts being added. In most contracts, each user-added struct gets its own state, while global state is minimized, in order to partition any security concerns as much as possible. In the case of malicious staking pools or trees being added, our utmost concern is that the other pools/trees are unaffected. 


Some of the contracts together form an NFT minting system. We have designed this to put NFT metadata on IPFS, because we believe this more closely matches the notion of actually owning some bit of digital whatever, instead of putting the metadata on a URL controlled by some trusted third party. We have used merkle trees to do this at scale, putting the metadata uris into a big merkle tree and burdening the end user with the gas fees to prove the validity of the metadata and associate it with their NFT. This minting suite also has a traffic light system (not included here) that warns users if they are likely to collide with others trying to mint the same token ID. This system also uses merkle trees to prove eligibility to mint, making the notion of a whitelist scalable. 


The trio of merkle-drop merkle-vesting and merkle-resistor form another product of ours called "bank". They build upon one another, with merkle-drop being the simplest, in which tokens are allocated to many users at once via merkle tree and it is up to the user (with the help of an interface, of course) to supply the merkle proof that they are eligible to receive how many tokens. MerkleVesting builds upon this idea but adds a time lock to it, with the details of the time lock again supplied by the user and verified via merkle proof. Lastly, MerkleResistor does the same thing, but with the vesting schedule only partially specified, with the user both choosing the vesting schedule and proving the details of the vesting schedule to the contract via merkle proof. In all three of these contracts, there is no way for the contract to introspect the contents of the merkle tree at tree-creation-time, which is where the massive increase in scalability comes from. Because of this, the contracts are not able to verify any global statistics about the trees, which means that the contracts can never know if the trees have been completely exhausted or if the trees are under/over funded relative to their liabilities. Therefore each tree keeps its own balance of tokens that can be topped up by any user at any time. There is no mechanism to reclaim committed tokens to avoid the possibility of a rugpull. Fees are inserted by the frontend as an additional liability in the trees.



