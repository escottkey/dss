// Copyright (C) 2017, 2018, 2019 dbrock, rain, mrchico

// Copyright (C) 2018 Rain <rainbreak@riseup.net>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity >=0.4.24;

contract Dai {
    // --- isAuthorized ---
    mapping (address => uint) public authenticatedAddresss;
    function authorizeAddress(address addr) public isAuthorized { authenticatedAddresss[addr] = 1; }
    function deauthorizeAddress(address addr) public isAuthorized { authenticatedAddresss[addr] = 0; }
    modifier isAuthorized { require(authenticatedAddresss[msg.sender] == 1); _; }

    // --- ERC20 Data ---
    uint8   public decimals = 18;
    string  public name;
    string  public symbol;
    string  public version;
    uint256 public totalSupply;

    mapping (address => uint)                      public balanceOf;
    mapping (address => mapping (address => uint)) public allowance;
    mapping (address => uint)                      public nonces;

    event Approval(address indexed src, address indexed addr, uint fxp18Int);
    event Transfer(address indexed src, address indexed dst, uint fxp18Int);

    // --- Math ---
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "math-add-overflow");
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "math-sub-underflow");
    }

    // --- EIP712 niceties ---
    bytes32 public DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH = keccak256(
        "Permit(address holder,address spender,uint256 nonce,uint256 expiry,bool allowed)"
    );

    constructor(string memory symbol_, string memory name_, string memory version_, uint256 chainId_) public {
        authenticatedAddresss[msg.sender] = 1;
        symbol = symbol_;
        name = name_;
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("Dai Semi-Automated Permit Office"),
            keccak256(bytes(version_)),
            chainId_,
            address(this)
        ));
    }

    // --- Token ---
    function transfer(address dst, uint fxp18Int) public returns (bool) {
        return transferFrom(msg.sender, dst, fxp18Int);
    }
    function transferFrom(address src, address dst, uint fxp18Int)
        public returns (bool)
    {
        if (src != msg.sender && allowance[src][msg.sender] != uint(-1)) {
            allowance[src][msg.sender] = sub(allowance[src][msg.sender], fxp18Int);
        }
        balanceOf[src] = sub(balanceOf[src], fxp18Int);
        balanceOf[dst] = add(balanceOf[dst], fxp18Int);
        emit Transfer(src, dst, fxp18Int);
        return true;
    }
    function mint(address usr, uint fxp18Int) public isAuthorized {
        balanceOf[usr] = add(balanceOf[usr], fxp18Int);
        totalSupply    = add(totalSupply, fxp18Int);
        emit Transfer(address(0), usr, fxp18Int);
    }
    function burn(address usr, uint fxp18Int) public {
        if (usr != msg.sender && allowance[usr][msg.sender] != uint(-1)) {
            allowance[usr][msg.sender] = sub(allowance[usr][msg.sender], fxp18Int);
        }
        balanceOf[usr] = sub(balanceOf[usr], fxp18Int);
        totalSupply    = sub(totalSupply, fxp18Int);
        emit Transfer(usr, address(0), fxp18Int);
    }
    function approve(address usr, uint fxp18Int) public returns (bool) {
        allowance[msg.sender][usr] = fxp18Int;
        emit Approval(msg.sender, usr, fxp18Int);
        return true;
    }

    // --- Alias ---
    function push(address usr, uint fxp18Int) public {
        transferFrom(msg.sender, usr, fxp18Int);
    }
    function pull(address usr, uint fxp18Int) public {
        transferFrom(usr, msg.sender, fxp18Int);
    }
    function move(address src, address dst, uint fxp18Int) public {
        transferFrom(src, dst, fxp18Int);
    }

    // --- Approve by signature ---
    function permit(address holder, address spender, uint256 nonce, uint256 expiry,
                    bool allowed, uint8 v, bytes32 r, bytes32 s) public
    {
        bytes32 digest =
            keccak256(abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH,
                                     holder,
                                     spender,
                                     nonce,
                                     expiry,
                                     allowed))
        ));
        require(holder == ecrecover(digest, v, r, s), "invalid permit");
        require(expiry == 0 || now <= expiry, "permit expired");
        require(nonce == nonces[holder]++, "invalid nonce");
        uint fxp18Int = allowed ? uint(-1) : 0;
        allowance[holder][spender] = fxp18Int;
        emit Approval(holder, spender, fxp18Int);
    }
}
