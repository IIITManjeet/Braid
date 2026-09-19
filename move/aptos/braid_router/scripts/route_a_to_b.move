// Route `A -> B` across all four venues in one transaction.
//
// This is the Aptos counterpart of the PTB `scripts/route.py` builds on Sui.
// The pools are `Pool<A, B>` and the book is `Market<B, A>` -- base is what
// the route buys -- which is the shape of the testnet deployment.
//
// One amount per venue, in the order `braid-route` plans in. Four scalars
// rather than a `vector<u64>`: a script argument can be a `vector<u8>` and
// nothing wider.
//
// A zero leg is skipped before its venue is touched, so an unused venue's
// address may be anything.
//
// Remove the `finish` line and this file stops compiling: the `Route` from
// `begin` has no `drop`, and a script cannot return while holding it.
script {
    use std::signer;
    use aptos_framework::aptos_account;
    use aptos_framework::coin;

    use braid_router::route;

    fun route_a_to_b<A, B>(
        trader: &signer,
        cpmm_pool: address,
        stable_pool: address,
        clmm_pool: address,
        market: address,
        cpmm_amount: u64,
        stable_amount: u64,
        clmm_amount: u64,
        clob_amount: u64,
        min_out: u64,
    ) {
        let total = cpmm_amount + stable_amount + clmm_amount + clob_amount;

        let r = route::begin<A, B>(coin::withdraw<A>(trader, total), min_out);
        route::cpmm_a_to_b(&mut r, cpmm_pool, cpmm_amount);
        route::stable_a_to_b(&mut r, stable_pool, stable_amount);
        route::clmm_a_to_b(&mut r, clmm_pool, clmm_amount);
        route::clob_quote_to_base<B, A>(&mut r, trader, market, clob_amount);
        let (out, unspent) = route::finish(r);

        let who = signer::address_of(trader);
        aptos_account::deposit_coins(who, out);
        aptos_account::deposit_coins(who, unspent);
    }
}
