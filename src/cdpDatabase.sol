/// cdpDatabase.sol -- Dai CDP database

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

contract cdpDatabase {
    // --- isAuthorized ---
    mapping (address => uint) public authenticatedAddresss;
    function authorizeAddress(address usr) public note isAuthorized { authenticatedAddresss[usr] = 1; }
    function deauthorizeAddress(address usr) public note isAuthorized { authenticatedAddresss[usr] = 0; }
    modifier isAuthorized { require(authenticatedAddresss[msg.sender] == 1); _; }

    mapping(address => mapping (address => uint)) public can;
    function hope(address usr) public { can[msg.sender][usr] = 1; }
    function nope(address usr) public { can[msg.sender][usr] = 0; }
    function wish(address bit, address usr) internal view returns (bool) {
        return bit == usr || can[bit][usr] == 1;
    }

    // --- Data ---
    struct collateralType {
        uint256 totalStablecoinDebt;   // Total Normalised stablecoinSupply     [fxp18Int]
        uint256 debtMultiplierIncludingStabilityFee;  // Accumulated debtMultiplierIncludingStabilityFee         [fxp27Int]
        uint256 maxDaiPerUnitOfCollateral;  // Price with Safety Margin  [fxp27Int]
        uint256 debtCeiling;  // stablecoinSupply Ceiling              [fxp45Int]
        uint256 dust;  // cdp stablecoinSupply Floor            [fxp45Int]
    }
    struct cdp {
        uint256 collateralBalance;   // Locked Collateral  [fxp18Int]
        uint256 stablecoinDebt;   // Normalised stablecoinSupply    [fxp18Int]
    }

    mapping (bytes32 => collateralType)                       public collateralTypes;
    mapping (bytes32 => mapping (address => cdp )) public cdps;
    mapping (bytes32 => mapping (address => uint)) public collateralTokens;  // [fxp18Int]
    mapping (address => uint256)                   public dai;  // [fxp45Int]
    mapping (address => uint256)                   public badDebt;  // [fxp45Int]

    uint256 public stablecoinSupply;  // Total Dai Issued    [fxp45Int]
    uint256 public badDebtSupply;  // Total Unbacked Dai  [fxp45Int]
    uint256 public totalDebtCeiling;  // Total stablecoinSupply Ceiling  [fxp18Int]
    uint256 public live;  // Access Flag

    // --- Logs ---
    modifier note {
        _;
        assembly {
            // log an 'anonymous' event with a constant 6 words of calldata
            // and four indexed topics: the selector and the first three args
            let mark := msize                      // end of memory ensures zero
            mstore(0x40, add(mark, 288))           // update transferCollateralFromCDP memory pointer
            mstore(mark, 0x20)                     // bytes type data offset
            mstore(add(mark, 0x20), 224)           // bytes size (padded)
            calldatacopy(add(mark, 0x40), 0, 224)  // bytes payload
            log4(mark, 288,                        // calldata
                 shr(224, calldataload(0)),        // msg.sig
                 calldataload(4),                  // arg1
                 calldataload(36),                 // arg2
                 calldataload(68)                  // arg3
                )
        }
    }

    // --- Init ---
    constructor() public {
        authenticatedAddresss[msg.sender] = 1;
        live = 1;
    }

    // --- Math ---
    function add(uint x, int y) internal pure returns (uint z) {
        z = x + uint(y);
        require(y >= 0 || z <= x);
        require(y <= 0 || z >= x);
    }
    function sub(uint x, int y) internal pure returns (uint z) {
        z = x - uint(y);
        require(y <= 0 || z <= x);
        require(y >= 0 || z >= x);
    }
    function mul(uint x, int y) internal pure returns (int z) {
        z = int(x) * y;
        require(int(x) >= 0);
        require(y == 0 || z / y == int(x));
    }
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
    function createNewCollateralType(bytes32 collateralType) public note isAuthorized {
        require(collateralTypes[collateralType].debtMultiplierIncludingStabilityFee == 0);
        collateralTypes[collateralType].debtMultiplierIncludingStabilityFee = 10 ** 27;
    }
    function changeConfig(bytes32 what, uint data) public note isAuthorized {
        if (what == "totalDebtCeiling") totalDebtCeiling = data;
    }
    function changeConfig(bytes32 collateralType, bytes32 what, uint data) public note isAuthorized {
        if (what == "maxDaiPerUnitOfCollateral") collateralTypes[collateralType].maxDaiPerUnitOfCollateral = data;
        if (what == "debtCeiling") collateralTypes[collateralType].debtCeiling = data;
        if (what == "dust") collateralTypes[collateralType].dust = data;
    }

    // --- Fungibility ---
    function modifyUsersCollateralBalance(bytes32 collateralType, address usr, int256 fxp18Int) public note isAuthorized {
        collateralTokens[collateralType][usr] = add(collateralTokens[collateralType][usr], fxp18Int);
    }
    function transferCollateral(bytes32 collateralType, address src, address dst, uint256 fxp18Int) public note {
        require(wish(src, msg.sender));
        collateralTokens[collateralType][src] = sub(collateralTokens[collateralType][src], fxp18Int);
        collateralTokens[collateralType][dst] = add(collateralTokens[collateralType][dst], fxp18Int);
    }
    function move(address src, address dst, uint256 fxp45Int) public note {
        require(wish(src, msg.sender));
        dai[src] = sub(dai[src], fxp45Int);
        dai[dst] = add(dai[dst], fxp45Int);
    }

    // --- CDP Manipulation ---
    function modifyCDP(bytes32 i, address u, address v, address w, int changeInCollateral, int changeInDebt) public note {
        cdp storage cdp = cdps[i][u];
        collateralType storage collateralType = collateralTypes[i];

        cdp.collateralBalance = add(cdp.collateralBalance, changeInCollateral);
        cdp.stablecoinDebt = add(cdp.stablecoinDebt, changeInDebt);
        collateralType.totalStablecoinDebt = add(collateralType.totalStablecoinDebt, changeInDebt);

        collateralTokens[i][v] = sub(collateralTokens[i][v], changeInCollateral);
        dai[w]    = add(dai[w], mul(collateralType.debtMultiplierIncludingStabilityFee, changeInDebt));
        stablecoinSupply      = add(stablecoinSupply,   mul(collateralType.debtMultiplierIncludingStabilityFee, changeInDebt));

        bool isCdpDaiDebtNonIncreasing = changeInDebt <= 0;
        bool isCdpCollateralBalanceNonDecreasing = changeInCollateral >= 0;
        bool nice = isCdpDaiDebtNonIncreasing && isCdpCollateralBalanceNonDecreasing;
        bool isCdpBelowCollateralAndTotalDebtCeilings = mul(collateralType.totalStablecoinDebt, collateralType.debtMultiplierIncludingStabilityFee) <= collateralType.debtCeiling && stablecoinSupply <= totalDebtCeiling;
        bool isCdpSafe = mul(cdp.stablecoinDebt, collateralType.debtMultiplierIncludingStabilityFee) <= mul(cdp.collateralBalance, collateralType.maxDaiPerUnitOfCollateral);

        require((isCdpBelowCollateralAndTotalDebtCeilings || isCdpDaiDebtNonIncreasing) && (nice || isCdpSafe));

        require(wish(u, msg.sender) ||  nice);
        require(wish(v, msg.sender) || !isCdpCollateralBalanceNonDecreasing);
        require(wish(w, msg.sender) || !isCdpDaiDebtNonIncreasing);

        require(mul(cdp.stablecoinDebt, collateralType.debtMultiplierIncludingStabilityFee) >= collateralType.dust || cdp.stablecoinDebt == 0);
        require(collateralType.debtMultiplierIncludingStabilityFee != 0);
        require(live == 1);
    }
    // --- CDP Fungibility ---
    function fork(bytes32 collateralType, address src, address dst, int changeInCollateral, int changeInDebt) public note {
        cdp storage u = cdps[collateralType][src];
        cdp storage v = cdps[collateralType][dst];
        collateralType storage i = collateralTypes[collateralType];

        u.collateralBalance = sub(u.collateralBalance, changeInCollateral);
        u.stablecoinDebt = sub(u.stablecoinDebt, changeInDebt);
        v.collateralBalance = add(v.collateralBalance, changeInCollateral);
        v.stablecoinDebt = add(v.stablecoinDebt, changeInDebt);

        // both sides consent
        require(wish(src, msg.sender) && wish(dst, msg.sender));

        // both sides safe
        require(mul(u.stablecoinDebt, i.debtMultiplierIncludingStabilityFee) <= mul(u.collateralBalance, i.maxDaiPerUnitOfCollateral));
        require(mul(v.stablecoinDebt, i.debtMultiplierIncludingStabilityFee) <= mul(v.collateralBalance, i.maxDaiPerUnitOfCollateral));

        // both sides non-dusty
        require(mul(u.stablecoinDebt, i.debtMultiplierIncludingStabilityFee) >= i.dust || u.stablecoinDebt == 0);
        require(mul(v.stablecoinDebt, i.debtMultiplierIncludingStabilityFee) >= i.dust || v.stablecoinDebt == 0);
    }
    // --- CDP Confiscation ---
    function liquidateCDP(bytes32 i, address u, address v, address w, int changeInCollateral, int changeInDebt) public note isAuthorized {
        cdp storage cdp = cdps[i][u];
        collateralType storage collateralType = collateralTypes[i];

        cdp.collateralBalance = add(cdp.collateralBalance, changeInCollateral);
        cdp.stablecoinDebt = add(cdp.stablecoinDebt, changeInDebt);
        collateralType.totalStablecoinDebt = add(collateralType.totalStablecoinDebt, changeInDebt);

        collateralTokens[i][v] = sub(collateralTokens[i][v], changeInCollateral);
        badDebt[w]    = sub(badDebt[w], mul(collateralType.debtMultiplierIncludingStabilityFee, changeInDebt));
        badDebtSupply      = sub(badDebtSupply,   mul(collateralType.debtMultiplierIncludingStabilityFee, changeInDebt));
    }

    // --- Settlement ---
    function settleDebtUsingSurplus(address u, address v, int fxp45Int) public note isAuthorized {
        badDebt[u] = sub(badDebt[u], fxp45Int);
        dai[v] = sub(dai[v], fxp45Int);
        badDebtSupply   = sub(badDebtSupply,   fxp45Int);
        stablecoinSupply   = sub(stablecoinSupply,   fxp45Int);
    }

    // --- debtMultiplierIncludingStabilityFee ---
    function changeDebtMultiplier(bytes32 i, address u, int debtMultiplierIncludingStabilityFee) public note isAuthorized {
        collateralType storage collateralType = collateralTypes[i];
        collateralType.debtMultiplierIncludingStabilityFee = add(collateralType.debtMultiplierIncludingStabilityFee, debtMultiplierIncludingStabilityFee);
        int fxp45Int  = mul(collateralType.totalStablecoinDebt, debtMultiplierIncludingStabilityFee);
        dai[u]   = add(dai[u], fxp45Int);
        stablecoinSupply     = add(stablecoinSupply,   fxp45Int);
    }
}
