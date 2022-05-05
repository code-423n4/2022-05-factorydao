import pytest
from brownie import web3, VoterID
import brownie
from numpy.random import choice


def get_tokens(nft, owner):
    return [nft.tokenOfOwnerByIndex(owner, j) for j in range(nft.balances(owner))]


def test_voter_id(VoterID, accounts):
    minter = accounts[0]
    owner = accounts[1]
    nft = accounts[0].deploy(VoterID, owner, minter, 'EnEffTee', 'NFT')

    to_mint = choice(range(10000), size=100, replace=False)

    for i, token_id in enumerate(to_mint):
        account = accounts[i % len(accounts)]
        nft.createIdentityFor(account, token_id, '', {'from': minter})

    for i in range(10):
        token_id = choice(to_mint, 1)[0]
        sender = nft.ownerOf(token_id)
        recipient = sender
        while recipient == sender:
            recipient = accounts[i % len(accounts)]
        recipient_tokens_before = get_tokens(nft, recipient)
        sender_tokens_before = get_tokens(nft, sender)
        nft.transferFrom(sender, recipient, token_id, {'from': sender})
        recipient_tokens_after = get_tokens(nft, recipient)
        sender_tokens_after = get_tokens(nft, sender)

        print(recipient_tokens_before, recipient_tokens_after)
        recipient_tokens_after.remove(token_id)
        assert sorted(recipient_tokens_before) == sorted(recipient_tokens_after)

        print(sender_tokens_before, sender_tokens_after)
        sender_tokens_before.remove(token_id)
        assert sorted(sender_tokens_after) == sorted(sender_tokens_before)

