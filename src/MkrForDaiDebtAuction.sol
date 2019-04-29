/// MkrForDaiDebtAuction.sol -- stablecoinSupply auction

// Copyright (C) 2018 Rain <rainbreak@riseup.net>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity >=0.5.0;

import "./lib.sol";

contract DaiLike {
    function move(address,address,uint) public;
}
contract mkrTokensLike {
    function mint(address,uint) public;
}

/*
   This thing creates maker on demand in return for dai.

 - `lot` mkrTokens for sale
 - `bid` dai paid
 - `incomeRecipient` receives dai income
 - `ttl` single bid lifetime
 - `beg` minimum bid increase
 - `auctionEndTimestamp` max auction duration
*/

contract MkrForDaiDebtAuction is DSNote {
    // --- isAuthorized ---
    mapping (address => uint) public authenticatedAddresss;
    function authorizeAddress(address usr) public note isAuthorized { authenticatedAddresss[usr] = 1; }
    function deauthorizeAddress(address usr) public note isAuthorized { authenticatedAddresss[usr] = 0; }
    modifier isAuthorized { require(authenticatedAddresss[msg.sender] == 1); _; }

    // --- Data ---
    struct Bid {
        uint256 bid;
        uint256 lot;
        address highBidder;  // high bidder
        uint48  expiryTime;  // expiry time
        uint48  auctionEndTimestamp;
        address Settlement;
    }

    mapping (uint => Bid) public bids;

    DaiLike  public   dai;
    mkrTokensLike  public   mkrTokens;

    uint256  constant ONE = 1.00E27;
    uint256  public   beg = 1.05E27;  // 5% minimum bid increase
    uint48   public   ttl = 3 hours;  // 3 hours bid lifetime
    uint48   public   maximumAuctionDuration = 2 days;   // 2 days total auction length
    uint256  public startAuctions = 0;

    // --- Events ---
    event StartAuction(
      uint256 id,
      uint256 lot,
      uint256 bid,
      address indexed incomeRecipient
    );

    // --- Init ---
    constructor(address dai_, address mkrTokens_) public {
        authenticatedAddresss[msg.sender] = 1;
        dai = DaiLike(dai_);
        mkrTokens = mkrTokensLike(mkrTokens_);
    }

    // --- Math ---
    function add(uint48 x, uint48 y) internal pure returns (uint48 z) {
        require((z = x + y) >= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Auction ---
    function startAuction(address incomeRecipient, uint lot, uint bid) public isAuthorized returns (uint id) {
        require(startAuctions < uint(-1));
        id = ++startAuctions;

        bids[id].Settlement = msg.sender;
        bids[id].bid = bid;
        bids[id].lot = lot;
        bids[id].highBidder = incomeRecipient;
        bids[id].auctionEndTimestamp = add(uint48(now), maximumAuctionDuration);

        emit StartAuction(id, lot, bid, incomeRecipient);
    }
    
    // lot is basically how many mkr you'd take for the dai available, lowest amount = highest bidder
    function makeBidDecreaseLotSize(uint id, uint lot, uint bid) public note {
        require(bids[id].highBidder != address(0));
        require(bids[id].expiryTime > now || bids[id].expiryTime == 0);
        require(bids[id].auctionEndTimestamp > now);

        require(bid == bids[id].bid);
        require(lot < bids[id].lot);
        require(uint(mul(beg, lot)) / ONE <= bids[id].lot);  // div as lot can be huge

        dai.move(msg.sender, bids[id].highBidder, bid);

        bids[id].highBidder = msg.sender;
        bids[id].lot = lot;
        bids[id].expiryTime = add(uint48(now), ttl);
    }
    function claimWinningBid(uint id) public note {
        require(bids[id].expiryTime < now && bids[id].expiryTime != 0 ||
                bids[id].auctionEndTimestamp < now);
        mkrTokens.mint(bids[id].highBidder, bids[id].lot);
        delete bids[id];
    }
}
