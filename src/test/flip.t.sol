pragma solidity >=0.5.0;

import "ds-test/test.sol";
import {DSToken} from "ds-token/token.sol";

import {Vat}     from "../vat.sol";
import {CollateralForDaiAuction} from "../flip.sol";

contract Hevm {
    function warp(uint256) public;
}

contract Guy {
    CollateralForDaiAuction flip;
    constructor(CollateralForDaiAuction flip_) public {
        flip = flip_;
    }
    function hope(address usr) public {
        Vat(address(flip.vat())).hope(usr);
    }
    function makeBidIncreaseBidSize(uint id, uint lot, uint bid) public {
        flip.makeBidIncreaseBidSize(id, lot, bid);
    }
    function makeBidDecreaseLotSize(uint id, uint lot, uint bid) public {
        flip.makeBidDecreaseLotSize(id, lot, bid);
    }
    function claimWinningBid(uint id) public {
        flip.claimWinningBid(id);
    }
    function try_makeBidIncreaseBidSize(uint id, uint lot, uint bid)
        public returns (bool ok)
    {
        string memory sig = "makeBidIncreaseBidSize(uint256,uint256,uint256)";
        (ok,) = address(flip).call(abi.encodeWithSignature(sig, id, lot, bid));
    }
    function try_makeBidDecreaseLotSize(uint id, uint lot, uint bid)
        public returns (bool ok)
    {
        string memory sig = "makeBidDecreaseLotSize(uint256,uint256,uint256)";
        (ok,) = address(flip).call(abi.encodeWithSignature(sig, id, lot, bid));
    }
    function try_claimWinningBid(uint id)
        public returns (bool ok)
    {
        string memory sig = "claimWinningBid(uint256)";
        (ok,) = address(flip).call(abi.encodeWithSignature(sig, id));
    }
    function try_restartAuction(uint id)
        public returns (bool ok)
    {
        string memory sig = "restartAuction(uint256)";
        (ok,) = address(flip).call(abi.encodeWithSignature(sig, id));
    }
}


contract Gal {}

contract Vat_ is Vat {
    function mint(address usr, uint wad) public {
        dai[usr] += wad;
    }
    function dai_balance(address usr) public view returns (uint) {
        return dai[usr];
    }
    bytes32 ilk;
    function set_ilk(bytes32 ilk_) public {
        ilk = ilk_;
    }
    function gem_balance(address usr) public view returns (uint) {
        return gem[ilk][usr];
    }
}

contract FlipTest is DSTest {
    Hevm hevm;

    Vat_    vat;
    CollateralForDaiAuction flip;

    address ali;
    address bob;
    address gal;
    address urn = address(0xacab);

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(1 hours);

        vat = new Vat_();

        vat.init("gems");
        vat.set_ilk("gems");

        flip = new CollateralForDaiAuction(address(vat), "gems");

        ali = address(new Guy(flip));
        bob = address(new Guy(flip));
        gal = address(new Gal());

        Guy(ali).hope(address(flip));
        Guy(bob).hope(address(flip));
        vat.hope(address(flip));

        vat.slip("gems", address(this), 1000 ether);
        vat.mint(ali, 200 ether);
        vat.mint(bob, 200 ether);
    }
    function test_startAuction() public {
        flip.startAuction({ lot: 100 ether
                  , tab: 50 ether
                  , urn: urn
                  , gal: gal
                  , bid: 0
                  });
    }
    function testFail_makeBidIncreaseBidSize_empty() public {
        // can't makeBidIncreaseBidSize on non-existent
        flip.makeBidIncreaseBidSize(42, 0, 0);
    }
    function test_makeBidIncreaseBidSize() public {
        uint id = flip.startAuction({ lot: 100 ether
                            , tab: 50 ether
                            , urn: urn
                            , gal: gal
                            , bid: 0
                            });

        Guy(ali).makeBidIncreaseBidSize(id, 100 ether, 1 ether);
        // bid taken from bidder
        assertEq(vat.dai_balance(ali),   199 ether);
        // gal receives payment
        assertEq(vat.dai_balance(gal),     1 ether);

        Guy(bob).makeBidIncreaseBidSize(id, 100 ether, 2 ether);
        // bid taken from bidder
        assertEq(vat.dai_balance(bob), 198 ether);
        // prev bidder refunded
        assertEq(vat.dai_balance(ali), 200 ether);
        // gal receives excess
        assertEq(vat.dai_balance(gal),   2 ether);

        hevm.warp(5 hours);
        Guy(bob).claimWinningBid(id);
        // bob gets the winnings
        assertEq(vat.gem_balance(bob), 100 ether);
    }
    function test_makeBidIncreaseBidSize_later() public {
        uint id = flip.startAuction({ lot: 100 ether
                            , tab: 50 ether
                            , urn: urn
                            , gal: gal
                            , bid: 0
                            });
        hevm.warp(5 hours);

        Guy(ali).makeBidIncreaseBidSize(id, 100 ether, 1 ether);
        // bid taken from bidder
        assertEq(vat.dai_balance(ali), 199 ether);
        // gal receives payment
        assertEq(vat.dai_balance(gal),   1 ether);
    }
    function test_makeBidDecreaseLotSize() public {
        uint id = flip.startAuction({ lot: 100 ether
                            , tab: 50 ether
                            , urn: urn
                            , gal: gal
                            , bid: 0
                            });
        Guy(ali).makeBidIncreaseBidSize(id, 100 ether,  1 ether);
        Guy(bob).makeBidIncreaseBidSize(id, 100 ether, 50 ether);

        Guy(ali).makeBidDecreaseLotSize(id,  95 ether, 50 ether);
        // plop the gems
        assertEq(vat.gem_balance(address(0xacab)), 5 ether);
        assertEq(vat.dai_balance(ali),  150 ether);
        assertEq(vat.dai_balance(bob),  200 ether);
    }
    function test_beg() public {
        uint id = flip.startAuction({ lot: 100 ether
                            , tab: 50 ether
                            , urn: urn
                            , gal: gal
                            , bid: 0
                            });
        assertTrue( Guy(ali).try_makeBidIncreaseBidSize(id, 100 ether, 1.00 ether));
        assertTrue(!Guy(bob).try_makeBidIncreaseBidSize(id, 100 ether, 1.01 ether));
        // high bidder is subject to beg
        assertTrue(!Guy(ali).try_makeBidIncreaseBidSize(id, 100 ether, 1.01 ether));
        assertTrue( Guy(bob).try_makeBidIncreaseBidSize(id, 100 ether, 1.07 ether));

        // can bid by less than beg at flip
        assertTrue( Guy(ali).try_makeBidIncreaseBidSize(id, 100 ether, 49 ether));
        assertTrue( Guy(bob).try_makeBidIncreaseBidSize(id, 100 ether, 50 ether));

        assertTrue(!Guy(ali).try_makeBidDecreaseLotSize(id, 100 ether, 50 ether));
        assertTrue(!Guy(ali).try_makeBidDecreaseLotSize(id,  99 ether, 50 ether));
        assertTrue( Guy(ali).try_makeBidDecreaseLotSize(id,  95 ether, 50 ether));
    }
    function test_claimWinningBid() public {
        uint id = flip.startAuction({ lot: 100 ether
                            , tab: 50 ether
                            , urn: urn
                            , gal: gal
                            , bid: 0
                            });

        // only after ttl
        Guy(ali).makeBidIncreaseBidSize(id, 100 ether, 1 ether);
        assertTrue(!Guy(bob).try_claimWinningBid(id));
        hevm.warp(4.1 hours);
        assertTrue( Guy(bob).try_claimWinningBid(id));

        uint ie = flip.startAuction({ lot: 100 ether
                            , tab: 50 ether
                            , urn: urn
                            , gal: gal
                            , bid: 0
                            });

        // or after end
        hevm.warp(2 days);
        Guy(ali).makeBidIncreaseBidSize(ie, 100 ether, 1 ether);
        assertTrue(!Guy(bob).try_claimWinningBid(ie));
        hevm.warp(3 days);
        assertTrue( Guy(bob).try_claimWinningBid(ie));
    }
    function test_restartAuction() public {
        // start an auction
        uint id = flip.startAuction({ lot: 100 ether
                            , tab: 50 ether
                            , urn: urn
                            , gal: gal
                            , bid: 0
                            });
        // check no restartAuction
        assertTrue(!Guy(ali).try_restartAuction(id));
        // run past the end
        hevm.warp(2 weeks);
        // check not biddable
        assertTrue(!Guy(ali).try_makeBidIncreaseBidSize(id, 100 ether, 1 ether));
        assertTrue( Guy(ali).try_restartAuction(id));
        // check biddable
        assertTrue( Guy(ali).try_makeBidIncreaseBidSize(id, 100 ether, 1 ether));
    }
    function test_no_claimWinningBid_after_end() public {
        // if there are no bids and the auction ends, then it should not
        // be refundable to the creator. Rather, it restartAuctions indefinitely.
        uint id = flip.startAuction({ lot: 100 ether
                            , tab: 50 ether
                            , urn: urn
                            , gal: gal
                            , bid: 0
                            });
        assertTrue(!Guy(ali).try_claimWinningBid(id));
        hevm.warp(2 weeks);
        assertTrue(!Guy(ali).try_claimWinningBid(id));
        assertTrue( Guy(ali).try_restartAuction(id));
        assertTrue(!Guy(ali).try_claimWinningBid(id));
    }
}
