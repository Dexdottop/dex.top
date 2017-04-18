pragma solidity ^0.4.4;

contract IFuture {
  function shortBuy(address from) public payable returns (bool) {}
  function longBuy(address from) public payable returns (bool) {}
}

contract IMarket {
  function emitBrokerResult(address, bool, address[], bool[]) {}
}

contract Broker {

  address owner;
  address public market;

  function Broker() {
    owner = msg.sender;
  }

  function () payable {}

  function setMarket(address _market) {
    if (msg.sender != owner) throw;
    market = _market;
  }

  function batchShort(address[] futures, uint[] values) public payable {
    batchBuy(true,  futures, values);
  }

  function batchLong(address[] futures, uint[] values) public payable {
    batchBuy(false, futures, values);
  }

  function batchBuy(bool isShort, address[] futures, uint[] values)
    internal
  {
    uint refund = 0;
    bool[] memory res = new bool[](futures.length);
    for (uint i = 0; i < futures.length; i++) {
      IFuture future = IFuture(futures[i]);
      if(isShort) {
        res[i] = future.shortBuy.value(values[i])(msg.sender);
      } else {
        res[i] = future.longBuy.value(values[i])(msg.sender);
      }
      if(!res[i]) refund+=values[i];
    }
    if(refund>0) {
      if(!msg.sender.send(refund)) throw;
    }
    IMarket(market).emitBrokerResult(msg.sender, isShort, futures, res);    
  }
}
