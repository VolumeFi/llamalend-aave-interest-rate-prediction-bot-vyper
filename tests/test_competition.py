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
    return Deployer.deploy(project.testToken, "USDT", "USDT", 6, 10000000000000)

@pytest.fixture(scope="session")
def CompetitionArb(Deployer, project, Compass, USDT, Alice, Admin):
    contract = Deployer.deploy(project.competitionArb, Compass, USDT, Alice, Admin)
    funcSig = function_signature("set_paloma()")
    addPayload = encode(["bytes32"], [b'123456'])
    payload = funcSig + addPayload
    contract(sender=Compass, data=payload)

    return contract

def function_signature(str):
    return Web3.keccak(text=str)[:4]

def test_add():
    assert 1 + 1 == 2

def test_competition_arb(Deployer, accounts, CompetitionArb, Compass, Alice, chain):
    assert Deployer == accounts[0]

    func_sig = function_signature(
        "set_active_epoch((uint256,uint256,uint256,uint256,uint256))")
    enc_abi = encode(["(uint256,uint256,uint256,uint256,uint256)"], [(1, 1716249600, 1716336000, 0, 10000000)])
    add_payload = encode(["bytes32"], [b'123456'])
    payload = func_sig + enc_abi + add_payload
    CompetitionArb(sender=Compass, data=payload)

    assert CompetitionArb.epoch_info().epoch_id == 1
    assert CompetitionArb.epoch_info().competition_start == 1716249600
    assert CompetitionArb.epoch_info().competition_end == 1716336000
    assert CompetitionArb.epoch_info().entry_cnt == 0
    assert CompetitionArb.epoch_info().prize_amount == 10000000