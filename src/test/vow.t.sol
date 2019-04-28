pragma solidity >=0.5.0;

import "ds-test/test.sol";

import {MkrForDaiDebtAuction} from './flop.t.sol';
import {DaiForMkrSurplusAuction} from './flap.t.sol';
import {TestVat as  Vat} from './vat.t.sol';
import {Vow}     from '../vow.sol';

contract Hevm {
    function warp(uint256) public;
}

contract Gem {
    mapping (address => uint256) public balanceOf;
    function mint(address usr, uint rad) public {
        balanceOf[usr] += rad;
    }
}

contract VowTest is DSTest {
    Hevm hevm;

    Vat  vat;
    Vow  vow;
    MkrForDaiDebtAuction mkrForDaiDebtAuction;
    DaiForMkrSurplusAuction daiForMkrSurplusAuction;
    Gem  gov;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(0);

        vat = new Vat();
        vow = new Vow();
        vat.rely(address(vow));
        gov  = new Gem();

        mkrForDaiDebtAuction = new MkrForDaiDebtAuction(address(vat), address(gov));
        daiForMkrSurplusAuction = new DaiForMkrSurplusAuction(address(vat), address(gov));
        vat.hope(address(mkrForDaiDebtAuction));
        vat.rely(address(mkrForDaiDebtAuction));
        vat.rely(address(daiForMkrSurplusAuction));
        mkrForDaiDebtAuction.rely(address(vow));

        vow.file("vat",  address(vat));
        vow.file("mkrForDaiDebtAuction", address(mkrForDaiDebtAuction));
        vow.file("daiForMkrSurplusAuction", address(daiForMkrSurplusAuction));
        vow.file("surplusAuctionLotSize", rad(100 ether));
        vow.file("debtAuctionLotSize", rad(100 ether));
    }

    function try_removeDebtFromDebtQueue(uint48 era) internal returns (bool ok) {
        string memory sig = "removeDebtFromDebtQueue(uint48)";
        (ok,) = address(vow).call(abi.encodeWithSignature(sig, era));
    }
    function try_mkrForDaiDebtAuction() internal returns (bool ok) {
        string memory sig = "mkrForDaiDebtAuction()";
        (ok,) = address(vow).call(abi.encodeWithSignature(sig));
    }
    function try_daiForMkrSurplusAuction() internal returns (bool ok) {
        string memory sig = "daiForMkrSurplusAuction()";
        (ok,) = address(vow).call(abi.encodeWithSignature(sig));
    }
    function try_makeBidDecreaseLotSize(uint id, uint lot, uint bid) internal returns (bool ok) {
        string memory sig = "makeBidDecreaseLotSize(uint256,uint256,uint256)";
        (ok,) = address(mkrForDaiDebtAuction).call(abi.encodeWithSignature(sig, id, lot, bid));
    }

    uint constant ONE = 10 ** 27;
    function rad(uint wad) internal pure returns (uint) {
        return wad * ONE;
    }

    function suck(address who, uint wad) internal {
        vow.addDebtToDebtQueue(rad(wad));
        vat.init('');
        vat.settleDebtUsingSurplus(address(vow), who, -int(rad(wad)));
    }
    function removeDebtFromDebtQueue(uint wad) internal {
        suck(address(0), wad);  // suck dai into the zero address
        vow.removeDebtFromDebtQueue(uint48(now));
    }
    function settleDebtUsingSurplus(uint wad) internal {
        vow.settleDebtUsingSurplus(rad(wad));
    }

    function test_removeDebtFromDebtQueue_debtQueueLength() public {
        assertEq(vow.debtQueueLength(), 0);
        vow.file('debtQueueLength', uint(100 seconds));
        assertEq(vow.debtQueueLength(), 100 seconds);

        uint48 tic = uint48(now);
        vow.addDebtToDebtQueue(100 ether);
        assertTrue(!try_removeDebtFromDebtQueue(tic) );
        hevm.warp(tic + uint48(100 seconds));
        assertTrue( try_removeDebtFromDebtQueue(tic) );
    }

    function test_no_remkrForDaiDebtAuction() public {
        removeDebtFromDebtQueue(100 ether);
        assertTrue( try_mkrForDaiDebtAuction() );
        assertTrue(!try_mkrForDaiDebtAuction() );
    }

    function test_no_mkrForDaiDebtAuction_pending_joy() public {
        removeDebtFromDebtQueue(200 ether);

        vat.mint(address(vow), 100 ether);
        assertTrue(!try_mkrForDaiDebtAuction() );

        settleDebtUsingSurplus(100 ether);
        assertTrue( try_mkrForDaiDebtAuction() );
    }

    function test_daiForMkrSurplusAuction() public {
        vat.mint(address(vow), 100 ether);
        assertTrue( try_daiForMkrSurplusAuction() );
    }

    function test_no_daiForMkrSurplusAuction_pending_sin() public {
        vow.file("surplusAuctionLotSize", uint256(0 ether));
        removeDebtFromDebtQueue(100 ether);

        vat.mint(address(vow), 50 ether);
        assertTrue(!try_daiForMkrSurplusAuction() );
    }
    function test_no_daiForMkrSurplusAuction_nonzero_woe() public {
        vow.file("surplusAuctionLotSize", uint256(0 ether));
        removeDebtFromDebtQueue(100 ether);
        vat.mint(address(vow), 50 ether);
        assertTrue(!try_daiForMkrSurplusAuction() );
    }
    function test_no_daiForMkrSurplusAuction_pending_mkrForDaiDebtAuction() public {
        removeDebtFromDebtQueue(100 ether);
        vow.mkrForDaiDebtAuction();

        vat.mint(address(vow), 100 ether);

        assertTrue(!try_daiForMkrSurplusAuction() );
    }
    function test_no_daiForMkrSurplusAuction_pending_settleOnAuctionDebtUsingSurplus() public {
        removeDebtFromDebtQueue(100 ether);
        uint id = vow.mkrForDaiDebtAuction();

        vat.mint(address(this), 100 ether);
        mkrForDaiDebtAuction.makeBidDecreaseLotSize(id, 0 ether, rad(100 ether));

        assertTrue(!try_mkrForDaiDebtAuction() );
    }

    function test_no_surplus_after_good_mkrForDaiDebtAuction() public {
        removeDebtFromDebtQueue(100 ether);
        uint id = vow.mkrForDaiDebtAuction();
        vat.mint(address(this), 100 ether);

        mkrForDaiDebtAuction.makeBidDecreaseLotSize(id, 0 ether, rad(100 ether));  // mkrForDaiDebtAuction succeeds..

        assertTrue(!try_mkrForDaiDebtAuction() );
    }

    function test_multiple_mkrForDaiDebtAuction_makeBidDecreaseLotSizes() public {
        removeDebtFromDebtQueue(100 ether);
        uint id = vow.mkrForDaiDebtAuction();

        vat.mint(address(this), 100 ether);
        assertTrue(try_makeBidDecreaseLotSize(id, 2 ether,  rad(100 ether)));

        vat.mint(address(this), 100 ether);
        assertTrue(try_makeBidDecreaseLotSize(id, 1 ether,  rad(100 ether)));
    }
}
