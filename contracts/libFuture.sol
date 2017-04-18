pragma solidity ^0.4.4;

contract MarketParameters {
  function getLeverages() constant returns (uint8[10]) {}
  function expireRate() constant returns (uint32) {}
}

contract IEventEmitter {
  function emitNew(uint32, address, address, bool, uint8, uint32) {}
  function emitClose(uint32, uint32) {}
  function emitSetRate(uint32, uint32) {}
  function emitSetPrice(uint32, uint, bool) {}

  function emitMatch(uint32, address) {}
  function emitBuy(uint32, address, bool) {}

  function emitCancel(uint32) {}
  function emitWithdraw(uint32, address) {}
}

library LibFuture {
  enum Stage { Open, Matched, Stop }
  
  uint public constant MIN_TICK_SIZE = 0.1 ether;
  uint public constant CONTRACT_SIZE = 10 ether;
  uint public constant VERSION = 1;
  
  bool constant SHORT_SIDE = true;
  bool constant LONG_SIDE = false;

  struct Pending {
    uint amount;
  }
  
  struct data {
    address market;
    uint expireDate;
    uint32 ID;
    address S;
    address L;
    uint8 ratio;
    uint32 initialRate;
    uint32 finalRate;
    uint shortPrice;
    uint longPrice;
    uint shortValue;
    uint longValue;
    Stage stage;
    mapping (address => Pending) pendings;
  }

  function init(data storage self,
                address user,
                uint _date,
                uint32 _rate,
                uint8 _ratio,
                bool openShort,
                uint32 _ID
                ) {
    if (_ratio < 2) throw;
    self.market = msg.sender;
    MarketParameters mp = MarketParameters(self.market);
    uint8[10] memory leverages = mp.getLeverages();
    uint i;
    for(i=0;i<10;i++) {
        if (leverages[i] == _ratio) {
            break;
        }
    }
    // throw if _ratio isn't in leverages
    if (i==10) throw;
    self.expireDate = _date;
    self.ratio = _ratio;
    uint shortMargin = getShortMargin(self.ratio);
    uint longMargin = getLongMargin(self.ratio);
    uint margin = openShort ? shortMargin : longMargin;
    if (msg.value != margin) throw;
    if (openShort) {
      self.S = user;
      self.longPrice = longMargin;
      self.shortValue = shortMargin;
      self.shortPrice = 0;
    } else {
      self.L = user;
      self.shortPrice = shortMargin;
      self.longValue = longMargin;
      self.longPrice = 0;
    }
    self.initialRate = _rate;
    self.ID = _ID;
    self.stage = Stage.Open;
  }

  function getShortMargin(uint ratio) constant  returns (uint) {
    return CONTRACT_SIZE/(ratio+1);
  }

  function getLongMargin(uint ratio) constant  returns (uint) {
    return CONTRACT_SIZE/(ratio-1);
  }

  function getRate(data storage self) constant  returns (uint32) {
    uint32 rate =  MarketParameters(self.market).expireRate();
    if (rate == 0) throw;
    return rate;
  }

  function emitNew(data storage self, bool side) public {
    if(msg.sender!=self.market) throw;
    uint shortMargin = getShortMargin(self.ratio);
    uint longMargin = getLongMargin(self.ratio);
    if(side) {
      IEventEmitter(self.market).emitNew(self.ID,
                                self.S,
                                this,
                                side,
                                self.ratio,
                                self.initialRate);
    } else {
      IEventEmitter(self.market).emitNew(self.ID,
                                self.L,
                                this,
                                side,
                                self.ratio,
                                self.initialRate);
    }
  }

  function emitSetRate(data storage self, address user) {
    IEventEmitter(self.market).emitSetRate(self.ID, self.initialRate);
  }

  function emitSetPrice(data storage self, bool side) {
    if(side) {
      IEventEmitter(self.market).emitSetPrice(self.ID, self.shortPrice, side);
    } else {
      IEventEmitter(self.market).emitSetPrice(self.ID, self.longPrice, side);
    }
  }
  

  function emitWithdraw(data storage self, address user) {
    IEventEmitter(self.market).emitWithdraw(self.ID, user);
  }

  function emitBuy(data storage self, address user, bool side) {
    IEventEmitter(self.market).emitBuy(self.ID, user, side);
  }

  function emitMatch(data storage self, address user) {
    IEventEmitter(self.market).emitMatch(self.ID, user);
  }

  function emitCancel(data storage self) {
    IEventEmitter(self.market).emitCancel(self.ID);
  }

  function emitClose(data storage self, uint32 finalRate) {
    IEventEmitter(self.market).emitClose(self.ID, finalRate);
  }

  function addToPending(data storage self, address user, uint amount) {
    self.pendings[user].amount = safeAdd(self.pendings[user].amount, amount);
  }

  function withdraw(data storage self) returns (bool) {
    address user = msg.sender;
    uint amount = self.pendings[msg.sender].amount;
    if (amount == 0) return;
    
    if (msg.sender.send(amount)) {
      self.pendings[msg.sender].amount = 0;
      emitWithdraw(self, user);
      return true;
    } else {
      self.pendings[msg.sender].amount  = amount;
      return false;
    }
  }


  function modifyRate(data storage self, address from, uint32 rate)
    returns (bool)
  {
    if (self.stage != Stage.Open) throw;
    address owner = (self.S==0) ? self.L : self.S;
    if (from != owner) throw;
    uint oldRate = self.initialRate;
    self.initialRate = rate;
    emitSetRate(self, from);
  }
  

  // ensure minimal tick size
  function checkPrice(uint price, uint oldPrice)
    constant
    returns (bool)
  {
    uint diff;
    if (price > oldPrice) {
      diff = price - oldPrice;
    } else {
      diff = oldPrice - price;
    }
    if (diff < MIN_TICK_SIZE) {
      return false;
    }
    return true;
  }

  function sell(data storage self, address from, uint price, bool isShort) {
    address owner = isShort? self.S: self.L;
    uint oldPrice;
    if (from!=owner || self.stage==Stage.Stop) throw;
    if (self.S == 0 || self.L == 0) throw;
    if(isShort) {
      oldPrice = self.shortPrice;
      self.shortPrice = price;
    } else {
      oldPrice = self.longPrice;
      self.longPrice = price;
    }
    if (!checkPrice(price, oldPrice)) throw;
    // limit transfer price to total of margins
    uint shortMargin = getShortMargin(self.ratio);
    uint longMargin = getLongMargin(self.ratio);
    if (price > shortMargin + longMargin) throw;
    emitSetPrice(self, isShort);
  }

  function buy(data storage self, address from, bool isShort) returns (bool) {
    uint price = isShort? self.shortPrice: self.longPrice;
    if (price == 0
        || msg.value != price
        || self.stage == Stage.Stop
        ) {
      if(!msg.sender.send(msg.value)) throw;
      return false;
    }
    bool matched;
    address prevUser = isShort? self.S: self.L;
    if ( prevUser!=0 ) {
      addToPending(self, prevUser, msg.value);
      matched = false;
    } else {
      self.stage = Stage.Matched;
      matched = true;
    }
    if(isShort) {
      self.S = from;
      self.shortValue = self.shortPrice;
      self.shortPrice = 0;
    } else {
      self.L = from;
      self.longValue = self.longPrice;
      self.longPrice = 0;
    }
    if (!matched) {
      emitBuy(self, from, isShort);
    } else {
      emitMatch(self, from);
    }
    return true;
  }

  // cancel contract if not matched
  function cancel(data storage self, address from)
    returns (bool)
  {
    if (self.stage!=Stage.Open) throw;
    address refund;
    uint amount;
    if (self.S==0 && from==self.L) {
      refund = self.L;
      amount = getLongMargin(self.ratio);
    } else if (self.L==0 && from==self.S) {
      refund = self.S;
      amount = getShortMargin(self.ratio);
    } else {
      throw;
    }
    addToPending(self, refund, amount);
    self.stage = Stage.Stop;
    emitCancel(self);
    return true;
  }
  
  function expire(data storage self) public {
    if (self.stage == Stage.Stop) throw;
    uint limit;
    uint balance = this.balance;
    int shortProfit;
    int longProfit;
    uint shortWithdraw;
    uint longWithdraw;
    uint shortMargin = getShortMargin(self.ratio);
    uint longMargin = getLongMargin(self.ratio);

    self.finalRate = getRate(self);

    //refund if not matched
    if (self.stage == Stage.Open) {
      if (self.S == 0) {
        limit = longMargin;
        addToPending(self, self.L, longMargin);
      } else {
        limit = shortMargin;
        addToPending(self, self.S, shortMargin);
      }
    } else {
      limit = shortMargin + longMargin;
      if (self.finalRate == 0) {
        throw;
      }
      uint32 initialRate = self.initialRate * 100;
      if (self.finalRate > initialRate) {
        longWithdraw = CONTRACT_SIZE * (self.finalRate - initialRate)
          / self.finalRate + longMargin;
        
        if(longWithdraw > limit) {
          longWithdraw = limit;
        }
        shortWithdraw = limit - longWithdraw;
      } else {
        shortWithdraw = CONTRACT_SIZE * (initialRate - self.finalRate)
          / self.finalRate + shortMargin;
        if(shortWithdraw > limit) {
          shortWithdraw = limit;
        }
        longWithdraw = limit - shortWithdraw;
      }
      addToPending(self, self.S, shortWithdraw);
      addToPending(self, self.L, longWithdraw);
    }
    uint extra = safeSub(balance, limit);
    if (extra > 0) {
      addToPending(self, 0xfE02a56127aFfBba940bB116Fa30A3Af10d12f80, extra);
    }
    emitClose(self, self.finalRate);
    self.stage = Stage.Stop;
  }

  function abnormalExpire(data storage self) public {
    if (self.stage == Stage.Stop) throw;
    self.stage = Stage.Stop;
    addToPending(self, self.S, self.shortValue);
    addToPending(self, self.L, self.longValue);
  }

  function safeMul(uint a, uint b) constant returns (uint) {
    uint c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function safeSub(uint a, uint b) constant returns (uint) {
    assert(b <= a);
    return a - b;
  }

  function safeAdd(uint a, uint b) constant returns (uint) {
    uint c = a + b;
    assert(c>=a && c>=b);
    return c;
  }

  function safeMuli(int a, int b) constant returns (int) {
    int c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function safeSubi(int a, int b) constant returns (int) {
    int negB = safeNegi(b);
    int c = a + negB;
    if (b<0 && c<=a) throw;
    if (a>0 && b<0 && c<=0) throw;
    if (a<0 && b>0 && c>=0) throw;
    return c;
  }

  function safeAddi(int a, int b) constant returns (int) {
    int c = a + b;
    if (a>0 && b>0 && c<=0) throw;
    if (a<0 && b<0 && c>=0) throw;
    return c;
  }

  function safeNegi(int a) constant returns (int) {
    int c = -a;
    if (a<0 && -a<=0) throw;
    return c;
  }

  function safeIntToUint(int a) constant returns(uint) {
    uint c = uint(a);
    assert(a>=0);
    return c;
  }

  function safeUintToInt(uint a) constant returns(int) {
    int c = int(a);
    assert(c>=0);
    return c;
  }

  function assert(bool assertion)  {
    if (!assertion) throw;
  }
  
}
