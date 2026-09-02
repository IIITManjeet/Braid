/// TUSD -- a test stablecoin for exercising Braid on testnet.
///
/// # Deliberately unsafe. Never deploy this shape to mainnet.
///
/// The `TreasuryCap` is **shared**, so anyone can mint any amount. That is
/// exactly what you want from a testnet faucet coin and exactly what you never
/// want from a real one. No admin, no cap, no access control.
///
/// This package exists so the pools can be driven end to end on a live network:
/// `braid_cpmm` and `braid_stable` are generic over their coin types, so a
/// deployment with no concrete coins is bytecode nobody can call.
module braid_test_coins::tusd {
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::coin_registry;

    /// One-time witness. Must match the module name in uppercase, carry only
    /// `drop`, and have no fields -- that is what makes it unforgeable and
    /// guarantees `init` runs exactly once, at publish.
    public struct TUSD has drop {}

    fun init(otw: TUSD, ctx: &mut TxContext) {
        let (builder, treasury) = coin_registry::new_currency_with_otw(
            otw,
            6,
            b"TUSD".to_string(),
            b"Braid Test USD".to_string(),
            b"Test stablecoin for Braid. Testnet only, anyone can mint.".to_string(),
            b"".to_string(),
            ctx,
        );
        // Drops the MetadataCap, so name/symbol/decimals are frozen forever.
        coin_registry::finalize_and_delete_metadata_cap(builder, ctx);
        // Shared: any address can mint. Testnet faucet behaviour.
        transfer::public_share_object(treasury);
    }

    /// Mint `amount` base units. Returns the coin so a PTB can chain off it.
    public fun mint(
        treasury: &mut TreasuryCap<TUSD>,
        amount: u64,
        ctx: &mut TxContext,
    ): Coin<TUSD> {
        coin::mint(treasury, amount, ctx)
    }

    /// Mint straight to the caller. The form a plain `sui client call` wants.
    #[allow(lint(self_transfer))]
    public fun mint_to_sender(
        treasury: &mut TreasuryCap<TUSD>,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        transfer::public_transfer(coin::mint(treasury, amount, ctx), ctx.sender());
    }
}
