/// addCollateral.sol -- Basic token adapters

// Copyright (C) 2018 Rain <rainbreak@riseup.net>
//
// This program is transferCollateralFromCDP software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the transferCollateralFromCDP Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity >=0.5.0;

import "./lib.sol";

contract collateralTokensLike {
    function transfer(address,uint) public returns (bool);
    function transferFrom(address,address,uint) public returns (bool);
}

contract DSTokenLike {
    function mint(address,uint) public;
    function burn(address,uint) public;
}

contract cdpDatabaseInterface {
    function modifyUsersCollateralBalance(bytes32,address,int) public;
    function move(address,address,uint) public;
    function transferCollateral(bytes32,address,address,uint) public;
}

/*
    Here we provide *adapters* to connect the cdpDatabase to arbitrary external
    token implementations, creating a bounded context for the cdpDatabase. The
    adapters here are provided as working examples:

      - `collateralTokensAddCollateral`: For well behaved ERC20 tokens, with simple transfer
                   semantics.

      - `ETHAddCollateral`: For native Ether.

      - `DaiAddCollateral`: For connecting internal Dai balances to an external
                   `DSToken` implementation.

    In practice, adapter implementations will be varied and specific to
    individual collateral types, accounting for different transfer
    semantics and token standards.

    Adapters need to implement two basic methods:

      - `addCollateral`: enter collateral into the system
      - `removeCollateral`: remove collateral from the system

*/

contract collateralTokensAddCollateral is DSNote {
    cdpDatabaseInterface public cdpDatabase;
    bytes32 public collateralType;
    collateralTokensLike public collateralTokens;
    constructor(address vat_, bytes32 collateralType_, address collateralTokens_) public {
        cdpDatabase = cdpDatabaseInterface(vat_);
        collateralType = collateralType_;
        collateralTokens = collateralTokensLike(collateralTokens_);
    }
    function addCollateral(address cdp, uint fxp18Int) public note {
        require(int(fxp18Int) >= 0);
        cdpDatabase.modifyUsersCollateralBalance(collateralType, cdp, int(fxp18Int));
        require(collateralTokens.transferFrom(msg.sender, address(this), fxp18Int));
    }
    function removeCollateral(address usr, uint fxp18Int) public note {
        address cdp = msg.sender;
        require(int(fxp18Int) >= 0);
        cdpDatabase.modifyUsersCollateralBalance(collateralType, cdp, -int(fxp18Int));
        require(collateralTokens.transfer(usr, fxp18Int));
    }
}

contract ETHAddCollateral is DSNote {
    cdpDatabaseInterface public cdpDatabase;
    bytes32 public collateralType;
    constructor(address vat_, bytes32 collateralType_) public {
        cdpDatabase = cdpDatabaseInterface(vat_);
        collateralType = collateralType_;
    }
    function addCollateral(address cdp) public payable note {
        require(int(msg.value) >= 0);
        cdpDatabase.modifyUsersCollateralBalance(collateralType, cdp, int(msg.value));
    }
    function removeCollateral(address payable usr, uint fxp18Int) public note {
        address cdp = msg.sender;
        require(int(fxp18Int) >= 0);
        cdpDatabase.modifyUsersCollateralBalance(collateralType, cdp, -int(fxp18Int));
        usr.transfer(fxp18Int);
    }
}

contract DaiAddCollateral is DSNote {
    cdpDatabaseInterface public cdpDatabase;
    DSTokenLike public dai;
    constructor(address vat_, address dai_) public {
        cdpDatabase = cdpDatabaseInterface(vat_);
        dai = DSTokenLike(dai_);
    }
    uint constant ONE = 10 ** 27;
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function addCollateral(address cdp, uint fxp18Int) public note {
        cdpDatabase.move(address(this), cdp, mul(ONE, fxp18Int));
        dai.burn(msg.sender, fxp18Int);
    }
    function removeCollateral(address usr, uint fxp18Int) public note {
        address cdp = msg.sender;
        cdpDatabase.move(cdp, address(this), mul(ONE, fxp18Int));
        dai.mint(usr, fxp18Int);
    }
}
