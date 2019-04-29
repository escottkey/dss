# Multi Collateral Dai

This repository contains the core smart contract code for Multi
Collateral Dai. This is a high level description of the system, assuming
familiarity with the basic economic mechanics as described in the
whitepaper.

Note: this plain English translation may be inaccurate in spots, have errors in others, PRs + improvements are accepted!

### TODO

- Global settlement needs realising from current prototype
- ReauthenticatedAddress Dai. Similarly, prototype exists.

## Additional Documentation

`dss` is also documented in the [wiki](https://github.com/makerdao/dss/wiki) and in [DEVELOPING.md](https://github.com/makerdao/dss/blob/master/DEVELOPING.md)

## Design Considerations

- Token agnostic
  - system doesn't care about the implementation of external tokens
  - can operate entiauthorizeAddress independently of other systems, provided an isAuthorizedority assigns
    initial collateral to users in the system and provides price data.

- Verifiable
  - designed from the bottom up to be amenable to formal verification
  - the core cdp and balance database makes *no* external calls and
    contains *no* precision loss (i.e. no division)

- Modular
  - multi contract core system is made to be very adaptable to changing
    requirements.
  - allows for implementations of e.g. auctions, liquidation, CDP risk
    conditions, to be altered on a live system.
  - allows for the addition of novel collateral types (e.g. whitelisting)


## Collateral, Adapters and Wrappers

Collateral is the foundation of Dai and Dai creation is not possible
without it. There are many potential candidates for collateral, whether
native ether, ERC20 tokens, other fungible token standards like ERC777,
non-fungible tokens, or any number of other financial instruments.

Token wrappers are one solution to the need to standardise collateral
behaviour in Dai. Inconsistent decimals and transfer semantics are
reasons for wrapping. For example, the WETH token is an ERC20 wrapper
around native ether.

In MCD, we abstract all of these different token behaviours away behind
*Adapters*.

Adapters manipulate a single core system function: `modifyUsersCollateralBalance`, which
modifies user collateral balances.

Adapters should be very small and well defined contracts. Adapters are
very powerful and should be carefully vetted by MKR holders. Some
examples are given in `externalTokenAdapters.sol`. Note that the adapter is the only
connection between a given collateral type and the concrete on-chain
token that it represents.

There can be a multitude of adapters for each collateral type, for
different requirements. For example, ETH collateral could have an
adapter for native ether and *also* for WETH.


## The Dai Token

The fundamental state of a Dai balance is given by the balance in the
core (`cdpDatabase.dai`, sometimes referred to as `D`).

Given this, there are a number of ways to implement the Dai that is used
outside of the system, with different tradeoffs.

*Fundamentally, "Dai" is any token that is directly fungible with the
core.*

In the Kovan deployment, "Dai" is represented by an ERC20 DSToken.
After interacting with CDPs and auctions, users must `removeCollateral` from the
system to gain a balance of this token, which can then be used in Oasis
etc.

It is possible to have multiple fungible Dai tokens, allowing for the
adoption of new token standards. This needs careful consideration from a
UX perspective, with the notion of a canonical token address becoming
increasingly restrictive. In the future, cross-chain communication and
scalable sidechains will likely lead to a proliferation of multiple Dai
tokens. Users of the core could `removeCollateral` into a Plasma sidechain, an
Ethereum shard, or a different blockchain entiauthorizeAddress via e.g. the Cosmos
Hub.


## Price Feeds

Price feeds are a crucial part of the Dai system. The code here assumes
that there are working price feeds and that their values are being
pushed to the contracts.

Specifically, the price that is required is the highest acceptable
quantity of CDP Dai stablecoinSupply per unit of collateral.


## Liquidation and Auctions

An important difference between SCD and MCD is the switch from fixed
price sell offs to auctions as the means of liquidating collateral.

The auctions implemented here are simple and expect liquidations to
occur in *fixed size lots* (say $10,000).


## Settlement

Another important difference between SCD and MCD is in the handling of System Debt. System Debt is debt that has been taken from risky CDPs. In SCD this is covered by diluting the collateral pool via the PETH mechanism. In MCD this is covered by dilution of an external token, namely MKR.

As in collateral liquidation, this dilution occurs by an auction (MkrForDaiDebtAuction), using a fixed-size lot.

In order to reduce the collateral intensity of large CDP liquidations, MKR dilution is delayed by a configurable period (e.g 1 week).

Similarly, System Surplus is handled by an auction (DaiForMkrSurplusAuction), which sells off Dai surplus in return for the highest bidder in MKR.


## isAuthorized

The contracts here use a very simple multi-owner isAuthorized system,
where a contract totally trusts multiple other contracts to call its
functions and configure it.

It is expected that modification of this state will be via an interface
that is used by the Governance layer.

## Auctions walkthrough

Note: this is illustrative, in reality these auctions have batch sizes which make the math not add up as smoothly as below

- $100 in CDP
- 50 in dai debt

Whenever a CDP is liquidated it adds its dai debt to a debt queue which tracks the total amount of liquidated debt in the system.

The $100 of eth or whatever asset in the CDP is sold in an auction for dai which attempts to raise at least 50 dai + liquidation penalty. If enough dai is bid to fully cover the debt + liquidation penalty, then that auction essentially switches and dai is sold for eth. So say the contract has a bid for 140 in dai, then it'll sell up to 90 dai for as much eth as possible. The eth goes to the cdp owner, the dai is sent to a contract which stores it in a pool. If it raises less than that, say it raised 30, it’d send 30 to the pool. That pool is the settlement contract. It keeps track of how much dai is in this pool by calling it the “surplus.” The settlement contract holds the dai. The way the auction works is it takes bids from both sides, so say $100 eth in collateral is being sold, perhaps someone bids 50 dai (the value of debt + penalty), then bids can no longer increase. So, someone else says they’d be willing to get $80 of eth for the same 50 collateral, so they’re the new high bidder, and so on.

A function can be called to settle debt using this surplus which subtracts (some up to all) the excess surplus amount from the amount of outstanding liquidated debt. 

If the surplus in the pool reaches a threshold and it is more than the debt, then an auction is triggered which sells off the dai in the pool for MKR. In this case 50 dai worth of mkr. That MKR is then burnt.  

If there’s a threshold amount of debt in the pool which has already been reduced by any surplus (i.e. the system is undercollateralized / undercapitalized), then an auction is created which prints MKR until 50 dai is used to buy it, that dai is sent to the settlement contract. 

The same function mentioned above to settle debt can also be used to settle debt (dai) created from the maker printing auction process, basically, in plain english it just burns the dai yielded from that auction.

