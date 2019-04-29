/// Settlement.sol -- Dai settlement module

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

contract AuctionInterface {
    function startAuction(address gal, uint lot, uint bid) public returns (uint);
    function dai() public returns (address);
}

contract ApprovalInterface {
    function hope(address) public;
    function nope(address) public;
}

contract cdpDatabaseInterface {
    function dai (address) public view returns (uint);
    function badDebt (address) public view returns (uint);
    function settleDebtUsingSurplus(address,address,int) public;
}

contract Settlement is DSNote {
    // --- isAuthorized ---
    mapping (address => uint) public authenticatedAddresss;
    function authorizeAddress(address usr) public note isAuthorized { authenticatedAddresss[usr] = 1; }
    function deauthorizeAddress(address usr) public note isAuthorized { authenticatedAddresss[usr] = 0; }
    modifier isAuthorized { require(authenticatedAddresss[msg.sender] == 1); _; }


    // --- Data ---
    address public cdpDatabase;
    address public cow;  // surplus auctioner
    address public row;  // stablecoinSupply auctioner

    mapping (uint48 => uint256) public badDebtQueue; // stablecoinSupply queue
    uint256 public TotalDebtInQueue;   // queued stablecoinSupply          [fxp45Int]
    uint256 public TotalOnAuctionDebt;   // on-auction stablecoinSupply      [fxp45Int]

    uint256 public debtQueueLength;  // stablecoinSupply auction delay           [fxp45Int]
    uint256 public debtAuctionLotSize;  // stablecoinSupply auction (MKR-for-DAI) fixed lot size  [fxp45Int]
    uint256 public surplusAuctionLotSize;  // surplus auction (DAI-for-MKR) fixed lot size  [fxp45Int]
    uint256 public surplusAuctionBuffer;  // surplus buffer       [fxp45Int]

    // --- Init ---
    constructor() public { authenticatedAddresss[msg.sender] = 1; }

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
    function changeConfig(bytes32 what, uint data) public note isAuthorized {
        if (what == "debtQueueLength") debtQueueLength = data;
        if (what == "surplusAuctionLotSize") surplusAuctionLotSize = data;
        if (what == "debtAuctionLotSize") debtAuctionLotSize = data;
        if (what == "surplusAuctionBuffer") surplusAuctionBuffer = data;
    }
    function changeConfig(bytes32 what, address addr) public note isAuthorized {
        if (what == "daiForMkrSurplusAuction") cow = addr;
        if (what == "mkrForDaiDebtAuction") row = addr;
        if (what == "cdpDatabase")  cdpDatabase = addr;
    }

    // Total deficit
    function TotalDebt() public view returns (uint) {
        return uint(cdpDatabaseInterface(cdpDatabase).badDebt(address(this)));
    }
    // Total surplus
    function TotalSurplus() public view returns (uint) {
        return uint(cdpDatabaseInterface(cdpDatabase).dai(address(this)));
    }
    // Unqueued, pre-auction stablecoinSupply
    function TotalNonQueuedNonAuctionDebt() public view returns (uint) {
        return sub(sub(TotalDebt(), TotalDebtInQueue), TotalOnAuctionDebt);
    }

    // Push to stablecoinSupply-queue
    function addDebtToDebtQueue(uint debtPlusStabilityFee) public note isAuthorized {
        badDebtQueue[uint48(now)] = add(badDebtQueue[uint48(now)], debtPlusStabilityFee);
        TotalDebtInQueue = add(TotalDebtInQueue, debtPlusStabilityFee);
    }
    // Pop from stablecoinSupply-queue
    function removeDebtFromDebtQueue(uint48 era) public note {
        require(add(era, debtQueueLength) <= now);
        TotalDebtInQueue = sub(TotalDebtInQueue, badDebtQueue[era]);
        badDebtQueue[era] = 0;
    }

    // stablecoinSupply settlement
    function settleDebtUsingSurplus(uint fxp45Int) public note {
        require(fxp45Int <= TotalSurplus() && fxp45Int <= TotalNonQueuedNonAuctionDebt());
        require(int(fxp45Int) >= 0);
        cdpDatabaseInterface(cdpDatabase).settleDebtUsingSurplus(address(this), address(this), int(fxp45Int));
    }
    function settleOnAuctionDebtUsingSurplus(uint fxp45Int) public note {
        require(fxp45Int <= TotalOnAuctionDebt && fxp45Int <= TotalSurplus());
        TotalOnAuctionDebt = sub(TotalOnAuctionDebt, fxp45Int);
        require(int(fxp45Int) >= 0);
        cdpDatabaseInterface(cdpDatabase).settleDebtUsingSurplus(address(this), address(this), int(fxp45Int));
    
    // stablecoinSupply auction
    function auctionMkrForDai() public returns (uint id) {
        require(TotalNonQueuedNonAuctionDebt() >= debtAuctionLotSize);
        require(TotalSurplus() == 0);
        TotalOnAuctionDebt = add(TotalOnAuctionDebt, debtAuctionLotSize);
        return AuctionInterface(row).startAuction(address(this), uint(-1), debtAuctionLotSize);
    }
    // Surplus auction
    function auctionDaiForMkr() public returns (uint id) {
        require(TotalSurplus() >= add(add(TotalDebt(), surplusAuctionLotSize), surplusAuctionBuffer));
        require(TotalNonQueuedNonAuctionDebt() == 0);
        ApprovalInterface(AuctionInterface(cow).dai()).hope(cow);
        id = AuctionInterface(cow).startAuction(address(0), surplusAuctionLotSize, 0);
        ApprovalInterface(AuctionInterface(cow).dai()).nope(cow);
    }
}
