pragma solidity >=0.5.0;

import "ds-test/test.sol";

import {MkrForDaiDebtAuction} from './MkrForDaiDebtAuction.t.sol';
import {DaiForMkrSurplusAuction} from './DaiForMkrSurplusAuction.t.sol';
import {TestVat as  cdpDatabase} from './cdpDatabase.t.sol';
import {Settlement}     from '../Settlement.sol';

contract Hevm {
    function warp(uint256) public;
}

contract collateralTokens {
    mapping (address => uint256) public balanceOf;
    function mint(address usr, uint fxp45Int) public {
        balanceOf[usr] += fxp45Int;
    }
}

contract VowTest is DSTest {
    Hevm hevm;

    cdpDatabase  cdpDatabase;
    Settlement  Settlement;
    MkrForDaiDebtAuction mkrForDaiDebtAuction;
    DaiForMkrSurplusAuction daiForMkrSurplusAuction;
    collateralTokens  gov;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(0);

        cdpDatabase = new cdpDatabase();
        Settlement = new Settlement();
        cdpDatabase.authorizeAddress(address(Settlement));
        gov  = new collateralTokens();

        mkrForDaiDebtAuction = new MkrForDaiDebtAuction(address(cdpDatabase), address(gov));
        daiForMkrSurplusAuction = new DaiForMkrSurplusAuction(address(cdpDatabase), address(gov));
        cdpDatabase.hope(address(mkrForDaiDebtAuction));
        cdpDatabase.authorizeAddress(address(mkrForDaiDebtAuction));
        cdpDatabase.authorizeAddress(address(daiForMkrSurplusAuction));
        mkrForDaiDebtAuction.authorizeAddress(address(Settlement));

        Settlement.changeConfig("cdpDatabase",  address(cdpDatabase));
        Settlement.changeConfig("mkrForDaiDebtAuction", address(mkrForDaiDebtAuction));
        Settlement.changeConfig("daiForMkrSurplusAuction", address(daiForMkrSurplusAuction));
        Settlement.changeConfig("surplusAuctionLotSize", fxp45Int(100 ether));
        Settlement.changeConfig("debtAuctionLotSize", fxp45Int(100 ether));
    }

    function try_removeDebtFromDebtQueue(uint48 era) internal returns (bool ok) {
        string memory sig = "removeDebtFromDebtQueue(uint48)";
        (ok,) = address(Settlement).call(abi.encodeWithSignature(sig, era));
    }
    function try_mkrForDaiDebtAuction() internal returns (bool ok) {
        string memory sig = "mkrForDaiDebtAuction()";
        (ok,) = address(Settlement).call(abi.encodeWithSignature(sig));
    }
    function try_daiForMkrSurplusAuction() internal returns (bool ok) {
        string memory sig = "daiForMkrSurplusAuction()";
        (ok,) = address(Settlement).call(abi.encodeWithSignature(sig));
    }
    function try_makeBidDecreaseLotSize(uint id, uint lot, uint bid) internal returns (bool ok) {
        string memory sig = "makeBidDecreaseLotSize(uint256,uint256,uint256)";
        (ok,) = address(mkrForDaiDebtAuction).call(abi.encodeWithSignature(sig, id, lot, bid));
    }

    uint constant ONE = 10 ** 27;
    function fxp45Int(uint fxp18Int) internal pure returns (uint) {
        return fxp18Int * ONE;
    }

    function suck(address who, uint fxp18Int) internal {
        Settlement.addDebtToDebtQueue(fxp45Int(fxp18Int));
        cdpDatabase.createNewCollateralType('');
        cdpDatabase.settleDebtUsingSurplus(address(Settlement), who, -int(fxp45Int(fxp18Int)));
    }
    function removeDebtFromDebtQueue(uint fxp18Int) internal {
        suck(address(0), fxp18Int);  // suck dai into the zero address
        Settlement.removeDebtFromDebtQueue(uint48(now));
    }
    function settleDebtUsingSurplus(uint fxp18Int) internal {
        Settlement.settleDebtUsingSurplus(fxp45Int(fxp18Int));
    }

    function test_removeDebtFromDebtQueue_debtQueueLength() public {
        assertEq(Settlement.debtQueueLength(), 0);
        Settlement.changeConfig('debtQueueLength', uint(100 seconds));
        assertEq(Settlement.debtQueueLength(), 100 seconds);

        uint48 expiryTime = uint48(now);
        Settlement.addDebtToDebtQueue(100 ether);
        assertTrue(!try_removeDebtFromDebtQueue(expiryTime) );
        hevm.warp(expiryTime + uint48(100 seconds));
        assertTrue( try_removeDebtFromDebtQueue(expiryTime) );
    }

    function test_no_remkrForDaiDebtAuction() public {
        removeDebtFromDebtQueue(100 ether);
        assertTrue( try_mkrForDaiDebtAuction() );
        assertTrue(!try_mkrForDaiDebtAuction() );
    }

    function test_no_mkrForDaiDebtAuction_pending_joy() public {
        removeDebtFromDebtQueue(200 ether);

        cdpDatabase.mint(address(Settlement), 100 ether);
        assertTrue(!try_mkrForDaiDebtAuction() );

        settleDebtUsingSurplus(100 ether);
        assertTrue( try_mkrForDaiDebtAuction() );
    }

    function test_daiForMkrSurplusAuction() public {
        cdpDatabase.mint(address(Settlement), 100 ether);
        assertTrue( try_daiForMkrSurplusAuction() );
    }

    function test_no_daiForMkrSurplusAuction_pending_sin() public {
        Settlement.changeConfig("surplusAuctionLotSize", uint256(0 ether));
        removeDebtFromDebtQueue(100 ether);

        cdpDatabase.mint(address(Settlement), 50 ether);
        assertTrue(!try_daiForMkrSurplusAuction() );
    }
    function test_no_daiForMkrSurplusAuction_nonzero_woe() public {
        Settlement.changeConfig("surplusAuctionLotSize", uint256(0 ether));
        removeDebtFromDebtQueue(100 ether);
        cdpDatabase.mint(address(Settlement), 50 ether);
        assertTrue(!try_daiForMkrSurplusAuction() );
    }
    function test_no_daiForMkrSurplusAuction_pending_mkrForDaiDebtAuction() public {
        removeDebtFromDebtQueue(100 ether);
        Settlement.mkrForDaiDebtAuction();

        cdpDatabase.mint(address(Settlement), 100 ether);

        assertTrue(!try_daiForMkrSurplusAuction() );
    }
    function test_no_daiForMkrSurplusAuction_pending_settleOnAuctionDebtUsingSurplus() public {
        removeDebtFromDebtQueue(100 ether);
        uint id = Settlement.mkrForDaiDebtAuction();

        cdpDatabase.mint(address(this), 100 ether);
        mkrForDaiDebtAuction.makeBidDecreaseLotSize(id, 0 ether, fxp45Int(100 ether));

        assertTrue(!try_mkrForDaiDebtAuction() );
    }

    function test_no_surplus_after_good_mkrForDaiDebtAuction() public {
        removeDebtFromDebtQueue(100 ether);
        uint id = Settlement.mkrForDaiDebtAuction();
        cdpDatabase.mint(address(this), 100 ether);

        mkrForDaiDebtAuction.makeBidDecreaseLotSize(id, 0 ether, fxp45Int(100 ether));  // mkrForDaiDebtAuction succeeds..

        assertTrue(!try_mkrForDaiDebtAuction() );
    }

    function test_multiple_mkrForDaiDebtAuction_makeBidDecreaseLotSizes() public {
        removeDebtFromDebtQueue(100 ether);
        uint id = Settlement.mkrForDaiDebtAuction();

        cdpDatabase.mint(address(this), 100 ether);
        assertTrue(try_makeBidDecreaseLotSize(id, 2 ether,  fxp45Int(100 ether)));

        cdpDatabase.mint(address(this), 100 ether);
        assertTrue(try_makeBidDecreaseLotSize(id, 1 ether,  fxp45Int(100 ether)));
    }
}
