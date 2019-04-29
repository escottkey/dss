pragma solidity >=0.5.0;

import "ds-test/test.sol";
import "ds-token/token.sol";

import {cdpDatabase} from '../cdpDatabase.sol';
import {Liquidation} from '../cat.sol';
import {Settlement} from '../Settlement.sol';
import {StabilityFeeContract} from '../stabilityFeeDatabase.sol';
import {collateralTokensAddCollateral, ETHAddCollateral, DaiAddCollateral} from '../addCollateral.sol';

import {CollateralForDaiAuction} from './collateralForDaiAuction.t.sol';
import {MkrForDaiDebtAuction} from './MkrForDaiDebtAuction.t.sol';
import {DaiForMkrSurplusAuction} from './DaiForMkrSurplusAuction.t.sol';


contract Hevm {
    function warp(uint256) public;
}

contract TestVat is cdpDatabase {
    uint256 constant ONE = 10 ** 27;
    function mint(address usr, uint fxp18Int) public {
        dai[usr] += fxp18Int * ONE;
        stablecoinSupply += fxp18Int * ONE;
    }
    function balanceOf(address usr) public view returns (uint) {
        return dai[usr] / ONE;
    }
    function modifyCDP(bytes32 collateralType, int changeInCollateral, int changeInDebt) public {
        address usr = msg.sender;
        modifyCDP(collateralType, usr, usr, usr, changeInCollateral, changeInDebt);
    }
}

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
}


contract FrobTest is DSTest {
    TestVat cdpDatabase;
    DSToken gold;
    StabilityFeeContract     stabilityFeeDatabase;

    collateralTokensAddCollateral collateralTokensA;

    function try_frob(bytes32 collateralType, int collateralBalance, int stablecoinDebt) public returns (bool ok) {
        string memory sig = "modifyCDP(bytes32,address,address,address,int256,int256)";
        address self = address(this);
        (ok,) = address(cdpDatabase).call(abi.encodeWithSignature(sig, collateralType, self, self, self, collateralBalance, stablecoinDebt));
    }

    function fxp27Int(uint fxp18Int) internal pure returns (uint) {
        return fxp18Int * 10 ** 9;
    }

    function setUp() public {
        cdpDatabase = new TestVat();

        gold = new DSToken("collateralTokens");
        gold.mint(1000 ether);

        cdpDatabase.createNewCollateralType("gold");
        collateralTokensA = new collateralTokensAddCollateral(address(cdpDatabase), "gold", address(gold));

        cdpDatabase.changeConfig("gold", "maxDaiPerUnitOfCollateral",    fxp27Int(1 ether));
        cdpDatabase.changeConfig("gold", "debtCeiling", fxp45Int(1000 ether));
        cdpDatabase.changeConfig("totalDebtCeiling",         fxp45Int(1000 ether));
        stabilityFeeDatabase = new StabilityFeeContract(address(cdpDatabase));
        stabilityFeeDatabase.createNewCollateralType("gold");
        cdpDatabase.authorizeAddress(address(stabilityFeeDatabase));

        gold.approve(address(collateralTokensA));
        gold.approve(address(cdpDatabase));

        cdpDatabase.authorizeAddress(address(cdpDatabase));
        cdpDatabase.authorizeAddress(address(collateralTokensA));

        collateralTokensA.addCollateral(address(this), 1000 ether);
    }

    function collateralTokens(bytes32 collateralType, address cdp) internal view returns (uint) {
        return cdpDatabase.collateralTokens(collateralType, cdp);
    }
    function collateralBalance(bytes32 collateralType, address cdp) internal view returns (uint) {
        (uint collateralBalance_, uint art_) = cdpDatabase.cdps(collateralType, cdp); art_;
        return collateralBalance_;
    }
    function stablecoinDebt(bytes32 collateralType, address cdp) internal view returns (uint) {
        (uint collateralBalance_, uint art_) = cdpDatabase.cdps(collateralType, cdp); collateralBalance_;
        return art_;
    }

    function test_setup() public {
        assertEq(gold.balanceOf(address(collateralTokensA)), 1000 ether);
        assertEq(collateralTokens("gold",    address(this)), 1000 ether);
    }
    function test_join() public {
        address cdp = address(this);
        gold.mint(500 ether);
        assertEq(gold.balanceOf(address(this)),    500 ether);
        assertEq(gold.balanceOf(address(collateralTokensA)),   1000 ether);
        collateralTokensA.addCollateral(cdp,                             500 ether);
        assertEq(gold.balanceOf(address(this)),      0 ether);
        assertEq(gold.balanceOf(address(collateralTokensA)),   1500 ether);
        collateralTokensA.removeCollateral(cdp,                             250 ether);
        assertEq(gold.balanceOf(address(this)),    250 ether);
        assertEq(gold.balanceOf(address(collateralTokensA)),   1250 ether);
    }
    function test_lock() public {
        assertEq(collateralBalance("gold", address(this)),    0 ether);
        assertEq(collateralTokens("gold", address(this)), 1000 ether);
        cdpDatabase.modifyCDP("gold", 6 ether, 0);
        assertEq(collateralBalance("gold", address(this)),   6 ether);
        assertEq(collateralTokens("gold", address(this)), 994 ether);
        cdpDatabase.modifyCDP("gold", -6 ether, 0);
        assertEq(collateralBalance("gold", address(this)),    0 ether);
        assertEq(collateralTokens("gold", address(this)), 1000 ether);
    }
    function test_isCdpBelowCollateralAndTotalDebtCeilings() public {
        // isCdpBelowCollateralAndTotalDebtCeilings means that the stablecoinSupply ceiling is not exceeded
        // it's ok to increase stablecoinSupply as long as you remain below the stablecoinSupply ceilings
        cdpDatabase.changeConfig("gold", 'debtCeiling', fxp45Int(10 ether));
        assertTrue( try_frob("gold", 10 ether, 9 ether));
        // only if under stablecoinSupply ceiling
        assertTrue(!try_frob("gold",  0 ether, 2 ether));
    }
    function test_isCdpDaiDebtNonIncreasing() public {
        // isCdpDaiDebtNonIncreasing means that the stablecoinSupply has not increased
        // it's ok to be over the stablecoinSupply ceiling as long as you're not increasing the stablecoinSupply
        cdpDatabase.changeConfig("gold", 'debtCeiling', fxp45Int(10 ether));
        assertTrue(try_frob("gold", 10 ether,  8 ether));
        cdpDatabase.changeConfig("gold", 'debtCeiling', fxp45Int(5 ether));
        // can decrease stablecoinSupply when over ceiling
        assertTrue(try_frob("gold",  0 ether, -1 ether));
    }
    function test_isCdpSafe() public {
        // isCdpSafe means that the cdp is not risky
        // you can't modifyCDP a cdp into unsafe
        cdpDatabase.modifyCDP("gold", 10 ether, 5 ether);                // safe increaseCDPDebt
        assertTrue(!try_frob("gold", 0 ether, 6 ether));  // unsafe increaseCDPDebt
    }
    function test_nice() public {
        // nice means that the collateral has increased or the stablecoinSupply has
        // decreased. remaining unsafe is ok as long as you're nice

        cdpDatabase.modifyCDP("gold", 10 ether, 10 ether);
        cdpDatabase.changeConfig("gold", 'maxDaiPerUnitOfCollateral', fxp27Int(0.5 ether));  // now unsafe

        // stablecoinSupply can't increase if unsafe
        assertTrue(!try_frob("gold",  0 ether,  1 ether));
        // stablecoinSupply can decrease
        assertTrue( try_frob("gold",  0 ether, -1 ether));
        // collateralBalance can't decrease
        assertTrue(!try_frob("gold", -1 ether,  0 ether));
        // collateralBalance can increase
        assertTrue( try_frob("gold",  1 ether,  0 ether));

        // cdp is still unsafe
        // collateralBalance can't decrease, even if stablecoinSupply decreases more
        assertTrue(!this.try_frob("gold", -2 ether, -4 ether));
        // stablecoinSupply can't increase, even if collateralBalance increases more
        assertTrue(!this.try_frob("gold",  5 ether,  1 ether));

        // collateralBalance can decrease if end state is safe
        assertTrue( this.try_frob("gold", -1 ether, -4 ether));
        cdpDatabase.changeConfig("gold", 'maxDaiPerUnitOfCollateral', fxp27Int(0.4 ether));  // now unsafe
        // stablecoinSupply can increase if end state is safe
        assertTrue( this.try_frob("gold",  5 ether, 1 ether));
    }

    function fxp45Int(uint fxp18Int) internal pure returns (uint) {
        return fxp18Int * 10 ** 27;
    }
    function test_alt_callers() public {
        Usr ali = new Usr(cdpDatabase);
        Usr bob = new Usr(cdpDatabase);
        Usr che = new Usr(cdpDatabase);

        address a = address(ali);
        address b = address(bob);
        address c = address(che);

        cdpDatabase.modifyUsersCollateralBalance("gold", a, int(fxp45Int(20 ether)));
        cdpDatabase.modifyUsersCollateralBalance("gold", b, int(fxp45Int(20 ether)));
        cdpDatabase.modifyUsersCollateralBalance("gold", c, int(fxp45Int(20 ether)));

        ali.modifyCDP("gold", a, a, a, 10 ether, 5 ether);

        // anyone can transferCollateralToCDP
        assertTrue( ali.can_frob("gold", a, a, a,  1 ether,  0 ether));
        assertTrue( bob.can_frob("gold", a, b, b,  1 ether,  0 ether));
        assertTrue( che.can_frob("gold", a, c, c,  1 ether,  0 ether));
        // but only with their own collateralTokenss
        assertTrue(!ali.can_frob("gold", a, b, a,  1 ether,  0 ether));
        assertTrue(!bob.can_frob("gold", a, c, b,  1 ether,  0 ether));
        assertTrue(!che.can_frob("gold", a, a, c,  1 ether,  0 ether));

        // only the lad can transferCollateralFromCDP
        assertTrue( ali.can_frob("gold", a, a, a, -1 ether,  0 ether));
        assertTrue(!bob.can_frob("gold", a, b, b, -1 ether,  0 ether));
        assertTrue(!che.can_frob("gold", a, c, c, -1 ether,  0 ether));
        // the lad can transferCollateralFromCDP to anywhere
        assertTrue( ali.can_frob("gold", a, b, a, -1 ether,  0 ether));
        assertTrue( ali.can_frob("gold", a, c, a, -1 ether,  0 ether));

        // only the lad can increaseCDPDebt
        assertTrue( ali.can_frob("gold", a, a, a,  0 ether,  1 ether));
        assertTrue(!bob.can_frob("gold", a, b, b,  0 ether,  1 ether));
        assertTrue(!che.can_frob("gold", a, c, c,  0 ether,  1 ether));
        // the lad can increaseCDPDebt to anywhere
        assertTrue( ali.can_frob("gold", a, a, b,  0 ether,  1 ether));
        assertTrue( ali.can_frob("gold", a, a, c,  0 ether,  1 ether));

        cdpDatabase.mint(address(bob), 1 ether);
        cdpDatabase.mint(address(che), 1 ether);

        // anyone can decreaseCDPDebt
        assertTrue( ali.can_frob("gold", a, a, a,  0 ether, -1 ether));
        assertTrue( bob.can_frob("gold", a, b, b,  0 ether, -1 ether));
        assertTrue( che.can_frob("gold", a, c, c,  0 ether, -1 ether));
        // but only with their own dai
        assertTrue(!ali.can_frob("gold", a, a, b,  0 ether, -1 ether));
        assertTrue(!bob.can_frob("gold", a, b, c,  0 ether, -1 ether));
        assertTrue(!che.can_frob("gold", a, c, a,  0 ether, -1 ether));
    }

    function test_hope() public {
        Usr ali = new Usr(cdpDatabase);
        Usr bob = new Usr(cdpDatabase);
        Usr che = new Usr(cdpDatabase);

        address a = address(ali);
        address b = address(bob);
        address c = address(che);

        cdpDatabase.modifyUsersCollateralBalance("gold", a, int(fxp45Int(20 ether)));
        cdpDatabase.modifyUsersCollateralBalance("gold", b, int(fxp45Int(20 ether)));
        cdpDatabase.modifyUsersCollateralBalance("gold", c, int(fxp45Int(20 ether)));

        ali.modifyCDP("gold", a, a, a, 10 ether, 5 ether);

        // only owner can do risky actions
        assertTrue( ali.can_frob("gold", a, a, a,  0 ether,  1 ether));
        assertTrue(!bob.can_frob("gold", a, b, b,  0 ether,  1 ether));
        assertTrue(!che.can_frob("gold", a, c, c,  0 ether,  1 ether));

        ali.hope(address(bob));

        // unless they hope another user
        assertTrue( ali.can_frob("gold", a, a, a,  0 ether,  1 ether));
        assertTrue( bob.can_frob("gold", a, b, b,  0 ether,  1 ether));
        assertTrue(!che.can_frob("gold", a, c, c,  0 ether,  1 ether));
    }

    function test_dust() public {
        assertTrue( try_frob("gold", 9 ether,  1 ether));
        cdpDatabase.changeConfig("gold", "dust", fxp45Int(5 ether));
        assertTrue(!try_frob("gold", 5 ether,  2 ether));
        assertTrue( try_frob("gold", 0 ether,  5 ether));
        assertTrue(!try_frob("gold", 0 ether, -5 ether));
        assertTrue( try_frob("gold", 0 ether, -6 ether));
    }
}

contract AddCollateralTest is DSTest {
    TestVat cdpDatabase;
    ETHAddCollateral ethA;
    DaiAddCollateral daiA;
    DSToken dai;
    address me;

    function setUp() public {
        cdpDatabase = new TestVat();
        cdpDatabase.createNewCollateralType("eth");

        ethA = new ETHAddCollateral(address(cdpDatabase), "eth");
        cdpDatabase.authorizeAddress(address(ethA));

        dai  = new DSToken("Dai");
        daiA = new DaiAddCollateral(address(cdpDatabase), address(dai));
        cdpDatabase.authorizeAddress(address(daiA));
        dai.setOwner(address(daiA));

        me = address(this);
    }
    function () external payable {}
    function test_eth_join() public {
        ethA.addCollateral.value(10 ether)(address(this));
        assertEq(cdpDatabase.collateralTokens("eth", me), 10 ether);
    }
    function test_eth_exit() public {
        address payable cdp = address(this);
        ethA.addCollateral.value(50 ether)(cdp);
        ethA.removeCollateral(cdp, 10 ether);
        assertEq(cdpDatabase.collateralTokens("eth", me), 40 ether);
    }
    function fxp45Int(uint fxp18Int) internal pure returns (uint) {
        return fxp18Int * 10 ** 27;
    }
    function test_dai_exit() public {
        address cdp = address(this);
        cdpDatabase.mint(address(this), 100 ether);
        cdpDatabase.hope(address(daiA));
        daiA.removeCollateral(cdp, 60 ether);
        assertEq(dai.balanceOf(address(this)), 60 ether);
        assertEq(cdpDatabase.dai(me),              fxp45Int(40 ether));
    }
    function test_dai_exit_join() public {
        address cdp = address(this);
        cdpDatabase.mint(address(this), 100 ether);
        cdpDatabase.hope(address(daiA));
        daiA.removeCollateral(cdp, 60 ether);
        dai.approve(address(daiA), uint(-1));
        daiA.addCollateral(cdp, 30 ether);
        assertEq(dai.balanceOf(address(this)),     30 ether);
        assertEq(cdpDatabase.dai(me),                  fxp45Int(70 ether));
    }
    function test_fallback_reverts() public {
        (bool ok,) = address(ethA).call("invalid calldata");
        assertTrue(!ok);
    }
    function test_nonzero_fallback_reverts() public {
        (bool ok,) = address(ethA).call.value(10)("invalid calldata");
        assertTrue(!ok);
    }
}

contract LiquidateCdpTest is DSTest {
    Hevm hevm;

    TestVat cdpDatabase;
    Settlement     Settlement;
    Liquidation     cat;
    DSToken gold;
    StabilityFeeContract     stabilityFeeDatabase;

    collateralTokensAddCollateral collateralTokensA;

    CollateralForDaiAuction collateralForDaiAuction;
    MkrForDaiDebtAuction mkrForDaiDebtAuction;
    DaiForMkrSurplusAuction daiForMkrSurplusAuction;

    DSToken gov;

    function try_frob(bytes32 collateralType, int collateralBalance, int stablecoinDebt) public returns (bool ok) {
        string memory sig = "modifyCDP(bytes32,address,address,address,int256,int256)";
        address self = address(this);
        (ok,) = address(cdpDatabase).call(abi.encodeWithSignature(sig, collateralType, self, self, self, collateralBalance, stablecoinDebt));
    }

    function fxp27Int(uint fxp18Int) internal pure returns (uint) {
        return fxp18Int * 10 ** 9;
    }
    function fxp45Int(uint fxp18Int) internal pure returns (uint) {
        return fxp18Int * 10 ** 27;
    }

    function collateralTokens(bytes32 collateralType, address cdp) internal view returns (uint) {
        return cdpDatabase.collateralTokens(collateralType, cdp);
    }
    function collateralBalance(bytes32 collateralType, address cdp) internal view returns (uint) {
        (uint collateralBalance_, uint art_) = cdpDatabase.cdps(collateralType, cdp); art_;
        return collateralBalance_;
    }
    function stablecoinDebt(bytes32 collateralType, address cdp) internal view returns (uint) {
        (uint collateralBalance_, uint art_) = cdpDatabase.cdps(collateralType, cdp); collateralBalance_;
        return art_;
    }

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(0);

        gov = new DSToken('GOV');
        gov.mint(100 ether);

        cdpDatabase = new TestVat();
        cdpDatabase = cdpDatabase;

        daiForMkrSurplusAuction = new DaiForMkrSurplusAuction(address(cdpDatabase), address(gov));
        mkrForDaiDebtAuction = new MkrForDaiDebtAuction(address(cdpDatabase), address(gov));
        gov.setOwner(address(mkrForDaiDebtAuction));

        Settlement = new Settlement();
        Settlement.changeConfig("cdpDatabase",  address(cdpDatabase));
        Settlement.changeConfig("daiForMkrSurplusAuction", address(daiForMkrSurplusAuction));
        Settlement.changeConfig("mkrForDaiDebtAuction", address(mkrForDaiDebtAuction));
        mkrForDaiDebtAuction.authorizeAddress(address(Settlement));

        stabilityFeeDatabase = new StabilityFeeContract(address(cdpDatabase));
        stabilityFeeDatabase.createNewCollateralType("gold");
        stabilityFeeDatabase.changeConfig("Settlement", address(Settlement));
        cdpDatabase.authorizeAddress(address(stabilityFeeDatabase));

        cat = new Liquidation(address(cdpDatabase));
        cat.changeConfig("Settlement", address(Settlement));
        cdpDatabase.authorizeAddress(address(cat));
        Settlement.authorizeAddress(address(cat));

        gold = new DSToken("collateralTokens");
        gold.mint(1000 ether);

        cdpDatabase.createNewCollateralType("gold");
        collateralTokensA = new collateralTokensAddCollateral(address(cdpDatabase), "gold", address(gold));
        cdpDatabase.authorizeAddress(address(collateralTokensA));
        gold.approve(address(collateralTokensA));
        collateralTokensA.addCollateral(address(this), 1000 ether);

        cdpDatabase.changeConfig("gold", "maxDaiPerUnitOfCollateral", fxp27Int(1 ether));
        cdpDatabase.changeConfig("gold", "debtCeiling", fxp45Int(1000 ether));
        cdpDatabase.changeConfig("totalDebtCeiling",         fxp45Int(1000 ether));
        collateralForDaiAuction = new CollateralForDaiAuction(address(cdpDatabase), "gold");
        cat.changeConfig("gold", "collateralForDaiAuction", address(collateralForDaiAuction));
        cat.changeConfig("gold", "liquidationPenalty", fxp27Int(1 ether));

        cdpDatabase.authorizeAddress(address(collateralForDaiAuction));
        cdpDatabase.authorizeAddress(address(daiForMkrSurplusAuction));
        cdpDatabase.authorizeAddress(address(mkrForDaiDebtAuction));

        cdpDatabase.hope(address(collateralForDaiAuction));
        cdpDatabase.hope(address(mkrForDaiDebtAuction));
        gold.approve(address(cdpDatabase));
        gov.approve(address(daiForMkrSurplusAuction));
    }
    function test_happy_liquidateCdp() public {
        // maxDaiPerUnitOfCollateral = tag / (par . mat)
        // tag=5, mat=2
        cdpDatabase.changeConfig("gold", 'maxDaiPerUnitOfCollateral', fxp27Int(2.5 ether));
        cdpDatabase.modifyCDP("gold",  40 ether, 100 ether);

        // tag=4, mat=2
        cdpDatabase.changeConfig("gold", 'maxDaiPerUnitOfCollateral', fxp27Int(2 ether));  // now unsafe

        assertEq(collateralBalance("gold", address(this)),  40 ether);
        assertEq(stablecoinDebt("gold", address(this)), 100 ether);
        assertEq(Settlement.TotalNonQueuedNonAuctionDebt(), 0 ether);
        assertEq(collateralTokens("gold", address(this)), 960 ether);
        uint id = cat.liquidateCdp("gold", address(this));
        assertEq(collateralBalance("gold", address(this)), 0);
        assertEq(stablecoinDebt("gold", address(this)), 0);
        assertEq(Settlement.debtQueue(uint48(now)),   fxp45Int(100 ether));
        assertEq(collateralTokens("gold", address(this)), 960 ether);

        cat.changeConfig("gold", "liquidationQuantity", fxp45Int(100 ether));
        uint auction = cat.collateralForDaiAuction(id, fxp45Int(100 ether));  // collateralForDaiAuction all the debtPlusStabilityFee

        assertEq(cdpDatabase.balanceOf(address(Settlement)),    0 ether);
        collateralForDaiAuction.makeBidIncreaseBidSize(auction, 40 ether,   fxp45Int(1 ether));
        assertEq(cdpDatabase.balanceOf(address(Settlement)),    1 ether);
        collateralForDaiAuction.makeBidIncreaseBidSize(auction, 40 ether, fxp45Int(100 ether));
        assertEq(cdpDatabase.balanceOf(address(Settlement)),  100 ether);

        assertEq(cdpDatabase.balanceOf(address(this)),   0 ether);
        assertEq(collateralTokens("gold", address(this)),   960 ether);
        cdpDatabase.mint(address(this), 100 ether);  // magic up some dai for bidding
        collateralForDaiAuction.makeBidDecreaseLotSize(auction, 38 ether,  fxp45Int(100 ether));
        assertEq(cdpDatabase.balanceOf(address(this)), 100 ether);
        assertEq(cdpDatabase.balanceOf(address(Settlement)),  100 ether);
        assertEq(collateralTokens("gold", address(this)),   962 ether);
        assertEq(collateralTokens("gold", address(this)),   962 ether);

        assertEq(Settlement.debtQueue(uint48(now)),     fxp45Int(100 ether));
        assertEq(cdpDatabase.balanceOf(address(Settlement)),  100 ether);
    }

    function test_debtAuction_liquidateCdp() public {
        cdpDatabase.changeConfig("gold", 'maxDaiPerUnitOfCollateral', fxp27Int(2.5 ether));
        cdpDatabase.modifyCDP("gold",  40 ether, 100 ether);
        cdpDatabase.changeConfig("gold", 'maxDaiPerUnitOfCollateral', fxp27Int(2 ether));  // now unsafe

        assertEq(Settlement.debtQueue(uint48(now)), fxp45Int(  0 ether));
        cat.liquidateCdp("gold", address(this));
        assertEq(Settlement.debtQueue(uint48(now)), fxp45Int(100 ether));

        assertEq(Settlement.TotalDebtInQueue(), fxp45Int(100 ether));
        Settlement.removeDebtFromDebtQueue(uint48(now));
        assertEq(Settlement.TotalDebtInQueue(), fxp45Int(  0 ether));
        assertEq(Settlement.TotalNonQueuedNonAuctionDebt(), fxp45Int(100 ether));
        assertEq(Settlement.TotalSurplus(), fxp45Int(  0 ether));
        assertEq(Settlement.TotalOnAuctionDebt(), fxp45Int(  0 ether));

        Settlement.changeConfig("debtAuctionLotSize", fxp45Int(10 ether));
        uint f1 = Settlement.mkrForDaiDebtAuction();
        assertEq(Settlement.TotalNonQueuedNonAuctionDebt(),  fxp45Int(90 ether));
        assertEq(Settlement.TotalSurplus(),  fxp45Int( 0 ether));
        assertEq(Settlement.TotalOnAuctionDebt(),  fxp45Int(10 ether));
        mkrForDaiDebtAuction.makeBidDecreaseLotSize(f1, 1000 ether, fxp45Int(10 ether));
        assertEq(Settlement.TotalNonQueuedNonAuctionDebt(),  fxp45Int(90 ether));
        assertEq(Settlement.TotalSurplus(),  fxp45Int(10 ether));
        assertEq(Settlement.TotalOnAuctionDebt(),  fxp45Int(10 ether));

        assertEq(gov.balanceOf(address(this)),  100 ether);
        hevm.warp(4 hours);
        mkrForDaiDebtAuction.claimWinningBid(f1);
        assertEq(gov.balanceOf(address(this)), 1100 ether);
    }

    function test_surplusAuction_liquidateCdp() public {
        // get some surplus
        cdpDatabase.mint(address(Settlement), 100 ether);
        assertEq(cdpDatabase.balanceOf(address(Settlement)),  100 ether);
        assertEq(gov.balanceOf(address(this)), 100 ether);

        Settlement.changeConfig("surplusAuctionLotSize", fxp45Int(100 ether));
        assertEq(Settlement.TotalDebt(), 0 ether);
        uint id = Settlement.daiForMkrSurplusAuction();

        assertEq(cdpDatabase.balanceOf(address(this)),   0 ether);
        assertEq(gov.balanceOf(address(this)), 100 ether);
        daiForMkrSurplusAuction.makeBidIncreaseBidSize(id, fxp45Int(100 ether), 10 ether);
        hevm.warp(4 hours);
        daiForMkrSurplusAuction.claimWinningBid(id);
        assertEq(cdpDatabase.balanceOf(address(this)),   100 ether);
        assertEq(gov.balanceOf(address(this)),    90 ether);
    }
}

contract FoldTest is DSTest {
    cdpDatabase cdpDatabase;

    function fxp27Int(uint fxp18Int) internal pure returns (uint) {
        return fxp18Int * 10 ** 9;
    }
    function fxp45Int(uint fxp18Int) internal pure returns (uint) {
        return fxp18Int * 10 ** 27;
    }
    function debtPlusStabilityFee(bytes32 collateralType, address cdp) internal view returns (uint) {
        (uint collateralBalance_, uint art_) = cdpDatabase.cdps(collateralType, cdp); collateralBalance_;
        (uint totalStablecoinDebt_, uint debtMultiplierIncludingStabilityFee, uint maxDaiPerUnitOfCollateral, uint debtCeiling, uint dust) = cdpDatabase.collateralTypes(collateralType);
        totalStablecoinDebt_; maxDaiPerUnitOfCollateral; debtCeiling; dust;
        return art_ * debtMultiplierIncludingStabilityFee;
    }
    function jam(bytes32 collateralType, address cdp) internal view returns (uint) {
        (uint collateralBalance_, uint art_) = cdpDatabase.cdps(collateralType, cdp); art_;
        return collateralBalance_;
    }

    function setUp() public {
        cdpDatabase = new cdpDatabase();
        cdpDatabase.createNewCollateralType("gold");
        cdpDatabase.changeConfig("totalDebtCeiling", fxp45Int(100 ether));
        cdpDatabase.changeConfig("gold", "debtCeiling", fxp45Int(100 ether));
    }
    function increaseCDPDebt(bytes32 collateralType, uint dai) internal {
        cdpDatabase.changeConfig("totalDebtCeiling", fxp45Int(dai));
        cdpDatabase.changeConfig(collateralType, "debtCeiling", fxp45Int(dai));
        cdpDatabase.changeConfig(collateralType, "maxDaiPerUnitOfCollateral", 10 ** 27 * 10000 ether);
        address self = address(this);
        cdpDatabase.modifyUsersCollateralBalance(collateralType, self,  10 ** 27 * 1 ether);
        cdpDatabase.modifyCDP(collateralType, self, self, self, int(1 ether), int(dai));
    }
    function test_fold() public {
        address self = address(this);
        address ali  = address(bytes20("ali"));
        increaseCDPDebt("gold", 1 ether);

        assertEq(debtPlusStabilityFee("gold", self), fxp45Int(1.00 ether));
        cdpDatabase.changeDebtMultiplier("gold", ali,   int(fxp27Int(0.05 ether)));
        assertEq(debtPlusStabilityFee("gold", self), fxp45Int(1.05 ether));
        assertEq(cdpDatabase.dai(ali),      fxp45Int(0.05 ether));
    }
}
