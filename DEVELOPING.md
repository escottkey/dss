# Multi Collateral Dai Developer Guide

*work in progress*

This is a more in depth description of the Dai core contracts. The
previous iteration of Dai was called Single Collateral Dai (SCD), or
`sai`, and is found at https://github.com/makerdao/sai


## Tooling

- dapp.tools
- solc v0.4.24
- tests use ds-test and are in files ending .t.sol


## Units

Dai has three different numerical units: `fxp18Int`, `fxp27Int` and `fxp45Int`

- `fxp18Int`: fixed point decimal with 18 decimals (for basic quantities, e.g. balances)
- `fxp27Int`: fixed point decimal with 27 decimals (for precise quantites, e.g. ratios)
- `fxp45Int`: fixed point decimal with 45 decimals (result of integer multiplication with a `fxp18Int` and a `fxp27Int`)

`fxp18Int` and `fxp27Int` units will be familiar from SCD. `fxp45Int` is a new unit and
exists to prevent precision loss in the core CDP engine.

The base of `fxp27Int` is `ONE = 10 ** 27`.

A good explanation of fixed point arithmetic can be found at [Wikipedia](https://en.wikipedia.org/wiki/Fixed-point_arithmetic).

## Multiplication

Generally, `fxp18Int` should be used additively and `fxp27Int` should be used
multiplicatively. It usually doesn't make sense to multiply a `fxp18Int` by a
`fxp18Int` (or a `fxp45Int` by a `fxp45Int`).

Two multiplaction operators are used in `dss`:

- `mul`: standard integer multiplcation. No loss of precision.
- `rmul`: used for multiplications involving `fxp27Int`'s. Precision is lost.

They can only be used sensibly with the following combination of units:

- `mul(fxp18Int, fxp27Int) -> fxp45Int`
- `rmul(fxp18Int, fxp27Int) -> fxp18Int`
- `rmul(fxp27Int, fxp27Int) -> fxp27Int`
- `rmul(fxp45Int, fxp27Int) -> fxp45Int`

## Code style

This is obviously opinionated and you may even disagree, but here are
the considerations that make this code look like it does:

- Distinct things should have distinct names ("memes")

- Lack of symmetry and typographic alignment is a code smell.

- Inheritance masks complexity and encourages over abstraction, be
  explicit about what you want.

- In this modular system, contracts generally shouldn't call or jump
  into themselves, except for math. Again, this masks complexity.


## Architecture

![MCD calls](img/mcd-calls.png)

## CDP Engine

The core CDP, Dai, and collateral state is kept in the `cdpDatabase`. This
contract has no external dependencies and maintains the central
"Accounting Invariants" of Dai.

Dai cannot exist without collateral:

- An `collateralType` is a particular type of collateral.
- Collateral `collateralTokens` is assigned to users with `modifyUsersCollateralBalance`.
- Collateral `collateralTokens` is transferred between users with `transferCollateral`.

The CDP data structure is the `cdp`:

- it has `collateralBalance` encumbered collateral
- it has `stablecoinDebt` encumbered debt

Similarly, a collateral `collateralType`:

- it has `totalCollateralBalance` encumbered collateral
- it has `totalStablecoinDebt` encumbered debt
- it has `take` collateral scaling factor (discussed further below)
- it has `debtMultiplierIncludingStabilityFee` debt scaling factor (discussed further below)

Here, "encumbered" means "locked in a CDP".

CDPs are managed via `modifyCDP(i, u, v, w, changeInCollateral, changeInDebt)`, which modifies the
CDP of user `u`, using `collateralTokens` from user `v` and creating `dai` for user
`w`.

CDPs are confiscated via `liquidateCDP(i, u, v, w, changeInCollateral, changeInDebt)`, which modifies
the CDP of user `u`, giving `collateralTokens` to user `v` and creating `badDebt` for
user `w`. `liquidateCDP` is the means by which CDPs are liquidated, transferring
debt from the CDP to a users `badDebt` balance.

badDebt represents "seized" or "bad" debt and can be cancelled out with an
equal quantity of Dai using `heal(u, v, fxp45Int)`: take `badDebt` from `u` and
`dai` from `v`.

Note that `heal` can also be used to *create* Dai, balanced by an equal
quantity of badDebt.

Finally, the quantity `dai` can be transferred between users with `move`.

### Identifiers

The above discusses "users", but really the `cdpDatabase` does not have a
notion of "addresses" or "users", and just assigns internal values to
`bytes32` identifiers. The operator of the `cdpDatabase` is transferCollateralFromCDP to use any
scheme they like to manage these identifiers. A simple scheme
is to give an ethereum address control over any identifier that has the
address as the last 20 bytes.


### debtMultiplierIncludingStabilityFee

The collateralType quantities `take` and `debtMultiplierIncludingStabilityFee` define the ratio of exchange
between un-encumbered and encumbered Collateral and debt respectively.

These quantitites allow for manipulations collateral and debt balances
across a whole collateralType.

Collateral can be seized or injected into an collateralType using `changeCollateralMultiplier(i, u, take)`,
which decreases the `collateralTokens` balance of the user `u` by increasing the
encumbered collateral balance of all cdps in the collateralType by the ratio
`take`.

debt can be seized or injected into an collateralType using `changeDebtMultiplier(i, u, debtMultiplierIncludingStabilityFee)`,
which increases the `dai` balance of the user `u` by increasing the
encumbered debt balance of all cdps in the collateralType by the ratio `debtMultiplierIncludingStabilityFee`.

The practical use of these mechanisms is in applying stability fees and
seizing collateral in the case of global settlement.

## CDP Interface

The `cdpDatabase` is unsuitable for use by untrusted actors. External
users can manage their CDP using the `Pit` ("tfxp45Inting pit").

The `Pit` contains risk parameters for each `collateralType`:

- `maxDaiPerUnitOfCollateral`: the maximum amount of Dai drawn per unit collateral
- `debtCeiling`: the maximum total Dai drawn

And a global risk parameter:

- `totalDebtCeiling`: the maximum total Dai drawn across all collateralTypes

The `Pit` exposes one public function:

- `modifyCDP(collateralType, changeInCollateral, changeInDebt)`: manipulate the callers CDP in the given `collateralType`
  by `changeInCollateral` and `changeInDebt`, subject to the risk parameters

## Liquidation Interface

The companion to CDP management is CDP liquidation, which is defined via the Liquidation.

The `Liquidation` contains liquidation parameters for each `collateralType`:

- `collateralForDaiAuction`: the address of the collateral liquidator
- `chop`: the liquidation penalty
- `lump`: the liquidation quantity

The `Liquidation` exposes two public functions

- `bite(collateralType, cdp)`: mark a specific CDP for liquidation
- `collateralForDaiAuction(n, fxp18Int)`: initiate liquidation
