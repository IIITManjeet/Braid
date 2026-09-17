# Porting Braid from Sui Move to Aptos Move

`move/aptos/` is the phase-2 port of five of the six Sui packages: `braid_math`,
`braid_cpmm`, `braid_stable`, `braid_clmm` and `braid_clob`. Only `braid_router`
is still Sui-only, for a reason worth its own section at the end. Both trees are
live and both suites run in CI-shaped one-liners:

```bash
bash scripts/test.sh         # all of move/sui: 570 tests, plus the Rust replica
bash scripts/test-aptos.sh   # all of move/aptos: 537 tests
```

Counting only the five packages that exist on both sides: **536 tests on Sui,
537 on Aptos.** The extra one is explained below, and it is the only behavioural
difference in the whole port.

This note is what the port actually cost, separated into the two categories that
matter: edits the compiler forced on otherwise identical code, and places where
the two chains disagree about what a program *is*.

The headline: **the pricing math is the same code, and the generated
differential-fuzz corpora are byte-identical files that pass unmodified on both
chains.** For the three formula suites, `diff` between the trees is empty:

```bash
diff move/sui/braid_cpmm/tests/generated_diff_tests.move \
     move/aptos/braid_cpmm/tests/generated_diff_tests.move   # empty
# likewise braid_stable and braid_clmm
```

3,029 formula cases produced by the Rust replica in `node/crates` now run
against two independent Move VMs and agree with both to the unit. That is a
stronger claim than the Sui tree could make alone: a replica that matches one
implementation might have copied its bug, but a replica that matches two
implementations on two VMs is describing the arithmetic, not the code.

The two *whole-scenario* corpora -- 100 random CLMM pools and 50 random order
books -- cannot be byte-identical, because they build chain state and that is
exactly what differs. So `braid-difftest` now renders them twice, from
identically seeded RNG streams, and case `k` in the Sui file is the same pool
and the same trades as case `k` in the Aptos file. Every one passes on both. The
CLMM suite is 246 tests on either chain and the CLOB suite 128, the same numbers
on both sides:

```rust
write("../move/sui/braid_clmm/tests/generated_pool_diff_tests.move",
      &gen_clmm_pools(&mut rng_pools, n / 4, Dialect::Sui));
write("../move/aptos/braid_clmm/tests/generated_pool_diff_tests.move",
      &gen_clmm_pools(&mut Rng(SEED ^ 0x9001_5EED_u64), n / 4, Dialect::Aptos));
```

Regenerating still reproduces the committed Sui files byte for byte, so the
"a silent repricing becomes a reviewable line in a pull request" property the
README claims survives the port -- now across two chains.

---

## Part 1: the dialect

Six things the compiler insisted on. None of them changed a value.

### `let mut` does not exist

Sui's 2024 edition made local mutability explicit. Aptos Move did not follow, and
every local is assignable:

```move
let mut r = n / d;     // Sui
let r = n / d;         // Aptos
```

That is the entire diff for `full_math.move` and `q64.move` — 38 occurrences
across the transliterated math layer, applied by `sed`, after which
`grep -rn '\blet mut' move/aptos` returns nothing and the only surviving `mut` is
`&mut`, which both dialects spell the same. It is worth noticing what this
*doesn't* cost: nothing here relied
on `mut` as documentation, because the functions are small enough that the
reassignment is visible anyway. In `stable_math`'s Newton iterations, where the
loop variable genuinely is the state, the Sui version reads slightly better.

### No `vector` in the prelude

Sui binds `vector` to `std::vector` for you. Aptos does not, so `stable_math`'s
limit-cycle history needed `use std::vector;` added. One line.

### The source has to be ASCII

Aptos CLI 7.2.0 rejects any non-ASCII byte, in comments included:

```
error: invalid character
    │   D <- (Ann·S/AP + n·D_P) · D  /  ((Ann - AP)·D/AP + (n+1)·D_P)
    │                  ^ Invalid character '·' found when reading file.
```

The Curve invariant derivation in `stable_math`'s header used `·` and `Π`. Sui
compiles them without comment. On Aptos they became `*` and `prod(...)`, which is
a small loss — the ASCII version of a product formula is harder to read than the
real notation.

### Doc comments go *after* attributes

```move
#[view]
/// The LP asset's metadata object, so a holder can find their balance.
public fun lp_metadata<A, B>(pool_addr: address): Object<Metadata>
```

Put the `///` first and the compiler warns that the documentation "cannot be
matched to a language item" and silently drops it. Sui has no equivalent
ordering rule because it has no `#[view]`.

### Addresses are `_`, and every dev value must be distinct

Sui pins `braid_math = "0x0"` and the publish transaction rewrites it to the id
the chain assigned. Aptos writes `_` for "assigned at publish" and needs a
`[dev-addresses]` block to give tests something concrete. The constraint that
costs you a build is this one:

```
Found non-unique dev address assignment 'braid_math = 0xb4a1d' in root package
'braid_cpmm'. Dev address assignments must not conflict with any other
assignments in order to ensure that the package will compile with any possible
address assignment.
```

So the three packages take three distinct dev addresses (`0xB4A1D`, `0xCEE`,
`0x57AB1E`) even though at publish time they all resolve to the *same* account.
The rule exists to stop a package quietly depending on two names being equal.

This is also the deployment difference in miniature. Sui publishes one package
per transaction and gives each its own id, so `braid_cpmm`'s dependency on
`braid_math` becomes an on-chain pin at deploy time and `scripts/deploy.sh`
rewrites the manifest. Aptos publishes a package set under one account, so the
local path dependency stays a local path dependency and there is nothing to
rewrite.

### The framework must match the CLI

Pointing `AptosFramework` at a branch, or at a newer tag than the vendored CLI,
fails inside the framework's own sources:

```
error: unexpected token
    │ } proof {
    │   ^^^^^ Unexpected 'proof'
```

`aptos-core` ships the compiler and the framework together and the language
version moves under you. `move/aptos/*/Move.toml` pins
`rev = "aptos-cli-v7.2.0"` to match `APTOS_VERSION` in `scripts/get-aptos.sh`;
bump the two as a pair. Sui's vendored-CLI story in `scripts/get-sui.sh` has no
counterpart problem, because the Sui framework is bundled *inside* the CLI
rather than fetched from git.

---

## Part 2: the object model

This is the part that is not a transliteration. `cpmm_math.move` and
`stable_math.move` are the same program in both trees; `pool.move` is not, and
the reasons are worth stating precisely.

### Where a pool lives

Sui: a pool is an object with a `UID`, made reachable by `transfer::share_object`,
and reached by passing it:

```move
public fun swap_a_for_b<A, B>(
    pool: &mut Pool<A, B>,
    coin_in: Coin<A>,
    min_out: u64,
    ctx: &mut TxContext,
): Coin<B>
```

Aptos: resources live in global storage under an address. The pool arrives as an
`address`, the function declares `acquires Pool`, and the borrow is explicit:

```move
public fun swap_a_for_b<A, B>(
    pool_addr: address,
    coin_in: Coin<A>,
    min_out: u64,
): Coin<B> acquires Pool {
    assert_pool_exists<A, B>(pool_addr);
    let pool = borrow_global_mut<Pool<A, B>>(pool_addr);
```

**This costs a runtime check that Sui gets for free.** A Sui transaction naming a
`&mut Pool<A, B>` either resolves to a live object of exactly that type before
any Move code runs, or the transaction never starts. Addressing storage by hand
puts that back on the module, which is why the Aptos pools carry an error the Sui
pools do not:

```move
/// No pool of that pair lives at the given address.
const ENoSuchPool: u64 = 5;
```

That one error is the entire difference in the test counts — 163 Aptos tests
against 162 Sui ones, and the extra test is
`a_swap_against_an_address_holding_no_pool_aborts`. It is a nice illustration of
what a stronger type discipline at the transaction boundary buys: not
correctness, exactly, but one fewer thing to remember.

The `(address, type)` key does have a compensating property. `Pool<USDC, WETH>`
and `Pool<USDC, USDT>` at the same address are different resources and coexist
without any registry — the type parameters *are* the index. Sui needs an object
id per pool because its storage is keyed by id alone.

### "Shared" has no direct spelling

`transfer::share_object` says "no owner, anyone may pass this by reference".
Aptos objects always have an owner. The nearest construction is an object owned
by the package address — which has no signer after publication — with ungated
transfer switched off:

```move
let ctor = object::create_sticky_object(@braid_cpmm);
object::disable_ungated_transfer(&object::generate_transfer_ref(&ctor));
```

`create_sticky_object` rather than `create_object` is not stylistic:
`create_object` produces a *deletable* object and `fungible_asset::add_fungibility`
refuses those outright, since an asset's metadata must outlive anything
denominated in it. The failure is a bare `65554` from inside the framework, which
is a while to track down the first time.

### A reference cannot leave global storage

The sharpest surprise of the CLOB port. Sui's market hands the book out whole:

```move
public fun book<Base, Quote>(market: &Market<Base, Quote>): &Book { &market.book }
```

Callers then reach through it -- `book::has_order(market::book(&m), id)`. The
Aptos version does not compile:

```
error: cannot return a reference derived from struct `market::Market`
       since it is not based on a parameter
    │ public fun book<Base, Quote>(market_id: address): &Book acquires Market {
```

Reference safety will not let a borrow of global storage outlive the function
that took it, and on Aptos the market *is* global storage rather than a
parameter. Sui has no such problem because the caller already owns the
reference — it came in as an argument. So every accessor is forwarded
individually instead (`market::has_order`, `market::order_owner`,
`market::depth_at`, …), which is more code and, as it happens, more useful:
each forwarder can be a `#[view]`, and a `&Book` never could be.

### Storage operations belong to the defining module

Sui's `MarketCap` is an owned object. Its holder transfers it, stores it, or
passes it to `collect_fees`, and `market.move` has no say. The Aptos test tried
the equivalent and got:

```
error: Invalid operation: storage operation on type `market::MarketCap`
       can only be done within the defining module `0xc10b::market`
```

`move_to` and `borrow_global` on a type are confined to the module that declares
it. So a cap holder *cannot put their own cap away*; the market has to offer

```move
public fun store_cap(owner: &signer, cap: MarketCap) { move_to(owner, cap); }
```

and a matching reader, neither of which exists on the Sui side. The authority is
still the value rather than an address recorded in the market -- `collect_fees`
takes `&MarketCap` on both chains -- but the custody of that value is now the
declaring module's business. This is the same rule from the other direction as
the reference one above: Aptos draws a hard boundary at global storage, and Sui
draws it at object ownership.

### Tables

`sui::table::Table` has two Aptos counterparts, and picking the wrong one is a
compile error rather than a silent cost:

| | length tracked? | `destroy_empty`? | used by |
|---|---|---|---|
| `sui::table` | yes | yes | everything, on Sui |
| `aptos_std::table` | no | no | the CLMM pool's ticks, bitmap, positions; the market's claims |
| `aptos_std::table_with_length` | yes | yes | the critbit tree and the book |

`critbit` and `book` call `table::destroy_empty`, which needs to know the table
is empty, so they take the with-length variant. Nothing counts or destroys the
CLMM pool's three tables, so they take the plain one and skip a length write on
every tick update. Aliasing the import keeps the rest of `critbit.move` and
`book.move` character-for-character the Sui source:

```move
use aptos_std::table_with_length::{Self as table, TableWithLength as Table};
```

Those two modules are otherwise an eleven-line diff each, almost all of it that
import and `empty()` losing its `&mut TxContext`.

### Sui `Balance`/`Supply` vs Aptos `Coin`/`FungibleAsset`

The most interesting finding of the port. Compare abilities:

| | storable in a struct? | |
|---|---|---|
| Sui `Balance<T>` | yes (`store`) | reserves are struct fields |
| Aptos `Coin<T>` | yes (`store`) | same |
| Aptos `FungibleAsset` | **no abilities at all** | must be deposited before the transaction ends |

`FungibleAsset` is a hot potato. From the framework's own comment: *"FungibleAsset
is ephemeral and cannot be stored directly. It must be deposited back into a
store."* That is exactly the pattern `braid_router::route` uses on the Sui side
for `Route` — a struct with no abilities, so the type system forces the caller to
hand it to the function that discharges it. Aptos shipped its flagship token
standard on the trick Braid uses for atomic multi-venue settlement.

So the reserves stay `Coin<A>`/`Coin<B>`, which is the honest structural analogue
of Sui's `Balance<A>`. The LP token is where the models genuinely part ways.

### Why LP is a fungible asset and not a coin

Sui's LP is its own minting witness:

```move
public struct LP<phantom A, phantom B> has drop {}
let mut lp_supply = balance::create_supply(LP<A, B> {});
```

`create_supply` consumes one value of a `drop` type and returns the sole `Supply`
for it. Only the declaring module can construct that value, so only it can ever
mint. There is no capability object to lose and no admin to trust.

Aptos has no such thing for a type parameterised on the pair. `coin::initialize<LP<A,B>>`
asserts that the signer's address equals the address that *declares* `LP` — that
is, `@braid_cpmm`. Pool creation would need the publisher's signer, which means
either a resource account with a stored `SignerCapability` (the LiquidSwap
pattern) or permissioned pool creation. Both are worse.

The fungible-asset standard has no such constraint: mint and burn authority come
from a `ConstructorRef`, which any caller can obtain for an object they just
created. So each pool mints its own LP asset and keeps the refs inside itself:

```move
let lp_mint = fungible_asset::generate_mint_ref(&ctor);
let lp_burn = fungible_asset::generate_burn_ref(&ctor);
```

Same security property as Sui's witness — the refs are unreachable from outside
the module, so nothing else can mint — reached by a different route, and pool
creation stays permissionless. The asymmetry that remains (reserves are legacy
coins, LP is a fungible asset) is forced, not chosen.

One consequence worth flagging: Sui's `MINIMUM_LIQUIDITY` floor is a
`Balance<LP>` field parked inside the pool. A `FungibleAsset` cannot be a field,
so the Aptos floor is minted into the pool object's *own* primary store. Nothing
holds a signer for that address, so the shares are unspendable — the lock is the
missing signer, not a flag. The `locked_lp: u64` field records the amount for
reporting and is not load-bearing.

### Entry functions and the missing PTB

Sui's `create_pool` returns `Coin<LP<A, B>>` so a programmable transaction block
can thread it into a later command; `create_pool_entry` is the non-composable
convenience form for a plain CLI call. Aptos has no PTBs — an entry function
returns nothing and composition happens inside Move. So the wrapper is not a
convenience over composition, it is the *only* callable form, and the
value-returning version exists for other Move modules rather than for the client:

```move
public entry fun create_pool_entry<A, B>(
    creator: &signer, amount_a: u64, amount_b: u64, fee_bps: u64,
) {
    let coin_a = coin::withdraw<A>(creator, amount_a);
    ...
}
```

Note the `&signer` and the `coin::withdraw`. On Sui the caller hands you coins
they already own; on Aptos you are given the authority to take them. That is a
real difference in what a malicious module could do with an argument.

### `#[view]` closes a gap the Sui side still has

The README's "Not yet wired" note says reading return values back from deployed
Sui bytecode does not work: `--dev-inspect` on CLI 1.78 renders a dry run without
return values, and GraphQL's `simulateTransaction` wants a protobuf-shaped
transaction rather than serialized BCS. Aptos has `#[view]`, which a fullnode
evaluates against live state and returns as JSON, with no transaction and no gas.
Every quote and reserve accessor on the Aptos pools carries it. The off-chain
quote engine's on-chain anchor is genuinely easier on this side.

### Tests

Sui's `test_scenario` replays a sequence of transactions and hands objects back
by type: `ts::take_shared<Pool<USDC, WETH>>`, mutate, `ts::return_shared`. Aptos
unit tests are a single transaction against global storage, so a test holds an
address and calls through it — no `next_tx`, nothing to return. Most of the port
was deleting scaffolding.

Two smaller frictions:

- **Minting test coins.** Sui has `coin::mint_for_testing<T>`, which conjures a
  coin from nothing because a coin type there is a pure witness with no registry
  behind it. Aptos coins are registered types with a tracked supply, so the test
  module has to call `coin::initialize` and hold real `MintCapability`/
  `BurnCapability` values in a resource. And because `coin::initialize` demands
  the declaring address, the test coin types must be declared in a module
  published under `@braid_cpmm` — they cannot live in a shared fixture package.
- **Abort-code paths.** Sui writes the fully qualified
  `#[expected_failure(abort_code = braid_cpmm::pool::ESameCoinType)]`; Aptos
  wants the short `pool::ESameCoinType`.

The numbers all survived. The CPMM pool still pays exactly 996 on a 1,000-unit
trade against a 1e6/1e6 pool at 30 bps, and the StableSwap pool still returns
**999,590** for 1,000,000 in at `A = 100` and 4 bps — which is not just a
fixture, it is the figure the
[live Sui testnet swap](https://suiscan.xyz/testnet/tx/2g5GigCtPdPizEYJJffzGmY2rPHbHrC7X23gEq8QXF82)
returned. The Rust replica, the Python reference, the Sui chain, and now the
Aptos VM all agree on it.

---

### What the concentrated pool needed, and did not

`braid_clmm` is the largest port and the least eventful, which is the useful
finding. Eight of its nine modules are pure arithmetic -- tick math, the bitmap,
fee growth, the swap step, the signed integer types -- and they moved across on
`let mut` → `let` plus four non-ASCII characters in a comment. 128 tests, no
hand edits.

`pool.move` is the exception, and even there only the public entry points
changed. Each one resolves the pool with a single `borrow_global_mut` and then
calls the same private helpers, taking the same `&mut Pool<A, B>` the Sui
version passes in, so `modify_position`, `run_swap` and the tick accessors are
character-for-character the Sui source. The swap loop is the part that must not
drift, and threading storage access only through the boundary is what guarantees
it cannot.

Two smaller things:

- **`ctx.sender()` becomes an explicit `&signer`.** Sui authenticates the
  position owner through the transaction context. Here the authority is passed,
  and `remove_liquidity` and `collect` would be a theft primitive if it were a
  bare `address`.
- **`create_sticky_object`, not `create_object`.** The latter yields a
  *deletable* object and `fungible_asset::add_fungibility` refuses those, since
  an asset's metadata must outlive anything denominated in it. The failure is a
  bare `65554` from inside the framework, which is a while to track down.

One line of Sui did not come across: `public struct LP<phantom A, phantom B>`,
declared in the CLMM pool and never used -- concentrated positions are keyed
records, not tokens. A port is the wrong moment to copy dead code forward.

## What is not ported

`braid_router`. Not for want of effort — it is the one place where the property
the Sui code relies on does not exist on the other chain.

`Route` is a hot potato: no abilities, so a PTB that calls `begin` cannot
complete without handing it to `finish`, which is where `min_out` is enforced on
the *total* rather than per leg. The type system holds a partially-built
transaction hostage until the bound is checked. Aptos has no PTBs, so there is
no partially-built transaction to hold — the whole route would execute inside
one Move function instead. The safety property survives, but it stops being a
*type* property and becomes an ordinary control-flow one, which is a real
downgrade in what the compiler proves rather than a change of spelling.

The irony, noted above: Aptos ships `FungibleAsset` on exactly this trick. The
pattern is available; what is missing is a caller-assembled transaction for it
to constrain.

Nothing is deployed to Aptos testnet yet; the Sui addresses in the README remain
the only live deployment.

## What turned out not to be a difference

Worth recording, because each of these looked like one at first:

- **Vector method and index syntax.** `v.length()`, `v[i]`, `v.is_empty()` all
  work on Aptos. An earlier draft of this port rewrote them into
  `std::vector::…` calls for nothing; the rewrite was reverted.
- **`public struct`.** Aptos accepts the Sui-2024 spelling, so the sed'd files
  kept it and the diff stayed smaller than expected.
- **`#[test]` and `#[expected_failure]`.** Identical, apart from the abort-code
  path form.
