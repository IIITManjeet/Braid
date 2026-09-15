#[test_only]
/// The venue set the router tests run against, shared with the generated
/// route tests so both are provably trading the same world.
///
/// `braid-route`'s fixture `router_test_world` is this, in Rust. The generated
/// tests are what hold the two to agreeing: a plan computed against the Rust
/// copy is executed here with `min_out` set to the value it predicts.
module braid_router::test_world {
    use sui::coin;
    use sui::test_scenario::{Self as ts, Scenario};

    use braid_cpmm::pool::{Self as cpmm, Pool as CpmmPool};
    use braid_stable::pool::{Self as stable, StablePool};
    use braid_clmm::i32;
    use braid_clmm::pool::{Self as clmm, Pool as ClmmPool};
    use braid_clob::book;
    use braid_clob::market::{Self as clob, Market};
    use braid_router::route;

    public struct USD has drop {}
    public struct ETH has drop {}

    const ADMIN: address = @0xA;
    const TRADER: address = @0xB;

    /// sqrt(1.0) in Q64.64.
    const P0: u128 = 18446744073709551616;

    /// The four venues, all on USD/ETH at a raw price of 1:1 -- the same
    /// shape as the testnet deployment.
    ///
    /// `salt` exists because of the test runtime, not the router. Object ids
    /// derive from the transaction number, every scenario starts counting from
    /// the same place, and dynamic fields outlive `sc.end()` -- so a second
    /// world built in the same test would hand its order book the first one's
    /// table ids and collide. Burning `salt` transactions first moves it
    /// onto fresh ids. Each world in a test needs a distinct salt.
    public fun world(salt: u64): Scenario {
        let mut sc = ts::begin(ADMIN);
        let mut i = 0;
        while (i < salt) {
            sc.next_tx(ADMIN);
            i = i + 1;
        };
        {
            let ctx = sc.ctx();

            let lp = cpmm::create_pool(
                coin::mint_for_testing<USD>(10_000_000, ctx),
                coin::mint_for_testing<ETH>(10_000_000, ctx),
                30,
                ctx,
            );
            transfer::public_transfer(lp, ADMIN);

            let slp = stable::create_pool(
                coin::mint_for_testing<USD>(10_000_000, ctx),
                coin::mint_for_testing<ETH>(10_000_000, ctx),
                10_000,
                4,
                ctx,
            );
            transfer::public_transfer(slp, ADMIN);

            clmm::create_pool<USD, ETH>(P0, 30, 60, ctx);

            let cap = clob::create_market<ETH, USD>(100_000, 10_000, 10, ctx);
            transfer::public_transfer(cap, ADMIN);
        };

        sc.next_tx(ADMIN);
        {
            let mut pool = sc.take_shared<ClmmPool<USD, ETH>>();
            let (ra, rb) = clmm::add_liquidity(
                &mut pool,
                i32::neg_from(600),
                i32::from_u32(600),
                coin::mint_for_testing<USD>(5_000_000, sc.ctx()),
                coin::mint_for_testing<ETH>(5_000_000, sc.ctx()),
                sc.ctx(),
            );
            coin::burn_for_testing(ra);
            coin::burn_for_testing(rb);
            ts::return_shared(pool);

            let mut m = sc.take_shared<Market<ETH, USD>>();
            rest_ask(&mut sc, &mut m, 1_000_100_000);
            rest_ask(&mut sc, &mut m, 1_000_500_000);
            rest_ask(&mut sc, &mut m, 1_001_000_000);
            rest_bid(&mut sc, &mut m, 999_900_000);
            rest_bid(&mut sc, &mut m, 999_500_000);
            ts::return_shared(m);
        };

        sc.next_tx(TRADER);
        sc
    }

    fun rest_ask(sc: &mut Scenario, m: &mut Market<ETH, USD>, price: u64) {
        let pay = coin::mint_for_testing<ETH>(2_000_000, sc.ctx());
        let (out, change, _) = clob::place_ask(m, price, 2_000_000, book::gtc(), pay, sc.ctx());
        coin::burn_for_testing(out);
        coin::burn_for_testing(change);
    }

    fun rest_bid(sc: &mut Scenario, m: &mut Market<ETH, USD>, price: u64) {
        let pay = coin::mint_for_testing<USD>(2_100_000, sc.ctx());
        let (out, change, _) = clob::place_bid(m, price, 2_000_000, book::gtc(), pay, sc.ctx());
        coin::burn_for_testing(out);
        coin::burn_for_testing(change);
    }

    /// Route `total` USD -> ETH in a fresh world, spending `[cpmm, stable,
    /// clmm, clob]`. Returns `(eth_out, usd_unspent)`.
    public fun buy_eth(salt: u64, total: u64, amounts: vector<u64>, min_out: u64): (u64, u64) {
        let mut sc = world(salt);
        let mut cp = sc.take_shared<CpmmPool<USD, ETH>>();
        let mut sp = sc.take_shared<StablePool<USD, ETH>>();
        let mut cl = sc.take_shared<ClmmPool<USD, ETH>>();
        let mut mk = sc.take_shared<Market<ETH, USD>>();

        let coin_in = coin::mint_for_testing<USD>(total, sc.ctx());
        let mut r = route::begin<USD, ETH>(coin_in, min_out);
        route::cpmm_a_to_b(&mut r, &mut cp, amounts[0], sc.ctx());
        route::stable_a_to_b(&mut r, &mut sp, amounts[1], sc.ctx());
        route::clmm_a_to_b(&mut r, &mut cl, amounts[2], sc.ctx());
        route::clob_quote_to_base(&mut r, &mut mk, amounts[3], sc.ctx());
        let (out, unspent) = route::finish(r, sc.ctx());
        let (o, u) = (out.value(), unspent.value());

        coin::burn_for_testing(out);
        coin::burn_for_testing(unspent);
        ts::return_shared(cp);
        ts::return_shared(sp);
        ts::return_shared(cl);
        ts::return_shared(mk);
        sc.end();
        (o, u)
    }
}
