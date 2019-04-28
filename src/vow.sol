/// vow.sol -- Dai settlement module

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

contract Fusspot {
    function startAuction(address gal, uint lot, uint bid) public returns (uint);
    function dai() public returns (address);
}

contract Hopeful {
    function hope(address) public;
    function nope(address) public;
}

contract VatLike {
    function dai (address) public view returns (uint);
    function sin (address) public view returns (uint);
    function settleDebtUsingSurplus(address,address,int) public;
}

contract Vow is DSNote {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) public note auth { wards[usr] = 1; }
    function deny(address usr) public note auth { wards[usr] = 0; }
    modifier auth { require(wards[msg.sender] == 1); _; }


    // --- Data ---
    address public vat;
    address public cow;  // surplus auctioner
    address public row;  // debt auctioner

    mapping (uint48 => uint256) public sin; // debt queue
    uint256 public TotalDebtInQueue;   // queued debt          [rad]
    uint256 public TotalOnAuctionDebt;   // on-auction debt      [rad]

    uint256 public debtQueueLength;  // debt auction delay           [rad]
    uint256 public debtAuctionLotSize;  // debt auction (MKR-for-DAI) fixed lot size  [rad]
    uint256 public surplusAuctionLotSize;  // surplus auction (DAI-for-MKR) fixed lot size  [rad]
    uint256 public surplusAuctionBuffer;  // surplus buffer       [rad]

    // --- Init ---
    constructor() public { wards[msg.sender] = 1; }

    // --- Math ---
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Administration ---
    function file(bytes32 what, uint data) public note auth {
        if (what == "debtQueueLength") debtQueueLength = data;
        if (what == "surplusAuctionLotSize") surplusAuctionLotSize = data;
        if (what == "debtAuctionLotSize") debtAuctionLotSize = data;
        if (what == "surplusAuctionBuffer") surplusAuctionBuffer = data;
    }
    function file(bytes32 what, address addr) public note auth {
        if (what == "daiForMkrSurplusAuction") cow = addr;
        if (what == "mkrForDaiDebtAuction") row = addr;
        if (what == "vat")  vat = addr;
    }

    // Total deficit
    function TotalDebt() public view returns (uint) {
        return uint(VatLike(vat).sin(address(this)));
    }
    // Total surplus
    function TotalSurplus() public view returns (uint) {
        return uint(VatLike(vat).dai(address(this)));
    }
    // Unqueued, pre-auction debt
    function TotalNonQueuedNonAuctionDebt() public view returns (uint) {
        return sub(sub(TotalDebt(), TotalDebtInQueue), TotalOnAuctionDebt);
    }

    // Push to debt-queue
    function addDebtToDebtQueue(uint tab) public note auth {
        sin[uint48(now)] = add(sin[uint48(now)], tab);
        TotalDebtInQueue = add(TotalDebtInQueue, tab);
    }
    // Pop from debt-queue
    function removeDebtFromDebtQueue(uint48 era) public note {
        require(add(era, debtQueueLength) <= now);
        TotalDebtInQueue = sub(TotalDebtInQueue, sin[era]);
        sin[era] = 0;
    }

    // Debt settlement
    function settleDebtUsingSurplus(uint rad) public note {
        require(rad <= TotalSurplus() && rad <= TotalNonQueuedNonAuctionDebt());
        require(int(rad) >= 0);
        VatLike(vat).settleDebtUsingSurplus(address(this), address(this), int(rad));
    }
    function settleOnAuctionDebtUsingSurplus(uint rad) public note {
        require(rad <= TotalOnAuctionDebt && rad <= TotalSurplus());
        TotalOnAuctionDebt = sub(TotalOnAuctionDebt, rad);
        require(int(rad) >= 0);
        VatLike(vat).settleDebtUsingSurplus(address(this), address(this), int(rad));
    }

    // Debt auction
    function auctionMkrForDai() public returns (uint id) {
        require(TotalNonQueuedNonAuctionDebt() >= debtAuctionLotSize);
        require(TotalSurplus() == 0);
        TotalOnAuctionDebt = add(TotalOnAuctionDebt, debtAuctionLotSize);
        return Fusspot(row).startAuction(address(this), uint(-1), debtAuctionLotSize);
    }
    // Surplus auction
    function auctionDaiForMkr() public returns (uint id) {
        require(TotalSurplus() >= add(add(TotalDebt(), surplusAuctionLotSize), surplusAuctionBuffer));
        require(TotalNonQueuedNonAuctionDebt() == 0);
        Hopeful(Fusspot(cow).dai()).hope(cow);
        id = Fusspot(cow).startAuction(address(0), surplusAuctionLotSize, 0);
        Hopeful(Fusspot(cow).dai()).nope(cow);
    }
}
