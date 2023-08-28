import pytest
import brownie
from brownie import web3, PermissionlessBasicPoolFactory, Token
from numpy.random import choice
import time


def test_add_pool(accounts):
    factory = accounts[0].deploy(PermissionlessBasicPoolFactory, accounts[-1], 10)
    token = accounts[0].deploy(Token, '', '', 18, '100000000 ether')
    assert factory.globalBeneficiary() == accounts[-1]
    assert factory.globalTaxPerCapita() == 10
    with brownie.reverts():
        factory.addPool(0, '1000000 ether', ['1000'], 1, token, accounts[-2], [token], '0x0', '0x01')

    rewards_per_second_per_token = 1000
    max_rewards = 86400 * rewards_per_second_per_token * 1000000

    token.approve(factory, max_rewards, {'from': accounts[0]})

    pool_owner_balance_before = token.balanceOf(accounts[0])
    factory_balance_before = token.balanceOf(factory)
    factory.addPool(0, '1000000 ether', [rewards_per_second_per_token], 1, token, accounts[-2], [token], '0x0', '0x01', {'from': accounts[0]})
    pool_owner_balance_after = token.balanceOf(accounts[0])
    factory_balance_after = token.balanceOf(factory)
    assert pool_owner_balance_before - pool_owner_balance_after == max_rewards
    assert factory_balance_after - factory_balance_before == max_rewards
    assert factory.getRewardData(1) == [[rewards_per_second_per_token], [0], [token], [max_rewards]]


def test_deposit_withdraw(accounts, chain):
    tax_per_capita = 10
    factory = accounts[0].deploy(PermissionlessBasicPoolFactory, accounts[-1], tax_per_capita)
    token = accounts[0].deploy(Token, '', '', 18, '100000000 ether')

    rewards_per_second_per_token = 1000
    max_rewards = 86400 * rewards_per_second_per_token * 1000000

    token.approve(factory, max_rewards, {'from': accounts[0]})
    factory.addPool(0, '1000000 ether', [rewards_per_second_per_token], 1, token, accounts[-2], [token], '0x0', '0x01', {'from': accounts[0]})

    chain.sleep(1)
    depositor = accounts[1]
    taxman = accounts[-1]
    token.transfer(depositor, '1000000 ether', {'from': accounts[0]})
    token.approve(factory, '1000000 ether', {'from': depositor})
    depositor_balance_before = token.balanceOf(depositor)
    taxman_balance_before = token.balanceOf(taxman)
    chain_time_before = chain.time()
    factory.deposit(1, '1000000 ether', {'from': depositor})
    depositor_balance_after = token.balanceOf(depositor)
    chain.sleep(1)
    t = factory.withdraw(1, 1, {'from': depositor})

    chain_time_after = t.timestamp
    depositor_balance_after2 = token.balanceOf(depositor)
    taxman_balance_after = token.balanceOf(taxman)
    expected_rewards = rewards_per_second_per_token * 1000000 * (chain_time_after - chain_time_before)
    tax = expected_rewards * tax_per_capita // 1000
    assert depositor_balance_before - depositor_balance_after == '1000000 ether'
    assert depositor_balance_after2 == depositor_balance_before + expected_rewards - tax
    assert taxman_balance_after - taxman_balance_before == 0

    factory.withdrawTaxes(1)
    taxman_balance_after = token.balanceOf(taxman)

    assert taxman_balance_after - taxman_balance_before == tax


def test_withdraw_excess(accounts, chain):
    tax_per_capita = 10
    taxman = accounts[-1]
    factory = accounts[0].deploy(PermissionlessBasicPoolFactory, taxman, tax_per_capita)
    token = accounts[0].deploy(Token, '', '', 18, '100000000 ether')

    rewards_per_second_per_token = 1000
    max_rewards = 86400 * rewards_per_second_per_token * 1000000
    pool_length_days = 1
    day_length = 86400
    depositor = accounts[1]
    excess_beneficiary = accounts[-2]

    token.approve(factory, max_rewards, {'from': accounts[0]})
    t = factory.addPool(0, '1000000 ether', [rewards_per_second_per_token], pool_length_days, token, excess_beneficiary, [token], '0x0', '0x01', {'from': accounts[0]})
    pool_time = t.timestamp
    chain.sleep(1)
    with brownie.reverts('Contract must reach maturity'):
        factory.withdrawExcessRewards(1)

    token.transfer(depositor, '1000000 ether', {'from': accounts[0]})
    token.approve(factory, '1000000 ether', {'from': depositor})
    t = factory.deposit(1, '1000000 ether', {'from': depositor})
    deposit_time = t.timestamp
    chain.sleep(day_length)

    with brownie.reverts('Cannot withdraw until all deposits are withdrawn'):
        factory.withdrawExcessRewards(1)
    with brownie.reverts('Uninitialized pool'):
        factory.withdrawExcessRewards(2)

    factory.withdraw(1, 1, {'from': depositor})

    untaxed_rewards = (day_length - (deposit_time - pool_time)) * max_rewards / day_length
    tax = untaxed_rewards * tax_per_capita // 1000
    expected_rewards = untaxed_rewards - tax

    assert token.balanceOf(depositor) - expected_rewards == '1000000 ether'
    assert token.balanceOf(excess_beneficiary) == 0
    assert token.balanceOf(taxman) == 0

    factory.withdrawTaxes(1)

    assert token.balanceOf(depositor) - expected_rewards == '1000000 ether'
    assert token.balanceOf(excess_beneficiary) == 0
    assert token.balanceOf(taxman) == tax

    factory.withdrawExcessRewards(1)

    assert token.balanceOf(depositor) - expected_rewards == '1000000 ether'
    assert token.balanceOf(excess_beneficiary) == max_rewards - untaxed_rewards
    assert token.balanceOf(taxman) == tax

    factory.withdrawTaxes(1)

    assert token.balanceOf(depositor) - expected_rewards == '1000000 ether'
    assert token.balanceOf(excess_beneficiary) == max_rewards - untaxed_rewards
    assert token.balanceOf(taxman) == tax

    factory.withdrawExcessRewards(1)

    assert token.balanceOf(depositor) - expected_rewards == '1000000 ether'
    assert token.balanceOf(excess_beneficiary) == max_rewards - untaxed_rewards
    assert token.balanceOf(taxman) == tax



def test_pools_dont_share(accounts, chain):
    tax_per_capita = 10
    global_beneficiary = accounts[-1]
    factory = accounts[0].deploy(PermissionlessBasicPoolFactory, global_beneficiary, tax_per_capita)
    token = accounts[0].deploy(Token, '', '', 18, '100000000 ether')

    rewards_per_second_per_token = 1000
    max_rewards_1 = 86400 * rewards_per_second_per_token * 1000000
    max_rewards_2 = 86400 * rewards_per_second_per_token * 2000000
    pool_length_days = 1
    day_length = 86400
    excess_beneficiary = accounts[-2]
    depositor = accounts[1]
    deposit_1 = '1000000 ether'
    deposit_2 = '2000000 ether'


    token.transfer(depositor, deposit_1, {'from': accounts[0]})
    token.transfer(depositor, deposit_2, {'from': accounts[0]})

    token.approve(factory, max_rewards_1, {'from': accounts[0]})
    t = factory.addPool(0, deposit_1, [rewards_per_second_per_token], pool_length_days, token, excess_beneficiary, [token], '0x0', '0x01', {'from': accounts[0]})
    pool_time_1 = t.timestamp
    chain.sleep(1)
    token.approve(factory, deposit_1, {'from': depositor})
    t = factory.deposit(1, deposit_1, {'from': depositor})
    deposit_time_1 = t.timestamp

    with brownie.reverts():
        factory.addPool(0, deposit_2, [rewards_per_second_per_token], pool_length_days, token, excess_beneficiary, [token], '0x0', '0x01', {'from': accounts[0]})
    token.approve(factory, max_rewards_2, {'from': accounts[0]})
    t = factory.addPool(0, deposit_2, [rewards_per_second_per_token], pool_length_days, token, excess_beneficiary, [token], '0x0', '0x01', {'from': accounts[0]})
    pool_time_2 = t.timestamp

    chain.sleep(day_length // 2)
    token.approve(factory, deposit_2, {'from': depositor})
    t = factory.deposit(2, deposit_2, {'from': depositor})
    deposit_time_2 = t.timestamp

    assert token.balanceOf(factory) - max_rewards_1 - max_rewards_2 == '3000000 ether'
    assert token.balanceOf(excess_beneficiary) == 0
    assert token.balanceOf(depositor) == 0
    assert token.balanceOf(global_beneficiary) == 0

    chain.sleep(day_length * 2)

    factory.withdraw(1, 1, {'from': depositor})
    untaxed_rewards_1 = (day_length - (deposit_time_1 - pool_time_1)) * max_rewards_1 / day_length
    tax_1 = untaxed_rewards_1 * tax_per_capita // 1000
    expected_rewards_1 = untaxed_rewards_1 - tax_1
    leftover_rewards_1 = max_rewards_1 - untaxed_rewards_1
    assert token.balanceOf(factory) - max_rewards_2 - leftover_rewards_1 - tax_1 == '2000000 ether'
    assert token.balanceOf(excess_beneficiary) == 0
    assert token.balanceOf(depositor) - expected_rewards_1 == '1000000 ether'
    assert token.balanceOf(global_beneficiary) == 0

    factory.withdraw(2, 1, {'from': depositor})
    untaxed_rewards_2 = (day_length - (deposit_time_2 - pool_time_2)) * max_rewards_2 / day_length
    tax_2 = untaxed_rewards_2 * tax_per_capita // 1000
    expected_rewards_2 = untaxed_rewards_2 - tax_2
    leftover_rewards_2 = max_rewards_2 - untaxed_rewards_2
    assert token.balanceOf(factory) == leftover_rewards_2 + leftover_rewards_1 + tax_2 + tax_1
    assert token.balanceOf(excess_beneficiary) == 0
    assert token.balanceOf(depositor) - expected_rewards_2 - expected_rewards_1 == '3000000 ether'
    assert token.balanceOf(global_beneficiary) == 0

    factory.withdrawExcessRewards(1)

    assert token.balanceOf(factory) == leftover_rewards_2 + tax_2 + tax_1
    assert token.balanceOf(excess_beneficiary) == leftover_rewards_1
    assert token.balanceOf(depositor) - expected_rewards_1 - expected_rewards_2 == '3000000 ether'
    assert token.balanceOf(global_beneficiary) == 0

    factory.withdrawExcessRewards(1)

    assert token.balanceOf(factory) == leftover_rewards_2 + tax_2 + tax_1
    assert token.balanceOf(excess_beneficiary) == leftover_rewards_1
    assert token.balanceOf(depositor) - expected_rewards_1 - expected_rewards_2 == '3000000 ether'
    assert token.balanceOf(global_beneficiary) == 0

    factory.withdrawExcessRewards(2)

    assert token.balanceOf(factory) == tax_1 + tax_2
    assert token.balanceOf(excess_beneficiary) == leftover_rewards_1 + leftover_rewards_2
    assert token.balanceOf(depositor) - expected_rewards_1 - expected_rewards_2 == '3000000 ether'
    assert token.balanceOf(global_beneficiary) == 0

    factory.withdrawExcessRewards(2)

    assert token.balanceOf(factory) == tax_1 + tax_2
    assert token.balanceOf(excess_beneficiary) == leftover_rewards_1 + leftover_rewards_2
    assert token.balanceOf(depositor) - expected_rewards_1 - expected_rewards_2 == '3000000 ether'
    assert token.balanceOf(global_beneficiary) == 0

    factory.withdrawTaxes(2)
    assert token.balanceOf(global_beneficiary) == tax_2
    factory.withdrawTaxes(2)
    assert token.balanceOf(global_beneficiary) == tax_2

    factory.withdrawTaxes(1)
    assert token.balanceOf(global_beneficiary) == tax_1 + tax_2
    factory.withdrawTaxes(1)
    factory.withdrawTaxes(2)
    with brownie.reverts('Uninitialized pool'):
        factory.withdrawTaxes(4)
    with brownie.reverts('Uninitialized pool'):
        factory.withdrawTaxes(3)
    assert token.balanceOf(global_beneficiary) == tax_1 + tax_2

