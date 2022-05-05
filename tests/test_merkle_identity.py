import pytest
from brownie import web3, AmaluEligibility, MerkleEligibility, SpeedBumpPriceGate, \
    FixedPriceGate, AmaluPriceGate, FixedSplitPooledPriceGate
import brownie
import random
from merkle import generateRandomTree, createMerkleProof, checkMerkleProof

ipfsHash = '0x0000000000000000030000000000000000000000000000000000000000000000'

@pytest.fixture
def contracts(
        accounts,
        MerkleLib,
        DummyUniswapRouter,
        Incinerator,
        MerkleIdentity,
        VoterID,
):
    # brownie autolinks libraries!
    _ = accounts[0].deploy(MerkleLib)
    router = accounts[0].deploy(DummyUniswapRouter)
    incinerator = accounts[0].deploy(Incinerator, router, accounts[0])
    identity = accounts[0].deploy(MerkleIdentity, accounts[0])
    dummy_token = accounts[5]
    nft = accounts[0].deploy(VoterID, accounts[0], identity, 'EnEffTee', 'NFT')
    return {
        'router': router,
        'incinerator': incinerator,
        'identity': identity,
        'nft': nft,
        'token': dummy_token
    }


def make_eligibility_tree(accounts, num_leaves):
    # print('accounts', accounts[0])
    preload = [{"address": web3.toChecksumAddress(str(accounts[i]))} for i in range(len(accounts))]
    return generateRandomTree(preload, ['address'], ['address'], num_leaves)


def make_metadata_tree(num_leaves):
    metadata_hash_keys = ['tokenId', 'uri']
    metadata_hash_types = ['uint256', 'string']
    return generateRandomTree([], metadata_hash_keys, metadata_hash_types, num_leaves)


def add_merkle_tree(contracts, accounts, eligibility_contract, price_gate_contract, num_mints, num_eligible, num_metadata, total_mints):
    eligibility_tree = make_eligibility_tree(accounts, num_eligible)
    eligibility_root = eligibility_tree['root']['hash']
    num_trees_expected = contracts['identity'].numTrees() + 1
    identity_index = num_trees_expected

    if eligibility_contract == MerkleEligibility:
        if 'merkle_eligibility' not in contracts:
            contracts['merkle_eligibility'] = accounts[0].deploy(eligibility_contract, accounts[0], contracts['identity'])
        contracts['eligibility'] = contracts['merkle_eligibility']
        contracts['eligibility'].addGate(eligibility_root, num_mints, total_mints)
    elif eligibility_contract == AmaluEligibility:
        if 'amalu_eligibility' not in contracts:
            contracts['amalu_eligibility'] = accounts[0].deploy(eligibility_contract, accounts[0], contracts['identity'])
        contracts['eligibility'] = contracts['amalu_eligibility']
        contracts['eligibility'].addGate(num_mints, total_mints)

    eligibility_index = contracts['eligibility'].numGates()

    if price_gate_contract == FixedPriceGate:
        if 'fixed_price_gate' not in contracts:
            contracts['fixed_price_gate'] = accounts[0].deploy(FixedPriceGate, accounts[0])
        contracts['price_gate'] = contracts['fixed_price_gate']
        contracts['price_gate'].addGate('0.001 ether', contracts['incinerator'], contracts['token'])
    elif price_gate_contract == FixedSplitPooledPriceGate:
        if 'fixed_split_pooled_price_gate' not in contracts:
            contracts['fixed_split_pooled_price_gate'] = accounts[0].deploy(FixedSplitPooledPriceGate, accounts[0])
        contracts['price_gate'] = contracts['fixed_split_pooled_price_gate']
        benPct = random.randint(0, 100)
        contracts['price_gate'].addGate('0.001 ether', benPct, contracts['incinerator'], contracts['token'], accounts[2])
    elif price_gate_contract == SpeedBumpPriceGate:
        if 'speed_bump_price_gate' not in contracts:
            contracts['speed_bump_price_gate'] = accounts[0].deploy(SpeedBumpPriceGate, accounts[0])
        contracts['price_gate'] = contracts['speed_bump_price_gate']
        contracts['price_gate'].addGate('0.001 ether', '0.001 ether', 5, 4, contracts['incinerator'], contracts['token'])
    elif price_gate_contract == AmaluPriceGate:
        if 'amalu_price_gate' not in contracts:
            contracts['amalu_price_gate'] = accounts[0].deploy(AmaluPriceGate)
        contracts['price_gate'] = contracts['amalu_price_gate']

    price_index = contracts['price_gate'].numGates()

    metadata_tree = make_metadata_tree(num_metadata)
    metadata_root = metadata_tree['root']['hash']
    # print('metadata', metadata_tree, metadata_root)
    contracts['identity'].addMerkleTree(metadata_root, ipfsHash, contracts['nft'], contracts['price_gate'], contracts['eligibility'], eligibility_index, price_index)

    num_trees_reported = contracts['identity'].numTrees()
    assert num_trees_expected == num_trees_reported
    tree = contracts['identity'].merkleTrees(identity_index)
    assert tree['metadataMerkleRoot'] == metadata_tree['root']['hash'].hex()
    assert tree['ipfsHash'] == ipfsHash
    assert tree['nftAddress'] == contracts['nft']
    assert tree['priceGateAddress'] == contracts['price_gate']
    assert tree['eligibilityAddress'] == contracts['eligibility']
    return eligibility_tree, metadata_tree, identity_index, eligibility_index, price_index


def simulate_nft_claim(contracts, accounts, eligibility_tree, metadata_tree, merkle_index, num_mints, maxed_out, price_index, eligibility_index):
    valid_samples = [x for x in metadata_tree['nodes'] if x['data'] is not None]
    mint_attempts = len(accounts) * (num_mints + 1)
    if len(valid_samples) <= mint_attempts:
        nodes = valid_samples
    else:
        nodes = random.sample(valid_samples, k=len(valid_samples))
    expected_tokens_burned = contracts['incinerator'].tokensBurned(accounts[5])
    for i in range(len(accounts)):
        leaf = eligibility_tree['nodes'][i]
        address_proof = createMerkleProof(eligibility_tree, leaf)
        assert checkMerkleProof(address_proof, eligibility_tree, leaf)

        for j in range(num_mints):
            if len(nodes) == 0:
                return
            random_choice = nodes.pop()
            metadata_proof = createMerkleProof(metadata_tree, random_choice)
            assert checkMerkleProof(metadata_proof, metadata_tree, random_choice)
            nft_price = contracts['identity'].getPrice(merkle_index)

            gate = contracts['eligibility'].getGate(eligibility_index)
            if gate[-1] == gate[-2]:
                assert not contracts['identity'].isEligible(merkle_index, accounts[i], address_proof)
                with brownie.reverts('Address is not eligible'):
                    contracts['identity'].withdraw(
                        merkle_index,
                        random_choice['data']['tokenId'],
                        random_choice['data']['uri'],
                        address_proof,
                        metadata_proof,
                        {'value': nft_price, 'from': accounts[i]})
            else:
                assert contracts['identity'].isEligible(merkle_index, accounts[i], address_proof)
                contracts['identity'].withdraw(
                    merkle_index,
                    random_choice['data']['tokenId'],
                    random_choice['data']['uri'],
                    address_proof,
                    metadata_proof,
                    {'value': nft_price, 'from': accounts[i]})
                if contracts['price_gate'] not in [contracts.get('fixed_split_pooled_price_gate', None), contracts.get('amalu_price_gate', None)]:
                    expected_tokens_burned += nft_price
                    tokens_burned = contracts['incinerator'].tokensBurned(accounts[5])
                    print(contracts['price_gate'], nft_price, tokens_burned, expected_tokens_burned)
                    # assert tokens_burned == expected_tokens_burned
                with brownie.reverts('Token already exists'):
                    contracts['identity'].withdraw(
                        merkle_index,
                        random_choice['data']['tokenId'],
                        random_choice['data']['uri'],
                        address_proof,
                        metadata_proof,
                        {'value': nft_price, 'from': accounts[i]})
        if maxed_out and len(nodes) > 0:
            with brownie.reverts('Address is not eligible'):
                random_choice = nodes.pop()
                metadata_proof = createMerkleProof(metadata_tree, random_choice)
                assert checkMerkleProof(metadata_proof, metadata_tree, random_choice)
                nft_price = contracts['identity'].getPrice(merkle_index)

                contracts['identity'].withdraw(
                    merkle_index,
                    random_choice['data']['tokenId'],
                    random_choice['data']['uri'],
                    address_proof,
                    metadata_proof,
                    {'value': nft_price, 'from': accounts[i]})

        print('contracts', contracts['price_gate'], contracts.get('fixed_split_pooled_price_gate', None))
        if contracts['price_gate'] == contracts.get('fixed_split_pooled_price_gate', None):
            gate_before = contracts['price_gate'].gates(price_index)
            balance = gate_before[0]
            to_be_burned = (100 - gate_before[-1]) * balance // 100
            burned_before = contracts['incinerator'].tokensBurned(accounts[5])
            contracts['price_gate'].distribute(price_index)
            burned_after = contracts['incinerator'].tokensBurned(accounts[5])
            gate_after = contracts['price_gate'].gates(price_index)
            balance_after = gate_after[0]
            assert burned_after - burned_before == to_be_burned
            assert contracts['price_gate'].balance() == 0
            assert balance_after == 0


def test_add_merkle_tree(contracts, accounts):
    num_mints = 50
    num_eligible = 1
    num_metadata = 50
    total_mints = 49
    eligibility_tree, metadata_tree, identity_index, eligibility_index, price_index = add_merkle_tree(contracts, accounts, MerkleEligibility, AmaluPriceGate, num_mints, num_eligible, num_metadata, total_mints)
    simulate_nft_claim(contracts, accounts, eligibility_tree, metadata_tree, identity_index, num_mints, True, price_index, eligibility_index)

    num_mints = 5
    num_eligible = 500
    num_metadata = 15
    total_mints = 14
    eligibility_tree, metadata_tree, identity_index, eligibility_index, price_index = add_merkle_tree(contracts, accounts, MerkleEligibility, FixedPriceGate, num_mints, num_eligible, num_metadata, total_mints)
    simulate_nft_claim(contracts, accounts, eligibility_tree, metadata_tree, identity_index, num_mints, True, price_index, eligibility_index)

    num_mints = 1
    num_eligible = 1200
    num_metadata = 85
    total_mints = 84
    eligibility_tree, metadata_tree, identity_index, eligibility_index, price_index = add_merkle_tree(contracts, accounts, MerkleEligibility, FixedSplitPooledPriceGate, num_mints, num_eligible, num_metadata, total_mints)
    simulate_nft_claim(contracts, accounts, eligibility_tree, metadata_tree, identity_index, num_mints, True, price_index, eligibility_index)

    num_mints = 10000
    num_eligible = 1
    num_metadata = 85
    total_mints = 84
    eligibility_tree, metadata_tree, identity_index, eligibility_index, price_index = add_merkle_tree(contracts, accounts, AmaluEligibility, SpeedBumpPriceGate, num_mints, num_eligible, num_metadata, total_mints)
    simulate_nft_claim(contracts, accounts, eligibility_tree, metadata_tree, identity_index, num_mints, False, price_index, eligibility_index)

    print('contracts', contracts)

