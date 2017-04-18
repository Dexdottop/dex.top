pragma solidity ^0.4.4;
import "future.sol";

contract IBroker {
  function batchShort(address, address[],uint[]) payable {}
  function batchLong(address, address[],uint[]) payable {}
}

contract Market {
    uint public constant VERSION = 1;

    address private owner;
    bool public stopped = false;

    modifier isAdmin() {
        if(msg.sender != owner) {
            throw;
        }
        _;
    }

    modifier fromActiveFuture() {
        if(!activeFutures[msg.sender]) throw;
        _;
    }

    modifier fromFuture() {
        if(futureIDs[msg.sender] == 0) throw;
        _;
    }

    modifier stopInEmergency {
        if (stopped) {
	  throw;
        }
        _;
    }

    modifier onlyInEmergency {
        if (!stopped) {
	   throw;
        }
        _;
    }

    function toggleAlive() isAdmin public { stopped = !stopped; }

    mapping(uint => address) futures;
    mapping(address => bool) activeFutures;
    mapping(address => uint) futureIDs;
    uint32 public numFutures = 0;

    // up to 10 leverage levels
    uint8[10] public leverages = [5, 10];
    
    function getLeverages() constant returns (uint8[10]) {
      return leverages;
    }
    
    // _leverages must be sorted
    function setLeverages(uint8[] _leverages) isAdmin public {
        if(_leverages.length>10) throw;
        uint i;
        // leverage should be larger than 2
        uint prev = 2;
        for (i=0; i<_leverages.length; i++) {
            if (_leverages[i] <= prev) throw;
            leverages[i] = _leverages[i];
            prev = _leverages[i];
        }
        for (i=_leverages.length; i<10; i++) {
            leverages[i] = 0;
        }
    }

    address public broker;

    event SetBroker(address broker);

    function setBroker(address _broker) isAdmin public {
      broker = _broker;
      SetBroker(_broker);
    }

    uint public expireDate;

    function setExpireDate(uint date) isAdmin onlyInEmergency public {
      expireDate = date;
    }

    uint32 public expireRate;

    function setExpireRate(uint32 rate) isAdmin public {
      expireRate = rate;
    }

    event MarketDeployed(address creator, uint expireDate, bytes8 kind);

    event New(
        uint32 id,
        address user,
        address futureAddr,
        bool side,
        uint8 leverage,
        uint32 rate);

    event Close(uint32 id, uint32 finalRate);

    event SetRate(uint32 id, uint32 newRate);
    
    event SetPrice(
        uint32 id,
        uint newPrice,
        bool side);
    
    event Buy(
        uint32 id,
        address user,
        bool side);
    
    event Match(uint32 id, address user);

    event Cancel(uint32 id);

    event Withdraw(uint32 id, address user);

    event BrokerResult(address  user, bool isShort,
                       address[] contracts, bool[] res);
    

    function emitNew(
        uint32 id,
        address user,
        address addr,
        bool side,
        uint8 leverage,
        uint32 rate
    )
      public
      fromActiveFuture
    {
      New(id, user, addr, side, leverage, rate);
    }

    function emitClose(uint32 id, uint32 finalRate)
      public
      fromActiveFuture
    {
      Close(id, finalRate);
    }


    function emitSetRate(uint32 id, uint32 newRate
    )
      public
      fromActiveFuture
    {
      SetRate(id, newRate);
    }

    function emitSetPrice(uint32 id, uint newPrice, bool side
    )
      public
      fromActiveFuture
    {
      SetPrice(id, newPrice, side);
    }


    function emitBuy(uint32 id, address user, bool side
    )
      public
      fromActiveFuture
    {
      Buy(id, user, side);
    }

    function emitMatch(uint32 id, address user
    )
      public
      fromActiveFuture
    {
      Match(id, user);
    }


    function emitCancel(uint32 id) public fromActiveFuture {
      Cancel(id);
    }

    function emitWithdraw(uint32 id, address user)
      public
      fromFuture
    {
      Withdraw(id, user);
    }

    function emitBrokerResult(
        address user,
        bool isShort,
        address[] futures,
        bool[] results
    )
      public
    {
      if (msg.sender != broker) throw;
      BrokerResult(user, isShort, futures, results);
    }


    function Market(uint _expireDate, bytes8 _kind) {
      owner = msg.sender;
      expireDate = _expireDate;
      MarketDeployed(owner, expireDate, _kind);
    }

    function newFuture(uint32 rate, uint8 ratio, bool isShort)
      public
      stopInEmergency
      payable
    {
        if (ratio < 2) throw;
        if (now >= expireDate) throw;
        address future;
        future = (new Future).value(msg.value)(
                  msg.sender,
                  expireDate,
                  rate,
                  ratio,
                  isShort,
                  numFutures+1);
        if (future != 0) {
            addFuture(future);
            Future newFuture = Future(future);
            newFuture.emitNew(isShort);
        } else {
            throw;
        }
    }

    function cancelFuture(address addr) public stopInEmergency {
      Future(addr).cancel(msg.sender);
      activeFutures[addr] = false;
    }

    function expireFuture(address addr) public stopInEmergency {
      if (now < expireDate) throw;
      Future(addr).expire();
      activeFutures[addr] = false;
    }

    function getFuture(uint id)
      constant
      returns (address,bool)
    {
      return (futures[id], activeFutures[futures[id]]);
    }

    function addFuture(address addr) private {
      numFutures++;
      futures[numFutures] = addr;
      activeFutures[addr] = true;
      futureIDs[addr] = numFutures;
    }

    // withdraw from market if unexpected ether locked in
    function emergencyWithdraw() public onlyInEmergency isAdmin {
        msg.sender.transfer(this.balance);
    }

    function() {
      throw;
    }
}

