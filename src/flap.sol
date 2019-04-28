/// flap.sol -- Surplus auction

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
contract GemLike {
    function move(address,address,uint) public;
}

/*
   This thing lets you sell some dai in return for gems.

 - `lot` dai for sale
 - `bid` gems paid
 - `incomeRecipient` receives gem income
 - `ttl` single bid lifetime
 - `minimumBidIncrease` minimum bid increase
 - `auctionEndTimestamp` max auction duration
*/

contract DaiForMkrSurplusAuction is DSNote {
    // --- Data ---
    struct Bid {
        uint256 bid;
        uint256 lot;
        address highBidder;  // high bidder
        uint48  tic;  // expiry time
        uint48  auctionEndTimestamp;
        address incomeRecipient;
    }

    mapping (uint => Bid) public bids;

    DaiLike  public   dai;
    GemLike  public   gem;

    uint256  constant ONE = 1.00E27;
    uint256  public   minimumBidIncrease = 1.05E27;  // 5% minimum bid increase
    uint48   public   ttl = 3 hours;  // 3 hours bid duration
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
    constructor(address dai_, address gem_) public {
        dai = DaiLike(dai_);
        gem = GemLike(gem_);
    }

    // --- Math ---
    function add(uint48 x, uint48 y) internal pure returns (uint48 z) {
        require((z = x + y) >= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Auction ---
    function startAuction(address incomeRecipient, uint lot, uint bid)
        public returns (uint id)
    {
        require(startAuctions < uint(-1));
        id = ++startAuctions;

        bids[id].bid = bid;
        bids[id].lot = lot;
        bids[id].highBidder = msg.sender; // configurable??
        bids[id].auctionEndTimestamp = add(uint48(now), maximumAuctionDuration);
        bids[id].incomeRecipient = incomeRecipient;

        dai.move(msg.sender, address(this), lot);

        emit StartAuction(id, lot, bid, incomeRecipient);
    }
    function makeBidIncreaseBidSize(uint id, uint lot, uint bid) public note {
        require(bids[id].highBidder != address(0));
        require(bids[id].tic > now || bids[id].tic == 0);
        require(bids[id].auctionEndTimestamp > now);

        require(lot == bids[id].lot);
        require(bid >  bids[id].bid);
        require(mul(bid, ONE) >= mul(minimumBidIncrease, bids[id].bid));

        gem.move(msg.sender, bids[id].highBidder, bids[id].bid);
        gem.move(msg.sender, bids[id].incomeRecipient, bid - bids[id].bid);

        bids[id].highBidder = msg.sender;
        bids[id].bid = bid;
        bids[id].tic = add(uint48(now), ttl);
    }
    function claimWinningBid(uint id) public note {
        require(bids[id].tic < now && bids[id].tic != 0 ||
                bids[id].auctionEndTimestamp < now);
        dai.move(address(this), bids[id].highBidder, bids[id].lot);
        delete bids[id];
    }
}
