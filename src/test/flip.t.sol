pragma solidity >=0.5.0;

import "ds-test/test.sol";
import {DSToken} from "ds-token/token.sol";

import {cdpDatabase}     from "../cdpDatabase.sol";
import {CollateralForDaiAuction} from "../collateralForDaiAuction.sol";

contract Hevm {
    function warp(uint256) public;
}

contract addr {
    CollateralForDaiAuction collateralForDaiAuction;
    constructor(CollateralForDaiAuction CollateralForDaiAuction_) public {
        collateralForDaiAuction = CollateralForDaiAuction_;
    }
    function hope(address usr) public {
        cdpDatabase(address(collateralForDaiAuction.cdpDatabase())).hope(usr);
    }
    function makeBidIncreaseBidSize(uint id, uint lot, uint bid) public {
        collateralForDaiAuction.makeBidIncreaseBidSize(id, lot, bid);
    }
    function makeBidDecreaseLotSize(uint id, uint lot, uint bid) public {
        collateralForDaiAuction.makeBidDecreaseLotSize(id, lot, bid);
    }
    function claimWinningBid(uint id) public {
        collateralForDaiAuction.claimWinningBid(id);
    }
    function try_makeBidIncreaseBidSize(uint id, uint lot, uint bid)
        public returns (bool ok)
    {
        string memory sig = "makeBidIncreaseBidSize(uint256,uint256,uint256)";
        (ok,) = address(collateralForDaiAuction).call(abi.encodeWithSignature(sig, id, lot, bid));
    }
    function try_makeBidDecreaseLotSize(uint id, uint lot, uint bid)
        public returns (bool ok)
    {
        string memory sig = "makeBidDecreaseLotSize(uint256,uint256,uint256)";
        (ok,) = address(collateralForDaiAuction).call(abi.encodeWithSignature(sig, id, lot, bid));
    }
    function try_claimWinningBid(uint id)
        public returns (bool ok)
    {
        string memory sig = "claimWinningBid(uint256)";
        (ok,) = address(collateralForDaiAuction).call(abi.encodeWithSignature(sig, id));
    }
    function try_restartAuction(uint id)
        public returns (bool ok)
    {
        string memory sig = "restartAuction(uint256)";
        (ok,) = address(collateralForDaiAuction).call(abi.encodeWithSignature(sig, id));
    }
}


contract Gal {}

contract Vat_ is cdpDatabase {
    function mint(address usr, uint fxp18Int) public {
        dai[usr] += fxp18Int;
    }
    function dai_balance(address usr) public view returns (uint) {
        return dai[usr];
    }
    bytes32 collateralType;
    function set_collateralType(bytes32 collateralType_) public {
        collateralType = collateralType_;
    }
    function collateralTokens_balance(address usr) public view returns (uint) {
        return collateralTokens[collateralType][usr];
    }
}

contract CollateralForDaiAuctionTest is DSTest {
    Hevm hevm;

    Vat_    cdpDatabase;
    CollateralForDaiAuction collateralForDaiAuction;

    address ali;
    address bob;
    address gal;
    address cdp = address(0xacab);

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(1 hours);

        cdpDatabase = new Vat_();

        cdpDatabase.createNewCollateralType("collateralTokenss");
        cdpDatabase.set_collateralType("collateralTokenss");

        collateralForDaiAuction = new CollateralForDaiAuction(address(cdpDatabase), "collateralTokenss");

        ali = address(new addr(collateralForDaiAuction));
        bob = address(new addr(collateralForDaiAuction));
        gal = address(new Gal());

        addr(ali).hope(address(collateralForDaiAuction));
        addr(bob).hope(address(collateralForDaiAuction));
        cdpDatabase.hope(address(collateralForDaiAuction));

        cdpDatabase.modifyUsersCollateralBalance("collateralTokenss", address(this), 1000 ether);
        cdpDatabase.mint(ali, 200 ether);
        cdpDatabase.mint(bob, 200 ether);
    }
    function test_startAuction() public {
        collateralForDaiAuction.startAuction({ lot: 100 ether
                  , debtPlusStabilityFee: 50 ether
                  , cdp: cdp
                  , gal: gal
                  , bid: 0
                  });
    }
    function testFail_makeBidIncreaseBidSize_empty() public {
        // can't makeBidIncreaseBidSize on non-existent
        collateralForDaiAuction.makeBidIncreaseBidSize(42, 0, 0);
    }
    function test_makeBidIncreaseBidSize() public {
        uint id = collateralForDaiAuction.startAuction({ lot: 100 ether
                            , debtPlusStabilityFee: 50 ether
                            , cdp: cdp
                            , gal: gal
                            , bid: 0
                            });

        addr(ali).makeBidIncreaseBidSize(id, 100 ether, 1 ether);
        // bid taken from bidder
        assertEq(cdpDatabase.dai_balance(ali),   199 ether);
        // gal receives payment
        assertEq(cdpDatabase.dai_balance(gal),     1 ether);

        addr(bob).makeBidIncreaseBidSize(id, 100 ether, 2 ether);
        // bid taken from bidder
        assertEq(cdpDatabase.dai_balance(bob), 198 ether);
        // prev bidder refunded
        assertEq(cdpDatabase.dai_balance(ali), 200 ether);
        // gal receives excess
        assertEq(cdpDatabase.dai_balance(gal),   2 ether);

        hevm.warp(5 hours);
        addr(bob).claimWinningBid(id);
        // bob gets the winnings
        assertEq(cdpDatabase.collateralTokens_balance(bob), 100 ether);
    }
    function test_makeBidIncreaseBidSize_later() public {
        uint id = collateralForDaiAuction.startAuction({ lot: 100 ether
                            , debtPlusStabilityFee: 50 ether
                            , cdp: cdp
                            , gal: gal
                            , bid: 0
                            });
        hevm.warp(5 hours);

        addr(ali).makeBidIncreaseBidSize(id, 100 ether, 1 ether);
        // bid taken from bidder
        assertEq(cdpDatabase.dai_balance(ali), 199 ether);
        // gal receives payment
        assertEq(cdpDatabase.dai_balance(gal),   1 ether);
    }
    function test_makeBidDecreaseLotSize() public {
        uint id = collateralForDaiAuction.startAuction({ lot: 100 ether
                            , debtPlusStabilityFee: 50 ether
                            , cdp: cdp
                            , gal: gal
                            , bid: 0
                            });
        addr(ali).makeBidIncreaseBidSize(id, 100 ether,  1 ether);
        addr(bob).makeBidIncreaseBidSize(id, 100 ether, 50 ether);

        addr(ali).makeBidDecreaseLotSize(id,  95 ether, 50 ether);
        // plop the collateralTokenss
        assertEq(cdpDatabase.collateralTokens_balance(address(0xacab)), 5 ether);
        assertEq(cdpDatabase.dai_balance(ali),  150 ether);
        assertEq(cdpDatabase.dai_balance(bob),  200 ether);
    }
    function test_beg() public {
        uint id = collateralForDaiAuction.startAuction({ lot: 100 ether
                            , debtPlusStabilityFee: 50 ether
                            , cdp: cdp
                            , gal: gal
                            , bid: 0
                            });
        assertTrue( addr(ali).try_makeBidIncreaseBidSize(id, 100 ether, 1.00 ether));
        assertTrue(!addr(bob).try_makeBidIncreaseBidSize(id, 100 ether, 1.01 ether));
        // high bidder is subject to beg
        assertTrue(!addr(ali).try_makeBidIncreaseBidSize(id, 100 ether, 1.01 ether));
        assertTrue( addr(bob).try_makeBidIncreaseBidSize(id, 100 ether, 1.07 ether));

        // can bid by less than beg at collateralForDaiAuction
        assertTrue( addr(ali).try_makeBidIncreaseBidSize(id, 100 ether, 49 ether));
        assertTrue( addr(bob).try_makeBidIncreaseBidSize(id, 100 ether, 50 ether));

        assertTrue(!addr(ali).try_makeBidDecreaseLotSize(id, 100 ether, 50 ether));
        assertTrue(!addr(ali).try_makeBidDecreaseLotSize(id,  99 ether, 50 ether));
        assertTrue( addr(ali).try_makeBidDecreaseLotSize(id,  95 ether, 50 ether));
    }
    function test_claimWinningBid() public {
        uint id = collateralForDaiAuction.startAuction({ lot: 100 ether
                            , debtPlusStabilityFee: 50 ether
                            , cdp: cdp
                            , gal: gal
                            , bid: 0
                            });

        // only after ttl
        addr(ali).makeBidIncreaseBidSize(id, 100 ether, 1 ether);
        assertTrue(!addr(bob).try_claimWinningBid(id));
        hevm.warp(4.1 hours);
        assertTrue( addr(bob).try_claimWinningBid(id));

        uint ie = collateralForDaiAuction.startAuction({ lot: 100 ether
                            , debtPlusStabilityFee: 50 ether
                            , cdp: cdp
                            , gal: gal
                            , bid: 0
                            });

        // or after end
        hevm.warp(2 days);
        addr(ali).makeBidIncreaseBidSize(ie, 100 ether, 1 ether);
        assertTrue(!addr(bob).try_claimWinningBid(ie));
        hevm.warp(3 days);
        assertTrue( addr(bob).try_claimWinningBid(ie));
    }
    function test_restartAuction() public {
        // start an auction
        uint id = collateralForDaiAuction.startAuction({ lot: 100 ether
                            , debtPlusStabilityFee: 50 ether
                            , cdp: cdp
                            , gal: gal
                            , bid: 0
                            });
        // check no restartAuction
        assertTrue(!addr(ali).try_restartAuction(id));
        // run past the end
        hevm.warp(2 weeks);
        // check not biddable
        assertTrue(!addr(ali).try_makeBidIncreaseBidSize(id, 100 ether, 1 ether));
        assertTrue( addr(ali).try_restartAuction(id));
        // check biddable
        assertTrue( addr(ali).try_makeBidIncreaseBidSize(id, 100 ether, 1 ether));
    }
    function test_no_claimWinningBid_after_end() public {
        // if there are no bids and the auction ends, then it should not
        // be refundable to the creator. Rather, it restartAuctions indefinitely.
        uint id = collateralForDaiAuction.startAuction({ lot: 100 ether
                            , debtPlusStabilityFee: 50 ether
                            , cdp: cdp
                            , gal: gal
                            , bid: 0
                            });
        assertTrue(!addr(ali).try_claimWinningBid(id));
        hevm.warp(2 weeks);
        assertTrue(!addr(ali).try_claimWinningBid(id));
        assertTrue( addr(ali).try_restartAuction(id));
        assertTrue(!addr(ali).try_claimWinningBid(id));
    }
}
