pragma solidity ^0.4.4;

import "libFuture.sol";

contract Future{
  LibFuture.data data;

  bool constant SHORT_SIDE = true;
  bool constant LONG_SIDE = false;

  function Future(
                  address user,
                  uint _date,
                  uint32 _rate,
                  uint8 _ratio,
                  bool openShort,
                  uint32 _ID
                  ) payable {
    LibFuture.init(data, user, _date, _rate, _ratio, openShort, _ID);
  }

  function withdraw() public returns (bool) {
    return LibFuture.withdraw(data);
  }

  function emitNew(bool side) public {
    LibFuture.emitNew(data, side);
  }
    
  function getInfo()
    public
    constant
    returns (uint32, uint, uint8, uint, uint8, uint, uint, address, address)
  {
    return (data.ID, // 0
            data.expireDate, // 1
            data.ratio, // 2
            data.initialRate, // 3
            uint8(data.stage), // 4
            data.shortPrice, // 5
            data.longPrice, // 6
            data.S, // 7
            data.L); // 8
  }

  // cancel contract if not matched
  function cancel(address from)
    public
  {
    LibFuture.cancel(data, from);
  }

  function modifyRate(address from, uint32 rate)
    public
  {
    LibFuture.modifyRate(data, from, rate);
  }
    
  function shortSell(address from, uint price) public {
    LibFuture.sell(data, from, price, SHORT_SIDE);
  }

  function longSell(address from, uint price) public {
    LibFuture.sell(data, from, price, LONG_SIDE);
  }

  function shortBuy(address from) public payable returns (bool) {
    return LibFuture.buy(data, from, SHORT_SIDE);
  }

  function longBuy(address from) public payable returns (bool) {
    return LibFuture.buy(data, from, LONG_SIDE);
  }

  // expire by admin or market after expireDate
  // shorter/longer can force expiring the future 3 days after expiration
  function expire() public {
    if (now < data.expireDate) throw;
     if (now >= data.expireDate && now < data.expireDate + 3 days) {
       if (msg.sender!=0xfE02a56127aFfBba940bB116Fa30A3Af10d12f80 && msg.sender!=data.market) throw;
       LibFuture.expire(data);
     } else {
       if (msg.sender!=data.S && msg.sender!=data.L) throw;
       LibFuture.abnormalExpire(data);
    }
  }

  // only in alpha test; expire early by admin
  function forceExpire() public {
    if (msg.sender!='0xfE02a56127aFfBba940bB116Fa30A3Af10d12f80') throw;
    LibFuture.expire(data);
  }

  // throw unexpected txs
  function() {
    throw;
  }

}
