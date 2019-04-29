pragma solidity >=0.5.0;
pragma experimental ABIEncoderV2;

import "ds-test/test.sol";

import {StabilityFeeContract} from "../stabilityFeeDatabase.sol";
import {cdpDatabase} from "../cdpDatabase.sol";


contract Hevm {
    function warp(uint256) public;
}

contract cdpDatabaseInterface {
    function collateralTypes(bytes32) public view returns (cdpDatabase.collateralType memory);
    function cdps(bytes32,address) public view returns (cdpDatabase.cdp memory);
}

contract JugTest is DSTest {
    Hevm hevm;
    StabilityFeeContract increaseStabilityFee;
    cdpDatabase  cdpDatabase;

    function fxp45Int(uint fxp18Int_) internal pure returns (uint) {
        return fxp18Int_ * 10 ** 27;
    }
    function fxp18Int(uint fxp45Int_) internal pure returns (uint) {
        return fxp45Int_ / 10 ** 27;
    }
    function collateralTypeLastStabilityFeeCollectionTimestamp(bytes32 collateralType) internal view returns (uint) {
        (uint duty, uint48 collateralTypeLastStabilityFeeCollectionTimestamp_) = increaseStabilityFee.collateralTypes(collateralType); duty;
        return uint(collateralTypeLastStabilityFeeCollectionTimestamp_);
    }
    function debtMultiplierIncludingStabilityFee(bytes32 collateralType) internal view returns (uint) {
        cdpDatabase.collateralType memory i = cdpDatabaseInterface(address(cdpDatabase)).collateralTypes(collateralType);
        return i.debtMultiplierIncludingStabilityFee;
    }
    function debtCeiling(bytes32 collateralType) internal view returns (uint) {
        cdpDatabase.collateralType memory i = cdpDatabaseInterface(address(cdpDatabase)).collateralTypes(collateralType);
        return i.debtCeiling;
    }

    address ali = address(bytes20("ali"));

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(0);

        cdpDatabase  = new cdpDatabase();
        increaseStabilityFee = new StabilityFeeContract(address(cdpDatabase));
        cdpDatabase.authorizeAddress(address(increaseStabilityFee));
        cdpDatabase.createNewCollateralType("i");

        increaseCDPDebt("i", 100 ether);
    }
    function increaseCDPDebt(bytes32 collateralType, uint dai) internal {
        cdpDatabase.changeConfig("totalDebtCeiling", cdpDatabase.totalDebtCeiling() + fxp45Int(dai));
        cdpDatabase.changeConfig(collateralType, "debtCeiling", debtCeiling(collateralType) + fxp45Int(dai));
        cdpDatabase.changeConfig(collateralType, "maxDaiPerUnitOfCollateral", 10 ** 27 * 10000 ether);
        address self = address(this);
        cdpDatabase.modifyUsersCollateralBalance(collateralType, self,  10 ** 27 * 1 ether);
        cdpDatabase.modifyCDP(collateralType, self, self, self, int(1 ether), int(dai));
    }

    function test_increaseStabilityFee_setup() public {
        assertEq(uint(now), 0);
        hevm.warp(1);
        assertEq(uint(now), 1);
        hevm.warp(2);
        assertEq(uint(now), 2);
        cdpDatabase.collateralType memory i = cdpDatabaseInterface(address(cdpDatabase)).collateralTypes("i");
        assertEq(i.totalStablecoinDebt, 100 ether);
    }
    function test_increaseStabilityFee_updates_collateralTypeLastStabilityFeeCollectionTimestamp() public {
        increaseStabilityFee.createNewCollateralType("i");
        assertEq(collateralTypeLastStabilityFeeCollectionTimestamp("i"), 0);

        increaseStabilityFee.changeConfig("i", "duty", 10 ** 27);
        increaseStabilityFee.increaseStabilityFee("i");
        assertEq(collateralTypeLastStabilityFeeCollectionTimestamp("i"), 0);
        hevm.warp(1);
        assertEq(collateralTypeLastStabilityFeeCollectionTimestamp("i"), 0);
        increaseStabilityFee.increaseStabilityFee("i");
        assertEq(collateralTypeLastStabilityFeeCollectionTimestamp("i"), 1);
        hevm.warp(1 days);
        increaseStabilityFee.increaseStabilityFee("i");
        assertEq(collateralTypeLastStabilityFeeCollectionTimestamp("i"), 1 days);
    }
    function test_increaseStabilityFee_changeConfig() public {
        increaseStabilityFee.createNewCollateralType("i");
        increaseStabilityFee.changeConfig("i", "duty", 10 ** 27);
        hevm.warp(1);
        increaseStabilityFee.increaseStabilityFee("i");
        increaseStabilityFee.changeConfig("i", "duty", 1000000564701133626865910626);  // 5% / day
    }
    function test_increaseStabilityFee_0d() public {
        increaseStabilityFee.createNewCollateralType("i");
        increaseStabilityFee.changeConfig("i", "duty", 1000000564701133626865910626);  // 5% / day
        assertEq(cdpDatabase.dai(ali), fxp45Int(0 ether));
        increaseStabilityFee.increaseStabilityFee("i");
        assertEq(cdpDatabase.dai(ali), fxp45Int(0 ether));
    }
    function test_increaseStabilityFee_1d() public {
        increaseStabilityFee.createNewCollateralType("i");
        increaseStabilityFee.changeConfig("Settlement", ali);

        increaseStabilityFee.changeConfig("i", "duty", 1000000564701133626865910626);  // 5% / day
        hevm.warp(1 days);
        assertEq(fxp18Int(cdpDatabase.dai(ali)), 0 ether);
        increaseStabilityFee.increaseStabilityFee("i");
        assertEq(fxp18Int(cdpDatabase.dai(ali)), 5 ether);
    }
    function test_increaseStabilityFee_2d() public {
        increaseStabilityFee.createNewCollateralType("i");
        increaseStabilityFee.changeConfig("Settlement", ali);
        increaseStabilityFee.changeConfig("i", "duty", 1000000564701133626865910626);  // 5% / day

        hevm.warp(2 days);
        assertEq(fxp18Int(cdpDatabase.dai(ali)), 0 ether);
        increaseStabilityFee.increaseStabilityFee("i");
        assertEq(fxp18Int(cdpDatabase.dai(ali)), 10.25 ether);
    }
    function test_increaseStabilityFee_3d() public {
        increaseStabilityFee.createNewCollateralType("i");
        increaseStabilityFee.changeConfig("Settlement", ali);

        increaseStabilityFee.changeConfig("i", "duty", 1000000564701133626865910626);  // 5% / day
        hevm.warp(3 days);
        assertEq(fxp18Int(cdpDatabase.dai(ali)), 0 ether);
        increaseStabilityFee.increaseStabilityFee("i");
        assertEq(fxp18Int(cdpDatabase.dai(ali)), 15.7625 ether);
    }
    function test_increaseStabilityFee_multi() public {
        increaseStabilityFee.createNewCollateralType("i");
        increaseStabilityFee.changeConfig("Settlement", ali);

        increaseStabilityFee.changeConfig("i", "duty", 1000000564701133626865910626);  // 5% / day
        hevm.warp(1 days);
        increaseStabilityFee.increaseStabilityFee("i");
        assertEq(fxp18Int(cdpDatabase.dai(ali)), 5 ether);
        increaseStabilityFee.changeConfig("i", "duty", 1000001103127689513476993127);  // 10% / day
        hevm.warp(2 days);
        increaseStabilityFee.increaseStabilityFee("i");
        assertEq(fxp18Int(cdpDatabase.dai(ali)),  15.5 ether);
        assertEq(fxp18Int(cdpDatabase.stablecoinSupply()),     115.5 ether);
        assertEq(debtMultiplierIncludingStabilityFee("i") / 10 ** 9, 1.155 ether);
    }
    function test_increaseStabilityFee_base() public {
        cdpDatabase.createNewCollateralType("j");
        increaseCDPDebt("j", 100 ether);

        increaseStabilityFee.createNewCollateralType("i");
        increaseStabilityFee.createNewCollateralType("j");
        increaseStabilityFee.changeConfig("Settlement", ali);

        increaseStabilityFee.changeConfig("i", "duty", 1050000000000000000000000000);  // 5% / second
        increaseStabilityFee.changeConfig("j", "duty", 1000000000000000000000000000);  // 0% / second
        increaseStabilityFee.changeConfig("base",  uint(50000000000000000000000000)); // 5% / second
        hevm.warp(1);
        increaseStabilityFee.increaseStabilityFee("i");
        assertEq(fxp18Int(cdpDatabase.dai(ali)), 10 ether);
    }
}
