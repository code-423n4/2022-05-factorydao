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
- [x] Please have final versions of contracts and documentation added/updated in this repo **no less than 8 hours prior to contest start time.**
- [x] Ensure that you have access to the _findings_ repo where issues will be submitted.
- [ ] Promote the contest on Twitter (optional: tag in relevant protocols, etc.)
- [ ] Share it with your own communities (blog, Discord, Telegram, email newsletters, etc.)
- [x] Optional: pre-record a high-level overview of your protocol (not just specific smart contract functions). This saves wardens a lot of time wading through documentation.
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
<h2>Introduction to FactoryDAO</h2>

FactoryDAO is a modular DAO framework that aims to work as a DAO to build the tools that DAOs need to launch tokens, manage their token economies, sell tokens from their treasuries and improve decentralised decision making. The goal is to be the Google apps / Office 365 dApp suite for DAOs, allowing DAOs to pick tools from our suite or mix and match them with tools from elsewhere in the DAO tooling space.

You will be auditing the smart contracts of three of these tools in this competition, Yield, Bank and Mint. 

These three tools sit along a wider DAO suite: Launch (LBP-like fungible token auctions and liquidity bootstrapping), Influence (a snapshot-like voting a decision making system), Auction (a permissionless NFT auctioning system) and a number of other tools (Identity, Dashboard, AMA) for monitoring DAO activity and collaborating as a decentralised community. These are out of the scope of this audit, but it is useful to know that these tools fit alongside a broader ecosystem and we hope to present them to you in future competitions.

<h2>The High Level Overview of the Tools</h2>

<h3>Yield</h3>

Yield comes in two components Basic Pool, which you are auditing in this tranche and Resident Pool, a more complex Harberger Tax based staking pool (not in scope). In the case of Basic Pool, it is a simple stake-tokens-earn-tokens as a yield primitive designed to allow DAOs to incentivise holding. Stakers can return not just one token as yield but many. We also use this Pool for governance, where stakers can take part in Stake Weighted Voting.

In our new version of this product, we have extended the permissionlessness of the system to allow any user to create their own Basic Pool.  This is one of the contracts you will audit.

<h3>Bank</h3>

Bank is a token vesting, airdrop and payroll tool. It uses merkle trees to massively scale token distributions with integrated vesting (time locks). The idea of this tool is that it allows DAOs to vest pre-sale participants, and future allocations of tokens (such as DAO treasury allocations) far into the future. These are important contracts since they need longevity and will secure large allocations of tokens. 

Additionally, this tool allows DAOs to pay out tokens to their participants. Vesting is an important component to this because it means that DAOs can stream tokens to their users and limit the amount of immediate sell pressure on the exchanges, allowing users to pick up their tokens as they are available with to-the-token-to-the-second resolution. The Merkle Resistor contract here allows users to select their own vesting schedule e.g get tokens quicker, but get less of them. Users select their chosen vesting schedule with a slider on the front end and ‘Commit’ to their chosen vesting schedule by submitting their Merkle Proof along with their vesting parameters.

Bank aims to be an important primitive for DAOs, since it will allow rapid distribution of tokens by simply uploading a CSV or JSON file of the appropriate distributions and allow users to pay the gas to claim making it affordable for DAOs to send tokens to millions of people. 

<h3>Mint</h3>

Mint is an NFT launching suite with integrated merkle tree based whitelisting and price discovery functionality. It’s designed to give NFT DAOs the best start in life by ensuring that tokens get a wide distribution and are sold for their best price without descending into a gas race.

It has two main functions. The mass mint and the continuous auction. The mass mint allows users to select which tokenID that they wish to mint and provides them with feedback on the front end informing them of whether the token is available (already been minted) or if the token is in the process of being minted (an optional gas race). The use of merkle trees ensures that users can only mint if they are included in the whitelist (stopping direct contract minting) and allows DAOs to issue NFTs at variable price points simultaneously during mint. 

The continuous auction issues NFTs one at a time with a dynamic pricing determined by a rolling auction mechanism. As an example, TokenID1 is sold for a base price of 1 ETH and TokenID2 is immediately listed at 2 ETH, with a block by block linear price decay until it returns to the base price. If TokenID2 is minted at 1.5 ETH, then TokenID3 is listed at 3 ETH and so on. This mechanism is designed to sell NFTs at their market rate as opposed to a flat rate across the whole set. 

<h2>The Contract Detail Overview </h2>

<h3>Yield</h3>

- PermissionlessBasicPoolFactory.sol: 193 lines of code, 6 calls to external ERC20, 0 libraries. 
<b>Basic fungible token staking with multiple reward token yield and permissionless pool creation.</b>

<h3>Bank</h3>

- MerkleLib.sol: 
17 lines of code, 0 external calls, 0 libraries.
<b>Library for extremely efficient merkle proof verification.</b>

- MerkleDropFactory.sol: 
48 lines of code, 2 calls to external ERC20, 1 library.
<b>Permissionless scalable airdrops using merkle trees</b>

- MerkleVesting.sol: 
82 lines of code, 2 calls to external ERC20, 1 library. 
<b>Permissionless scalable linear token vesting using merkle trees</b>

- MerkleResistor.sol: 
107 lines of code, 2 calls to external ERC20, 1 library
<b>Permissionless scalable user-chosen token vesting using merkle trees</b>

<h3>Mint</h3>

- MerkleIdentity.sol: 
81 lines of code, 3 calls to external contracts, 1 library
<b>Permissioned NFT minting with flexible pricing and eligibility, and metadata on IPFS.</b>

- MerkleEligibility.sol: 
41 lines of code, 0 external calls, 1 library
<b>Scalable NFT minting whitelists with merkle trees</b>

- FixedPricePassThruGate.sol: 
27 lines of code, 1 call to external address, 0 libraries
<b>NFT pricing module with fixed prices, per-address limits and global limits.</b>

- SpeedBumpPriceGate.sol: 
43 lines of code, 1 call to external address, 0 libraries
<b>NFT pricing module with pricing that increases exponentially on purchase and decreases linearly with time thereafter.</b>

- VoterID.sol:  
173 lines of code, 1 call to external contract, 0 libraries
<b>Modified ERC721 contract compatible with our minting system.</b>


Total: 812 lines of code


These contracts make extensive use of merkle trees, it is advised to review this data structure before auditing. The suggested order of audit is as they are listed above.
https://en.wikipedia.org/wiki/Merkle_tree


<h3>Unusual Calculations:</h3>

There are a couple of unusual calculations to consider. First, in MerkleResistor, the creator of a tree specifies a range of vesting schedules that the user may choose from. This is expressed as a line, a diagonal of a rectangle from (minEndTime, minTotalPayments) to (maxEndTime, maxTotalPayments). Each point on this line represents a valid end point of another line, the vesting schedule line, which is drawn from (startTime, 0) to (endTime, totalCoins). This is 2D linear algebra, but there's two lines working together, so it can be confusing. Additionally, the first line has a positive slope < 1, so we have to multiply by a precision factor to simulate floating point arithmetic. The second bit of unusual math is in SpeedBumpPriceGate, in which each purchase multiplies the price by a factor (exponential increase), after which the price decays linearly. 

<h3>Permissionlessness:</h3>

A particular concern with these contracts is their largely permissionless nature. Anyone can add merkledrops or staking pools, etc. so we must consider the possibility of malicious ERC20 contracts being added. In most contracts, each user-added struct gets its own state, while global state is minimized, in order to partition any security concerns as much as possible. In the case of malicious staking pools or trees being added, our utmost concern is that the other pools/trees are unaffected. 


<h3>NFT Minting:</h3>

The third group of contracts together form an NFT minting system. We have designed this to put NFT metadata on IPFS, because we believe this more closely matches the notion of actually owning a digital object, instead of putting the metadata on a URL controlled by some trusted third party. We have used merkle trees to do this at scale, putting the metadata URIs into a big merkle tree and passing the responsibility to the end user to pay the gas fees to prove the validity of the metadata and associate it with their NFT. This minting suite also has a traffic light system (not included here) that warns users if they are likely to collide with others trying to mint the same token ID. This system also uses merkle trees to prove eligibility to mint, making the notion of a whitelist scalable. Funds paid for NFTs flow first to MerkleIdentity then to the pricing module, then to the beneficiary.
![MintingContracts.png](MintContracts.png)

<h3>Distributing Tokens</h3>

The trio of merkle-drop merkle-vesting and merkle-resistor form another product of ours called "bank". They build upon one another, with merkle-drop being the simplest, in which tokens are allocated to many users at once via merkle tree and it is up to the user (with the help of an interface, of course) to supply the merkle proof that they are eligible to receive how many tokens. MerkleVesting builds upon this idea but adds a time lock to it, with the details of the time lock again supplied by the user and verified via merkle proof. Lastly, MerkleResistor does the same thing, but with the vesting schedule only partially specified, with the user both choosing the vesting schedule and proving the details of the vesting schedule to the contract via merkle proof. In all three of these contracts, there is no way for the contract to introspect the contents of the merkle tree at tree-creation-time, which is where the massive increase in scalability comes from. Because of this, the contracts are not able to verify any global statistics about the trees, which means that the contracts can never know if the trees have been completely exhausted or if the trees are under/over funded relative to their liabilities. Therefore each tree keeps its own balance of tokens that can be topped up by any user at any time. There is no mechanism to reclaim committed tokens to avoid the possibility of a rugpull. Fees are inserted by the frontend as an additional liability in the trees.

<h3>Yield Farming</h3>

The PermissionlessBasicPoolFactory is part of a product we have called "yield". It is designed to allow anyone to create a basic staking pool in which users put in one kind of token and receive any kind (and possibly multiple types) of fungible token in return, at any rate. Users can pull out anytime, the rate is a linear factor of the time and deposit size, and there is a global pro-rata fee paid from rewards. As the pools will in general not be 100% full all the time, we allow pool creators to specify a beneficiary that may receive excess rewards at the closure of a pool. Here again, pools are intended to be entirely separate, with malicious reward or deposit token contracts only affecting those pools in which they play a role. Under no circumstances should pools share funds. Since the reward rate is linear, we compute the maximum possible rewards distributed at pool-creation-time and take that from the user, returning the excess after the pool has completed. This ensures that pools are never underfunded, and in general overfunded.


Annotated Screens for Basic Pool are available here: https://financevote.readthedocs.io/projects/yield/en/latest/content/about.html#basic-pools




