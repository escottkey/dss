pragma solidity >=0.5.0;

import "ds-test/test.sol";
import "ds-token/token.sol";

import {cdpDatabase} from '../cdpDatabase.sol';

contract Usr {
    cdpDatabase public cdpDatabase;
    constructor(cdpDatabase vat_) public {
        cdpDatabase = vat_;
    }
    function try_call(address addr, bytes calldata data) external returns (bool) {
        bytes memory _data = data;
        assembly {
            let ok := call(gas, addr, 0, add(_data, 0x20), mload(_data), 0, 0)
            let transferCollateralFromCDP := mload(0x40)
            mstore(transferCollateralFromCDP, ok)
            mstore(0x40, add(transferCollateralFromCDP, 32))
            revert(transferCollateralFromCDP, 32)
        }
    }
    function can_frob(bytes32 collateralType, address u, address v, address w, int changeInCollateral, int changeInDebt) public returns (bool) {
        string memory sig = "modifyCDP(bytes32,address,address,address,int256,int256)";
        bytes memory data = abi.encodeWithSignature(sig, collateralType, u, v, w, changeInCollateral, changeInDebt);

        bytes memory can_call = abi.encodeWithSignature("try_call(address,bytes)", cdpDatabase, data);
        (bool ok, bytes memory success) = address(this).call(can_call);

        ok = abi.decode(success, (bool));
        if (ok) return true;
    }
    function can_fork(bytes32 collateralType, address src, address dst, int changeInCollateral, int changeInDebt) public returns (bool) {
        string memory sig = "fork(bytes32,address,address,int256,int256)";
        bytes memory data = abi.encodeWithSignature(sig, collateralType, src, dst, changeInCollateral, changeInDebt);

        bytes memory can_call = abi.encodeWithSignature("try_call(address,bytes)", cdpDatabase, data);
        (bool ok, bytes memory success) = address(this).call(can_call);

        ok = abi.decode(success, (bool));
        if (ok) return true;
    }
    function modifyCDP(bytes32 collateralType, address u, address v, address w, int changeInCollateral, int changeInDebt) public {
        cdpDatabase.modifyCDP(collateralType, u, v, w, changeInCollateral, changeInDebt);
    }
    function fork(bytes32 collateralType, address src, address dst, int changeInCollateral, int changeInDebt) public {
        cdpDatabase.fork(collateralType, src, dst, changeInCollateral, changeInDebt);
    }
    function hope(address usr) public {
        cdpDatabase.hope(usr);
    }
    function pass() public {}
}

contract ForkTest is DSTest {
    cdpDatabase cdpDatabase;
    Usr ali;
    Usr bob;
    address a;
    address b;

    function fxp27Int(uint fxp18Int) internal pure returns (uint) {
        return fxp18Int * 10 ** 9;
    }
    function fxp45Int(uint fxp18Int) internal pure returns (uint) {
        return fxp18Int * 10 ** 27;
    }

    function setUp() public {
        cdpDatabase = new cdpDatabase();
        ali = new Usr(cdpDatabase);
        bob = new Usr(cdpDatabase);
        a = address(ali);
        b = address(bob);

        cdpDatabase.createNewCollateralType("collateralTokenss");
        cdpDatabase.changeConfig("collateralTokenss", "maxDaiPerUnitOfCollateral", fxp27Int(0.5  ether));
        cdpDatabase.changeConfig("collateralTokenss", "debtCeiling", fxp45Int(1000 ether));
        cdpDatabase.changeConfig("totalDebtCeiling",         fxp45Int(1000 ether));

        cdpDatabase.modifyUsersCollateralBalance("collateralTokenss", a, 8 ether);
    }
    function test_fork_to_self() public {
        ali.modifyCDP("collateralTokenss", a, a, a, 8 ether, 4 ether);
        assertTrue( ali.can_fork("collateralTokenss", a, a, 8 ether, 4 ether));
        assertTrue( ali.can_fork("collateralTokenss", a, a, 4 ether, 2 ether));
        assertTrue(!ali.can_fork("collateralTokenss", a, a, 9 ether, 4 ether));
    }
    function test_give_to_other() public {
        ali.modifyCDP("collateralTokenss", a, a, a, 8 ether, 4 ether);
        assertTrue(!ali.can_fork("collateralTokenss", a, b, 8 ether, 4 ether));
        bob.hope(address(ali));
        assertTrue( ali.can_fork("collateralTokenss", a, b, 8 ether, 4 ether));
    }
    function test_fork_to_other() public {
        ali.modifyCDP("collateralTokenss", a, a, a, 8 ether, 4 ether);
        bob.hope(address(ali));
        assertTrue( ali.can_fork("collateralTokenss", a, b, 4 ether, 2 ether));
        assertTrue(!ali.can_fork("collateralTokenss", a, b, 4 ether, 3 ether));
        assertTrue(!ali.can_fork("collateralTokenss", a, b, 4 ether, 1 ether));
    }
    function test_fork_dust() public {
        ali.modifyCDP("collateralTokenss", a, a, a, 8 ether, 4 ether);
        bob.hope(address(ali));
        assertTrue( ali.can_fork("collateralTokenss", a, b, 4 ether, 2 ether));
        cdpDatabase.changeConfig("collateralTokenss", "dust", fxp45Int(1 ether));
        assertTrue( ali.can_fork("collateralTokenss", a, b, 2 ether, 1 ether));
        assertTrue(!ali.can_fork("collateralTokenss", a, b, 1 ether, 0.5 ether));
    }
}
