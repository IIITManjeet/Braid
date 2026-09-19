// Route `B -> A` across all four venues in one transaction: the reverse of
// `route_a_to_b.move`, selling the book's base into its bids.
//
// One amount per venue, as in `route_a_to_b.move`.
script {
    use std::signer;
    use aptos_framework::aptos_account;
    use aptos_framework::coin;

    use braid_router::route;

    fun route_b_to_a<A, B>(
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

        let r = route::begin<B, A>(coin::withdraw<B>(trader, total), min_out);
        route::cpmm_b_to_a<A, B>(&mut r, cpmm_pool, cpmm_amount);
        route::stable_b_to_a<A, B>(&mut r, stable_pool, stable_amount);
        route::clmm_b_to_a<A, B>(&mut r, clmm_pool, clmm_amount);
        route::clob_base_to_quote<B, A>(&mut r, trader, market, clob_amount);
        let (out, unspent) = route::finish(r);

        let who = signer::address_of(trader);
        aptos_account::deposit_coins(who, out);
        aptos_account::deposit_coins(who, unspent);
    }
}
