#pragma version 0.3.10
#pragma optimize gas
#pragma evm-version shanghai
"""
@title      CRV price prediction competition for Juice Bot
@license    Apache 2.0
@author     Volume.finance
"""
struct EpochInfo:
    competition_start: uint256
    competition_end: uint256
    entry_cnt: uint256
    prize_amount: uint256

struct WinnerInfo:
    winner: address
    claimable_amount: uint256

struct BidInfo:
    sender: address
    aave_version: uint256
    chain_id: uint256
    token_asset: address

struct SwapInfo:
    route: address[11]
    swap_params: uint256[5][5]
    amount: uint256
    expected: uint256
    pools: address[5]

MAX_ENTRY: constant(uint256) = 1000
MAX_SIZE: constant(uint256) = 8
DAY_IN_SEC: constant(uint256) = 86400
MAX_FUNDABLE_DAYS: constant(uint256) = 5

FACTORY: public(immutable(address))
REWARD_TOKEN: public(immutable(address))
DECIMALS: public(immutable(uint256))

paloma: public(bytes32)
compass: public(address)
admin: public(address)
epoch_cnt: public(uint256)
active_epoch_num: public(uint256)
epoch_info: public(HashMap[uint256, EpochInfo])
bid_info: public(HashMap[uint256, DynArray[BidInfo, MAX_ENTRY]])
my_info: public(HashMap[uint256, HashMap[address, BidInfo]])
winner_info: public(HashMap[uint256, HashMap[address, uint256]])
claimable_amount: public(HashMap[address, uint256])

interface ERC20:
    def approve(_spender: address, _value: uint256) -> bool: nonpayable
    def transfer(_to: address, _value: uint256) -> bool: nonpayable
    def transferFrom(_from: address, _to: address, _value: uint256) -> bool: nonpayable
    def decimals() -> uint8: view

interface CreateBotFactory:
    def create_bot(
        swap_infos: DynArray[SwapInfo, MAX_SIZE], 
        collateral: address, 
        debt: uint256, 
        N: uint256, 
        callbacker: address, 
        callback_args: DynArray[uint256, 5], 
        leverage: uint256, 
        deleverage_percentage: uint256, 
        health_threshold: uint256, 
        expire: uint256, 
        number_trades: uint256, 
        interval: uint256,
        delegate: address = msg.sender
    ): payable

event Bid:
    epoch_id: uint256
    sender: address
    aave_version: uint256
    chain_id: uint256
    token_asset: address

event RewardSent:
    epoch_id: uint256
    sender: address
    reward_token: address
    amount: uint256
    competition_start: uint256
    competition_end: uint256

event SetPaloma:
    paloma: bytes32

event UpdateCompass:
    old_compass: address
    new_compass: address

event UpdateAdmin:
    old_admin: address
    new_admin: address

event SetWinner:
    epoch_id: uint256
    winner: address
    claimable_amount: uint256

event RollOverReward:
    epoch_id: uint256
    rollover_amount: uint256

event Claimed:
    sender: address
    claimed_amount: uint256

event EmergencyWithdraw:
    emergency: address
    amount: uint256

@external
def __init__(_compass: address, _reward_token: address, _factory: address, _admin: address):
    self.compass = _compass
    self.admin = _admin
    REWARD_TOKEN = _reward_token
    DECIMALS = convert(ERC20(_reward_token).decimals(), uint256)
    FACTORY = _factory
    log UpdateCompass(empty(address), _compass)
    log UpdateAdmin(empty(address), _admin)

@internal
def _paloma_check():
    assert msg.sender == self.compass, "Not compass"
    assert self.paloma == convert(slice(msg.data, unsafe_sub(len(msg.data), 32), 32), bytes32), "Invalid paloma"

@internal
def _admin_check():
    assert msg.sender == self.admin, "Not admin"

@external
def update_compass(_new_compass: address):
    self._paloma_check()
    self.compass = _new_compass
    log UpdateCompass(msg.sender, _new_compass)

@external
def update_admin(_new_admin: address):
    self._admin_check()
    self.admin = _new_admin
    log UpdateAdmin(msg.sender, _new_admin)

@external
def set_paloma():
    assert msg.sender == self.compass and self.paloma == empty(bytes32) and len(msg.data) == 36, "Invalid"
    _paloma: bytes32 = convert(slice(msg.data, 4, 32), bytes32)
    self.paloma = _paloma
    log SetPaloma(_paloma)

@external
def emergency_withdraw(_amount: uint256):
    self._admin_check()
    _admin: address = self.admin
    assert ERC20(REWARD_TOKEN).transfer(_admin, _amount, default_return_value=True), "Emergency withdraw Failed"
    log EmergencyWithdraw(_admin, _amount) 

@external
def send_reward(_daily_amount: uint256, _days: uint256):
    assert _daily_amount > 0, "Invalid Fund Amount"
    assert _days > 0, "Invalid days"
    assert _days <= MAX_FUNDABLE_DAYS, "MAX Fundable Days 5"

    # Transfer reward token to the contract
    assert ERC20(REWARD_TOKEN).transferFrom(msg.sender, self, unsafe_mul(_daily_amount, _days), default_return_value=True), "Send Reward Failed"

    _epoch_cnt: uint256 = self.epoch_cnt
    _competition_start: uint256 = 0
    _competition_end: uint256 = 0

    for _i in range(MAX_FUNDABLE_DAYS):
        if _i < _days:
            if _epoch_cnt > 0:
                _last_epoch_info: EpochInfo = self.epoch_info[_epoch_cnt]
                _last_competition_start: uint256 = _last_epoch_info.competition_start
                _last_competition_end: uint256 = _last_epoch_info.competition_end

                _epoch_cnt = unsafe_add(_epoch_cnt, 1)
                if block.timestamp >= _last_competition_start:
                    _competition_start = unsafe_add(unsafe_mul(unsafe_div(block.timestamp, DAY_IN_SEC), DAY_IN_SEC), DAY_IN_SEC)
                    _competition_end = unsafe_add(_competition_start, DAY_IN_SEC)
                elif block.timestamp < _last_competition_start:
                    _competition_start = unsafe_add(_last_competition_start, DAY_IN_SEC)
                    _competition_end = unsafe_add(_last_competition_end, DAY_IN_SEC)
            else:
                _epoch_cnt = unsafe_add(_epoch_cnt, 1)
                self.active_epoch_num = unsafe_add(self.active_epoch_num, 1)

                _competition_start = unsafe_add(unsafe_mul(unsafe_div(block.timestamp, DAY_IN_SEC), DAY_IN_SEC), DAY_IN_SEC)
                _competition_end = unsafe_add(_competition_start, DAY_IN_SEC)

            _current_prize_amount: uint256 = self.epoch_info[_epoch_cnt].prize_amount
            self.epoch_info[_epoch_cnt] = EpochInfo({
                competition_start: _competition_start,
                competition_end: _competition_end,
                entry_cnt: 0,
                prize_amount: _current_prize_amount + _daily_amount
            })

            # Event Log
            log RewardSent(_epoch_cnt, msg.sender, REWARD_TOKEN, _daily_amount, _competition_start, _competition_end)

    self.epoch_cnt = _epoch_cnt

@external
def set_winner_list(_winner_infos: DynArray[WinnerInfo, MAX_ENTRY]):
    self._paloma_check()

    _active_epoch_num: uint256 = self.active_epoch_num
    assert _active_epoch_num <= self.epoch_cnt, "No Reward yet"

    _winner_len: uint256 = len(_winner_infos)
    _next_epoch_num: uint256 = unsafe_add(_active_epoch_num, 1)
    if _winner_len == 0:
        _next_prize_amount: uint256 = self.epoch_info[_next_epoch_num].prize_amount
        _current_prize_amount: uint256 = self.epoch_info[_active_epoch_num].prize_amount
        self.epoch_info[_next_epoch_num].prize_amount = _next_prize_amount + _current_prize_amount

        log RollOverReward(_active_epoch_num, _current_prize_amount)
    else:
        for _winner_info in _winner_infos:
            self.winner_info[_active_epoch_num][_winner_info.winner] = _winner_info.claimable_amount
            self.claimable_amount[_winner_info.winner] = unsafe_add(self.claimable_amount[_winner_info.winner], _winner_info.claimable_amount)

            log SetWinner(_active_epoch_num, _winner_info.winner, _winner_info.claimable_amount)

    # increase activeEpochNum for activating the next Epoch
    self.active_epoch_num = _next_epoch_num

@external
def bid(_token_asset: address, _chain_id: uint256, _aave_version: uint256):
    _active_epoch_num: uint256 = self.active_epoch_num
    _epoch_info: EpochInfo = self.epoch_info[_active_epoch_num]
    
    assert block.timestamp >= _epoch_info.competition_start, "Not Active 1"
    assert block.timestamp < _epoch_info.competition_end, "Not Active 2"
    assert _epoch_info.entry_cnt < MAX_ENTRY, "Entry Limited"
    assert self.my_info[_active_epoch_num][msg.sender].token_asset == empty(address), "Already bid"
    assert _token_asset != empty(address), "Invalid"
    assert _chain_id > 0, "Shouldn't be zero"
    assert _aave_version > 0, "Shouldn't be zero"

    _epoch_info.entry_cnt = unsafe_add(_epoch_info.entry_cnt, 1)

    #Write
    _bid_info: BidInfo = BidInfo({
        sender: msg.sender,
        aave_version: _aave_version,
        chain_id: _chain_id,
        token_asset: _token_asset
    })
    self.bid_info[_active_epoch_num].append(_bid_info)
    self.my_info[_active_epoch_num][msg.sender] = _bid_info

    # Event Log
    log Bid(_active_epoch_num, msg.sender, _aave_version, _chain_id, _token_asset)

@external
@payable
@nonreentrant("lock")
def create_bot(swap_infos: DynArray[SwapInfo, MAX_SIZE],
        collateral: address, 
        debt: uint256, 
        N: uint256, 
        callbacker: address, 
        callback_args: DynArray[uint256, 5], 
        leverage: uint256, 
        deleverage_percentage: uint256, 
        health_threshold: uint256, 
        expire: uint256, 
        number_trades: uint256, 
        interval: uint256):
    
    _claimable_amount: uint256 = self.claimable_amount[msg.sender]
    assert _claimable_amount > 0, "No Claimable Amount"

    assert ERC20(REWARD_TOKEN).approve(FACTORY, _claimable_amount, default_return_value=True), "Approve Failed"
    CreateBotFactory(FACTORY).create_bot(
        swap_infos, 
        collateral, 
        debt, 
        N, 
        callbacker, 
        callback_args, 
        leverage, 
        deleverage_percentage, 
        health_threshold,
        expire,
        number_trades,
        interval, 
        msg.sender, 
        value=msg.value)

    log Claimed(msg.sender, _claimable_amount)

    # init claimable amount 
    self.claimable_amount[msg.sender] = 0

@external
@payable
def __default__():
    pass
