/// cat.sol -- Dai liquidation module

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
pragma experimental ABIEncoderV2;

import "./lib.sol";

contract CollateralForDaiAuctionpy {
    function startAuction(address cdp, address incomeRecipient, uint debtPlusStabilityFee, uint lot, uint bid)
        public returns (uint);
}

contract cdpDatabaseInterface {
    struct collateralType {
        uint256 totalStablecoinDebt;   // fxp18Int
        uint256 debtMultiplierIncludingStabilityFee;  // fxp27Int
        uint256 maxDaiPerUnitOfCollateral;  // fxp27Int
        uint256 debtCeiling;  // fxp45Int
    }
    struct cdp {
        uint256 collateralBalance;   // fxp18Int
        uint256 stablecoinDebt;   // fxp18Int
    }
    function collateralTypes(bytes32) public view returns (collateralType memory);
    function cdps(bytes32,address) public view returns (cdp memory);
    function liquidateCDP(bytes32,address,address,address,int,int) public;
    function hope(address) public;
}

contract VowLike {
    function addDebtToDebtQueue(uint) public;
}

contract Liquidation is DSNote {
    // --- isAuthorized ---
    mapping (address => uint) public authenticatedAddresss;
    function authorizeAddress(address usr) public note isAuthorized { authenticatedAddresss[usr] = 1; }
    function deauthorizeAddress(address usr) public note isAuthorized { authenticatedAddresss[usr] = 0; }
    modifier isAuthorized { require(authenticatedAddresss[msg.sender] == 1); _; }

    // --- Data ---
    struct collateralType {
        address collateralForDaiAuctionData;  // Liquidator
        uint256 liquidationPenalty;  // Liquidation Penalty   [fxp27Int]
        uint256 liquidationQuantity;  // Liquidation Quantity  [fxp45Int]
    }
    struct collateralForDaiAuctionData {
        bytes32 collateralType;  // Collateral Type
        address cdp;  // CDP Identifier
        uint256 collateralBalance;  // Collateral Quantity [fxp18Int]
        uint256 debtPlusStabilityFee;  // stablecoinSupply Outstanding    [fxp45Int]
    }

    mapping (bytes32 => collateralType)  public collateralTypes;
    mapping (uint256 => collateralForDaiAuctionData) public CollateralForDaiAuctions;
    uint256                   public nCollateralForDaiAuction;

    uint256 public live;
    cdpDatabaseInterface public cdpDatabase;
    VowLike public Settlement;

    // --- Events ---
    event LiquidateCdp(
      bytes32 indexed collateralType,
      address indexed cdp,
      uint256 collateralBalance,
      uint256 stablecoinDebt,
      uint256 debtPlusStabilityFee,
      uint256 collateralForDaiAuctionData
    );

    event CollateralForDaiAuctionStartAuction(
      uint256 nCollateralForDaiAuction,
      uint256 bid
    );

    // --- Init ---
    constructor(address vat_) public {
        authenticatedAddresss[msg.sender] = 1;
        cdpDatabase = cdpDatabaseInterface(vat_);
        live = 1;
    }

    // --- Math ---
    uint constant ONE = 10 ** 27;

    function mul(uint x, uint y) internal pure returns (uint z) {
        z = x * y;
        require(y == 0 || z / y == x);
    }
    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = x * y;
        require(y == 0 || z / y == x);
        z = z / ONE;
    }

    // --- Administration ---
    function changeConfig(bytes32 what, address data) public note isAuthorized {
        if (what == "Settlement") Settlement = VowLike(data);
    }
    function changeConfig(bytes32 collateralType, bytes32 what, uint data) public note isAuthorized {
        if (what == "liquidationPenalty") collateralTypes[collateralType].liquidationPenalty = data;
        if (what == "liquidationQuantity") collateralTypes[collateralType].liquidationQuantity = data;
    }
    function changeConfig(bytes32 collateralType, bytes32 what, address collateralForDaiAuction) public note isAuthorized {
        if (what == "collateralForDaiAuction") collateralTypes[collateralType].collateralForDaiAuction = collateralForDaiAuction; cdpDatabase.hope(collateralForDaiAuction);
    }

    // --- CDP Liquidation ---
    function liquidateCdp(bytes32 collateralType, address cdp) public returns (uint) {
        require(live == 1);
        cdpDatabaseInterface.collateralType memory i = cdpDatabase.collateralTypes(collateralType);
        cdpDatabaseInterface.cdp memory u = cdpDatabase.cdps(collateralType, cdp);

        uint debtPlusStabilityFee = mul(u.stablecoinDebt, i.debtMultiplierIncludingStabilityFee);

        require(mul(u.collateralBalance, i.maxDaiPerUnitOfCollateral) < debtPlusStabilityFee);  // !isCdpSafe

        cdpDatabase.liquidateCDP(collateralType, cdp, address(this), address(Settlement), -int(u.collateralBalance), -int(u.stablecoinDebt));
        Settlement.addDebtToDebtQueue(debtPlusStabilityFee);

        CollateralForDaiAuctions[nCollateralForDaiAuction] = collateralForDaiAuctionData(collateralType, cdp, u.collateralBalance, debtPlusStabilityFee);

        emit LiquidateCdp(collateralType, cdp, u.collateralBalance, u.stablecoinDebt, debtPlusStabilityFee, nCollateralForDaiAuction);

        return nCollateralForDaiAuction++;
    }

    function collateralForDaiAuction(uint n, uint fxp45Int) public note returns (uint id) {
        require(live == 1);
        collateralForDaiAuction storage f = CollateralForDaiAuctions[n];
        collateralType  storage i = collateralTypes[f.collateralType];

        require(fxp45Int <= f.debtPlusStabilityFee);
        require(fxp45Int == i.liquidationQuantity || (fxp45Int < i.liquidationQuantity && fxp45Int == f.debtPlusStabilityFee));

        uint debtPlusStabilityFee = f.debtPlusStabilityFee;
        uint collateralBalance = mul(f.collateralBalance, fxp45Int) / debtPlusStabilityFee;

        f.debtPlusStabilityFee -= fxp45Int;
        f.collateralBalance -= collateralBalance;

        id = CollateralForDaiAuction(i.collateralForDaiAuction).startAuction({ cdp: f.cdp
                                         , incomeRecipient: address(Settlement)
                                         , debtPlusStabilityFee: rmul(fxp45Int, i.liquidationPenalty)
                                         , lot: collateralBalance
                                         , bid: 0
                                         });
        emit CollateralForDaiAuctionStartAuction(n, id);
    }
}
