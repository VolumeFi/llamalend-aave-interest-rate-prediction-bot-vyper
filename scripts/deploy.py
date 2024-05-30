from ape import accounts, project, networks

def main():
    with networks.parse_network_choice("arbitrum:mainnet:alchemy") as provider:
        acct = accounts.load("deployer_account")
        print(acct.address, acct.balance)
        compass = ""    # new compass arb-main
        reward = ""     # USDT
        factory = ""    # llamalend bot factory
        admin = ""

        competitionArb = project.competitionArb.deploy(compass, reward, factory, admin, sender=acct)
        print(competitionArb)