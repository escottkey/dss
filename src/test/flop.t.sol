pragma solidity >=0.5.0;

import {DSTest}  from "ds-test/test.sol";
import {DSToken} from "ds-token/token.sol";

import "../MkrForDaiDebtAuction.sol";


contract Hevm {
    function warp(uint256) public;
}

contract addr {
    MkrForDaiDebtAuction auction;
    constructor(MkrForDaiDebtAuction fuss_) public {
        auction = fuss_;
        DSToken(address(auction.dai())).approve(address(auction));
        DSToken(address(auction.collateralTokens())).approve(address(auction));
    }
    function makeBidDecreaseLotSize(uint id, uint lot, uint bid) public {
        auction.makeBidDecreaseLotSize(id, lot, bid);
    }
    function claimWinningBid(uint id) public {
        auction.claimWinningBid(id);
    }
    function try_makeBidDecreaseLotSize(uint id, uint lot, uint bid)
        public returns (bool ok)
    {
        string memory sig = "makeBidDecreaseLotSize(uint256,uint256,uint256)";
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

contract MkrForDaiDebtAuctionTest is DSTest {
    Hevm hevm;

    MkrForDaiDebtAuction auction;
    cdpDatabaseInterface dai;
    DSToken collateralTokens;

    address ali;
    address bob;
    address gal;

    function settleOnAuctionDebtUsingSurplus(uint) public pure { }  // arbitrary callback

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(1 hours);

        dai = new cdpDatabaseInterface();
        collateralTokens = new DSToken('');

        auction = new MkrForDaiDebtAuction(address(dai), address(collateralTokens));

        ali = address(new addr(auction));
        bob = address(new addr(auction));
        gal = address(new Gal());

        dai.approve(address(auction));
        collateralTokens.approve(address(auction));

        dai.mint(1000 ether);

        dai.push(ali, 200 ether);
        dai.push(bob, 200 ether);
    }
    function test_startAuction() public {
        assertEq(dai.balanceOf(address(this)), 600 ether);
        assertEq(collateralTokens.balanceOf(address(this)),   0 ether);
        auction.startAuction({ lot: uint(-1)   // or whatever high starting value
                  , gal: gal
                  , bid: 0
                  });
        // no value transferred
        assertEq(dai.balanceOf(address(this)), 600 ether);
        assertEq(collateralTokens.balanceOf(address(this)),   0 ether);
    }
    function test_makeBidDecreaseLotSize() public {
        uint id = auction.startAuction({ lot: uint(-1)   // or whatever high starting value
                            , gal: gal
                            , bid: 10 ether
                            });

        addr(ali).makeBidDecreaseLotSize(id, 100 ether, 10 ether);
        // bid taken from bidder
        assertEq(dai.balanceOf(ali), 190 ether);
        // gal receives payment
        assertEq(dai.balanceOf(gal),  10 ether);

        addr(bob).makeBidDecreaseLotSize(id, 80 ether, 10 ether);
        // bid taken from bidder
        assertEq(dai.balanceOf(bob), 190 ether);
        // prev bidder refunded
        assertEq(dai.balanceOf(ali), 200 ether);
        // gal receives no more
        assertEq(dai.balanceOf(gal), 10 ether);

        hevm.warp(5 weeks);
        assertEq(collateralTokens.totalSupply(),  0 ether);
        collateralTokens.setOwner(address(auction));
        addr(bob).claimWinningBid(id);
        // collateralTokenss minted on demand
        assertEq(collateralTokens.totalSupply(), 80 ether);
        // bob gets the winnings
        assertEq(collateralTokens.balanceOf(bob), 80 ether);
    }
}
