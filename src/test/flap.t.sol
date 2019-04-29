pragma solidity >=0.5.0;

import "ds-test/test.sol";
import {DSToken} from "ds-token/token.sol";

import {DaiForMkrSurplusAuction} from "../DaiForMkrSurplusAuction.sol";


contract Hevm {
    function warp(uint256) public;
}

contract addr {
    DaiForMkrSurplusAuction auction;
    constructor(DaiForMkrSurplusAuction fuss_) public {
        auction = fuss_;
        DSToken(address(auction.dai())).approve(address(auction));
        DSToken(address(auction.collateralTokens())).approve(address(auction));
    }
    function makeBidIncreaseBidSize(uint id, uint lot, uint bid) public {
        auction.makeBidIncreaseBidSize(id, lot, bid);
    }
    function claimWinningBid(uint id) public {
        auction.claimWinningBid(id);
    }
    function try_makeBidIncreaseBidSize(uint id, uint lot, uint bid)
        public returns (bool ok)
    {
        string memory sig = "makeBidIncreaseBidSize(uint256,uint256,uint256)";
        (ok,) = address(auction).call(abi.encodeWithSignature(sig, id, lot, bid));
    }
    function try_claimWinningBid(uint id)
        public returns (bool ok)
    {
        string memory sig = "claimWinningBid(uint256)";
        (ok,) = address(auction).call(abi.encodeWithSignature(sig, id));
    }
}

contract Gal {}

contract cdpDatabaseInterface is DSToken('') {
    uint constant ONE = 10 ** 27;
    function move(address src, address dst, uint fxp45Int) public {
        super.move(src, dst, fxp45Int);
    }
}

contract DaiForMkrSurplusAuctionTest is DSTest {
    Hevm hevm;

    DaiForMkrSurplusAuction auction;
    cdpDatabaseInterface dai;
    DSToken collateralTokens;

    address ali;
    address bob;
    address gal;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(1 hours);

        dai = new cdpDatabaseInterface();
        collateralTokens = new DSToken('');

        auction = new DaiForMkrSurplusAuction(address(dai), address(collateralTokens));

        ali = address(new addr(auction));
        bob = address(new addr(auction));
        gal = address(new Gal());

        dai.approve(address(auction));
        collateralTokens.approve(address(auction));

        dai.mint(1000 ether);
        collateralTokens.mint(1000 ether);

        collateralTokens.push(ali, 200 ether);
        collateralTokens.push(bob, 200 ether);
    }
    function test_startAuction() public {
        assertEq(dai.balanceOf(address(this)), 1000 ether);
        assertEq(dai.balanceOf(address(auction)),    0 ether);
        auction.startAuction({ lot: 100 ether
                  , gal: gal
                  , bid: 0
                  });
        assertEq(dai.balanceOf(address(this)),  900 ether);
        assertEq(dai.balanceOf(address(auction)),  100 ether);
    }
    function test_makeBidIncreaseBidSize() public {
        uint id = auction.startAuction({ lot: 100 ether
                            , gal: gal
                            , bid: 0
                            });
        // lot taken from creator
        assertEq(dai.balanceOf(address(this)), 900 ether);

        addr(ali).makeBidIncreaseBidSize(id, 100 ether, 1 ether);
        // bid taken from bidder
        assertEq(collateralTokens.balanceOf(ali), 199 ether);
        // gal receives payment
        assertEq(collateralTokens.balanceOf(gal),   1 ether);

        addr(bob).makeBidIncreaseBidSize(id, 100 ether, 2 ether);
        // bid taken from bidder
        assertEq(collateralTokens.balanceOf(bob), 198 ether);
        // prev bidder refunded
        assertEq(collateralTokens.balanceOf(ali), 200 ether);
        // gal receives excess
        assertEq(collateralTokens.balanceOf(gal),   2 ether);

        hevm.warp(5 weeks);
        addr(bob).claimWinningBid(id);
        // bob gets the winnings
        assertEq(dai.balanceOf(address(auction)),  0 ether);
        assertEq(dai.balanceOf(bob), 100 ether);
    }
    function test_beg() public {
        uint id = auction.startAuction({ lot: 100 ether
                            , gal: gal
                            , bid: 0
                            });
        assertTrue( addr(ali).try_makeBidIncreaseBidSize(id, 100 ether, 1.00 ether));
        assertTrue(!addr(bob).try_makeBidIncreaseBidSize(id, 100 ether, 1.01 ether));
        // high bidder is subject to beg
        assertTrue(!addr(ali).try_makeBidIncreaseBidSize(id, 100 ether, 1.01 ether));
        assertTrue( addr(bob).try_makeBidIncreaseBidSize(id, 100 ether, 1.07 ether));
    }
}
