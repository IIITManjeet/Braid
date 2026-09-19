#[test_only]
/// The venue set the router tests run against, shared with the generated
/// route tests so both are provably trading the same world.
///
/// `braid-route`'s fixture `router_test_world` is this, in Rust. The generated
/// tests are what hold the two to agreeing: a plan computed against the Rust
/// copy is executed here with `min_out` set to the value it predicts. The
/// generated file is byte-identical to the Sui one, so `buy_eth` keeps the Sui
/// signature exactly.
module braid_router::test_world {
    use std::string;
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability};
    use aptos_framework::primary_fungible_store;

    use braid_cpmm::pool as cpmm;
    use braid_stable::pool as stable;
    use braid_clmm::i32;
    use braid_clmm::pool as clmm;
    use braid_clob::book;
    use braid_clob::market as clob;
    use braid_router::route;

    struct USD {}
    struct ETH {}

    const ADMIN: address = @0xA;
    const TRADER: address = @0xB;

    /// sqrt(1.0) in Q64.64.
    const P0: u128 = 18446744073709551616;

    /// Where the four venues of one world live.
    struct World has copy, drop {
        cpmm: address,
        stable: address,
        clmm: address,
        market: address,
    }

    public fun cpmm_pool(w: &World): address { w.cpmm }
    public fun stable_pool(w: &World): address { w.stable }
    public fun clmm_pool(w: &World): address { w.clmm }
    public fun market(w: &World): address { w.market }

    /// Mint and burn authority for the two test coins -- see the note on the
    /// CLOB's `market_tests::Caps`.
    struct Caps has key {
        usd_mint: MintCapability<USD>,
        usd_burn: BurnCapability<USD>,
        eth_mint: MintCapability<ETH>,
        eth_burn: BurnCapability<ETH>,
    }

    /// Every world's `MarketCap`. The cap has no `drop`, and `store_cap` holds
    /// one per account, so a second world's would have nowhere to go.
    struct CapStash has key {
        caps: vector<clob::MarketCap>,
    }

    /// Accounts and coin types, once per test. A test may build several
    /// worlds, and `coin::initialize` aborts the second time.
    fun ensure_setup() {
        if (exists<Caps>(@braid_router)) return;
        account::create_account_for_test(@aptos_framework);
        let braid = account::create_account_for_test(@braid_router);
        account::create_account_for_test(ADMIN);
        account::create_account_for_test(TRADER);

        let (usd_burn, usd_freeze, usd_mint) = coin::initialize<USD>(
            &braid, string::utf8(b"USD"), string::utf8(b"USD"), 6, false,
        );
        let (eth_burn, eth_freeze, eth_mint) = coin::initialize<ETH>(
            &braid, string::utf8(b"ETH"), string::utf8(b"ETH"), 6, false,
        );
        coin::destroy_freeze_cap(usd_freeze);
        coin::destroy_freeze_cap(eth_freeze);
        move_to(&braid, Caps { usd_mint, usd_burn, eth_mint, eth_burn });
        move_to(&braid, CapStash { caps: vector[] });
    }

    public fun trader(): signer { account::create_signer_for_test(TRADER) }

    public fun mint_usd(v: u64): Coin<USD> acquires Caps {
        coin::mint<USD>(v, &borrow_global<Caps>(@braid_router).usd_mint)
    }

    public fun mint_eth(v: u64): Coin<ETH> acquires Caps {
        coin::mint<ETH>(v, &borrow_global<Caps>(@braid_router).eth_mint)
    }

    public fun burn_usd(c: Coin<USD>) acquires Caps {
        coin::burn<USD>(c, &borrow_global<Caps>(@braid_router).usd_burn)
    }

    public fun burn_eth(c: Coin<ETH>) acquires Caps {
        coin::burn<ETH>(c, &borrow_global<Caps>(@braid_router).eth_burn)
    }

    /// The four venues, all on USD/ETH at a raw price of 1:1 -- the same
    /// shape as the testnet deployment.
    ///
    /// Sui's `world` takes a `salt` to push a second world in one test onto
    /// fresh object ids. Nothing here needs one: every pool and market is a
    /// new object at an address derived from a fresh GUID, so two worlds in a
    /// test never collide.
    public fun world(): World acquires Caps, CapStash {
        ensure_setup();
        let admin = account::create_signer_for_test(ADMIN);

        let (cpmm_addr, lp) = cpmm::create_pool<USD, ETH>(
            mint_usd(10_000_000), mint_eth(10_000_000), 30,
        );
        primary_fungible_store::deposit(ADMIN, lp);

        let (stable_addr, slp) = stable::create_pool<USD, ETH>(
            mint_usd(10_000_000), mint_eth(10_000_000), 10_000, 4,
        );
        primary_fungible_store::deposit(ADMIN, slp);

        let clmm_addr = clmm::create_pool<USD, ETH>(P0, 30, 60);
        let (ra, rb) = clmm::add_liquidity<USD, ETH>(
            &admin,
            clmm_addr,
            i32::neg_from(600),
            i32::from_u32(600),
            mint_usd(5_000_000),
            mint_eth(5_000_000),
        );
        burn_usd(ra);
        burn_eth(rb);

        let (market_addr, cap) = clob::create_market<ETH, USD>(100_000, 10_000, 10);
        borrow_global_mut<CapStash>(@braid_router).caps.push_back(cap);
        rest_ask(&admin, market_addr, 1_000_100_000);
        rest_ask(&admin, market_addr, 1_000_500_000);
        rest_ask(&admin, market_addr, 1_001_000_000);
        rest_bid(&admin, market_addr, 999_900_000);
        rest_bid(&admin, market_addr, 999_500_000);

        World { cpmm: cpmm_addr, stable: stable_addr, clmm: clmm_addr, market: market_addr }
    }

    fun rest_ask(admin: &signer, m: address, price: u64) acquires Caps {
        let pay = mint_eth(2_000_000);
        let (out, change, _) =
            clob::place_ask<ETH, USD>(admin, m, price, 2_000_000, book::gtc(), pay);
        burn_usd(out);
        burn_eth(change);
    }

    fun rest_bid(admin: &signer, m: address, price: u64) acquires Caps {
        let pay = mint_usd(2_100_000);
        let (out, change, _) =
            clob::place_bid<ETH, USD>(admin, m, price, 2_000_000, book::gtc(), pay);
        burn_eth(out);
        burn_usd(change);
    }

    /// Route `total` USD -> ETH in a fresh world, spending `[cpmm, stable,
    /// clmm, clob]`. Returns `(eth_out, usd_unspent)`.
    ///
    /// `_salt` is Sui's, kept so the generated tests are the same bytes on
    /// both chains; see `world`.
    public fun buy_eth(_salt: u64, total: u64, amounts: vector<u64>, min_out: u64): (u64, u64) acquires Caps, CapStash {
        let w = world();
        let taker = trader();

        let r = route::begin<USD, ETH>(mint_usd(total), min_out);
        route::cpmm_a_to_b(&mut r, w.cpmm, amounts[0]);
        route::stable_a_to_b(&mut r, w.stable, amounts[1]);
        route::clmm_a_to_b(&mut r, w.clmm, amounts[2]);
        route::clob_quote_to_base<ETH, USD>(&mut r, &taker, w.market, amounts[3]);
        let (out, unspent) = route::finish(r);
        let (o, u) = (coin::value(&out), coin::value(&unspent));

        burn_eth(out);
        burn_usd(unspent);
        (o, u)
    }
}
