import ape
import pytest
from eth_abi import encode
from web3 import Web3

@pytest.fixture(scope="session")
def Deployer(accounts):
    return accounts[0]

@pytest.fixture(scope="session")
def Admin(accounts):
    return accounts[1]

@pytest.fixture(scope="session")
def Alice(accounts):
    return accounts[2]

@pytest.fixture(scope="session")
def Compass(accounts):
    return accounts[3]

@pytest.fixture(scope="session")
def USDT(Deployer, project):
    print(project)
    return Deployer.deploy(project.testToken, "USDT", "USDT", 6, 10000000000000)

def function_signature(str):
    return Web3.keccak(text=str)[:4]

def test_add():
    assert 1 + 1 == 2

@pytest.fixture(scope="session")
def CompetitionArb(Deployer, project, Compass, USDT, Alice, Admin):
    contract = Deployer.deploy(project.competitionArb, Compass, USDT, Alice, Admin)
    funcSig = function_signature("set_paloma()")
    addPayload = encode(["bytes32"], [b'123456'])
    payload = funcSig + addPayload
    contract(sender=Compass, data=payload)

    return contract

def test_competition_arb(Deployer, accounts, CompetitionArb, Compass, Alice, USDT, Admin, chain):
    assert Deployer == accounts[0]

    assert CompetitionArb.epoch_cnt() == 0
    USDT.approve(CompetitionArb.address, 1000000000, sender=Deployer)
    receipt = CompetitionArb.send_reward(1000000000, 1, sender=Deployer)
    assert not receipt.failed
    assert CompetitionArb.epoch_cnt() == 1
    assert CompetitionArb.active_epoch_num() == 1

    USDT.approve(CompetitionArb.address, 4000000000, sender=Deployer)
    receipt = CompetitionArb.send_reward(2000000000, 2, sender=Deployer)
    assert not receipt.failed
    assert CompetitionArb.epoch_cnt() == 3

    with ape.reverts():
        USDT.approve(CompetitionArb.address, 6000000000, sender=Deployer)
        receipt = CompetitionArb.send_reward(1000000000, 6, sender=Deployer)

    assert CompetitionArb.epoch_info(1).competition_start == 1719360000
    assert CompetitionArb.epoch_info(1).competition_end == 1719446400

    assert CompetitionArb.epoch_info(2).competition_start == 1719446400
    assert CompetitionArb.epoch_info(2).competition_end == 1719532800

    active_epoch_num = CompetitionArb.active_epoch_num()
    chain.pending_timestamp += 86400
    CompetitionArb.bid("0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9", sender=Alice)
    assert CompetitionArb.epoch_info(active_epoch_num).entry_cnt == 1
    with ape.reverts():
        CompetitionArb.bid("0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9", sender=Alice)

    func_sig = function_signature(
        "set_winner_list((address,uint256)[])")
    enc_abi = encode(["(address,uint256)[]"], [[(Deployer.address, 1000000000)]])
    # enc_abi = encode(["(address,uint256)[]"], [[]])
    add_payload = encode(["bytes32"], [b'123456'])
    payload = func_sig + enc_abi + add_payload
    with ape.reverts():
        CompetitionArb.set_winner_list([], sender=Compass)
    CompetitionArb(sender=Compass, data=payload)
    assert CompetitionArb.active_epoch_num() == 2
    assert CompetitionArb.epoch_info(2).prize_amount == 2000000000

    chain.pending_timestamp += 86400
    active_epoch_num = CompetitionArb.active_epoch_num()
    CompetitionArb.bid("0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9", sender=Alice)
    CompetitionArb.bid("0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9", sender=Deployer)
    assert CompetitionArb.epoch_info(active_epoch_num).entry_cnt == 2
    with ape.reverts():
        CompetitionArb.bid("0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9", sender=Alice)

    assert CompetitionArb.claimable_amount(Deployer.address) == 1000000000

    balance = USDT.balanceOf(CompetitionArb.address)
    CompetitionArb.emergency_withdraw(balance, sender=Admin)

    balance = USDT.balanceOf(CompetitionArb.address)
    assert balance == 0
