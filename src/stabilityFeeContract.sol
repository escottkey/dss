pragma solidity >=0.5.0;
pragma experimental ABIEncoderV2;

import "./lib.sol";

contract cdpDatabaseInterface {
    struct collateralType {
        uint256 totalStablecoinDebt;   // fxp18Int
        uint256 debtMultiplierIncludingStabilityFee;  // fxp27Int
    }
    function collateralTypes(bytes32) public returns (collateralType memory);
    function changeDebtMultiplier(bytes32,address,int) public;
}

contract StabilityFeeContract is DSNote {
    // --- isAuthorized ---
    mapping (address => uint) public authenticatedAddresss;
    function authorizeAddress(address usr) public note isAuthorized { authenticatedAddresss[usr] = 1; }
    function deauthorizeAddress(address usr) public note isAuthorized { authenticatedAddresss[usr] = 0; }
    modifier isAuthorized { require(authenticatedAddresss[msg.sender] == 1); _; }

    // --- Data ---
    struct collateralType {
        uint256 duty;
        uint48  collateralTypeLastStabilityFeeCollectionTimestamp;
    }

    mapping (bytes32 => collateralType) public collateralTypes;
    cdpDatabaseInterface                  public cdpDatabase;
    address                  public Settlement;
    uint256                  public base;

    // --- Init ---
    constructor(address vat_) public {
        authenticatedAddresss[msg.sender] = 1;
        cdpDatabase = cdpDatabaseInterface(vat_);
    }

    // --- Math ---
    function rpow(uint x, uint n, uint b) internal pure returns (uint z) {
      assembly {
        switch x case 0 {switch n case 0 {z := b} default {z := 0}}
        default {
          switch mod(n, 2) case 0 { z := b } default { z := x }
          let half := div(b, 2)  // for rounding.
          for { n := div(n, 2) } n { n := div(n,2) } {
            let xx := mul(x, x)
            if iszero(eq(div(xx, x), x)) { revert(0,0) }
            let xxRound := add(xx, half)
            if lt(xxRound, xx) { revert(0,0) }
            x := div(xxRound, b)
            if mod(n,2) {
              let zx := mul(z, x)
              if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
              let zxRound := add(zx, half)
              if lt(zxRound, zx) { revert(0,0) }
              z := div(zxRound, b)
            }
          }
        }
      }
    }
    uint256 constant ONE = 10 ** 27;
    function add(uint x, uint y) internal pure returns (uint z) {
        z = x + y;
        require(z >= x);
    }
    function diff(uint x, uint y) internal pure returns (int z) {
        z = int(x) - int(y);
        require(int(x) >= 0 && int(y) >= 0);
    }
    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = x * y;
        require(y == 0 || z / y == x);
        z = z / ONE;
    }

    // --- Administration ---
    function createNewCollateralType(bytes32 collateralType) public note isAuthorized {
        collateralType storage i = collateralTypes[collateralType];
        require(i.duty == 0);
        i.duty = ONE;
        i.collateralTypeLastStabilityFeeCollectionTimestamp = uint48(now);
    }
    function changeConfig(bytes32 collateralType, bytes32 what, uint data) public note isAuthorized {
        if (what == "duty") collateralTypes[collateralType].duty = data;
    }
    function changeConfig(bytes32 what, uint data) public note isAuthorized {
        if (what == "base") base = data;
    }
    function changeConfig(bytes32 what, address data) public note isAuthorized {
        if (what == "Settlement") Settlement = data;
    }

    // --- Stability Fee Collection ---
    function increaseStabilityFee(bytes32 collateralType) public note {
        require(now >= collateralTypes[collateralType].collateralTypeLastStabilityFeeCollectionTimestamp);
        cdpDatabaseInterface.collateralType memory i = cdpDatabase.collateralTypes(collateralType);
        cdpDatabase.changeDebtMultiplier(collateralType, Settlement, diff(rmul(rpow(add(base, collateralTypes[collateralType].duty), now - collateralTypes[collateralType].collateralTypeLastStabilityFeeCollectionTimestamp, ONE), i.debtMultiplierIncludingStabilityFee), i.debtMultiplierIncludingStabilityFee));
        collateralTypes[collateralType].collateralTypeLastStabilityFeeCollectionTimestamp = uint48(now);
    }
}
