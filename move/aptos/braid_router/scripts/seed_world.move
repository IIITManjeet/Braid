// Build `test_world::world` on a live network, in one transaction.
//
// Four venues on one pair, seeded exactly as the router tests seed theirs --
// which is what `braid-route --test-world` models. So a plan computed offline
// against that fixture predicts, to the unit, what `route_a_to_b` pays here.
//
// The pools are `Pool<A, B>` and the book is `Market<B, A>`. The seeder
// needs 29,200,000 A and 31,000,000 B: 25,000,000 of each for the three pools,
// then 6,000,000 B behind the asks and 4,200,000 A behind the bids, of which
// 200,000 comes straight back as change.
// The addresses come back in the `PoolCreated`, `StablePoolCreated` and
// `MarketCreated` events.
//
// The seeder is also the book's only maker, so the account that later takes
// from it must be a different one: the book's self-trade prevention would
// cancel the maker's own resting orders instead of filling them.
script {
    use std::signer;
    use aptos_framework::aptos_account;
    use aptos_framework::coin;
    use aptos_framework::primary_fungible_store;

    use braid_cpmm::pool as cpmm;
    use braid_stable::pool as stable;
    use braid_clmm::i32;
    use braid_clmm::pool as clmm;
    use braid_clob::book;
    use braid_clob::market as clob;

    fun seed_world<A, B>(seeder: &signer) {
        let who = signer::address_of(seeder);

        let (_, lp) = cpmm::create_pool<A, B>(
            coin::withdraw<A>(seeder, 10_000_000), coin::withdraw<B>(seeder, 10_000_000), 30,
        );
        primary_fungible_store::deposit(who, lp);

        let (_, slp) = stable::create_pool<A, B>(
            coin::withdraw<A>(seeder, 10_000_000), coin::withdraw<B>(seeder, 10_000_000), 10_000, 4,
        );
        primary_fungible_store::deposit(who, slp);

        // sqrt(1.0) in Q64.64: the same raw 1:1 price as every other venue.
        let pool = clmm::create_pool<A, B>(18446744073709551616, 30, 60);
        let (ra, rb) = clmm::add_liquidity<A, B>(
            seeder, pool, i32::neg_from(600), i32::from_u32(600),
            coin::withdraw<A>(seeder, 5_000_000), coin::withdraw<B>(seeder, 5_000_000),
        );
        aptos_account::deposit_coins(who, ra);
        aptos_account::deposit_coins(who, rb);

        let (market, cap) = clob::create_market<B, A>(100_000, 10_000, 10);
        clob::store_cap(seeder, cap);

        let asks = vector[1_000_100_000, 1_000_500_000, 1_001_000_000];
        let i = 0;
        while (i < 3) {
            let (out, change, _) = clob::place_ask<B, A>(
                seeder, market, asks[i], 2_000_000, book::gtc(), coin::withdraw<B>(seeder, 2_000_000),
            );
            aptos_account::deposit_coins(who, out);
            aptos_account::deposit_coins(who, change);
            i = i + 1;
        };
        let bids = vector[999_900_000, 999_500_000];
        let i = 0;
        while (i < 2) {
            let (out, change, _) = clob::place_bid<B, A>(
                seeder, market, bids[i], 2_000_000, book::gtc(), coin::withdraw<A>(seeder, 2_100_000),
            );
            aptos_account::deposit_coins(who, out);
            aptos_account::deposit_coins(who, change);
            i = i + 1;
        };
    }
}
