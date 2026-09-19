/// TUSD -- a test stablecoin for exercising Braid on testnet.
///
/// # Deliberately unsafe. Never deploy this shape to mainnet.
///
/// Anyone can mint any amount. That is exactly what you want from a testnet
/// faucet coin and exactly what you never want from a real one.
///
/// Sui makes that open mint by sharing the `TreasuryCap`. Aptos has no
/// shared objects, and `coin::initialize` demands the signer of the address
/// that declares the type -- so the publisher mints the type once, in
/// `init_module`, and parks the `MintCapability` under its own account where
/// only this module can reach it. The module then lends it to everyone.
module braid_test_coins::tusd {
    use std::signer;
    use std::string;
    use aptos_framework::aptos_account;
    use aptos_framework::coin::{Self, Coin, MintCapability};

    struct TUSD {}

    struct Faucet has key {
        mint: MintCapability<TUSD>,
    }

    /// Runs once, at publish, with the publisher's signer.
    fun init_module(publisher: &signer) {
        let (burn, freeze, mint) = coin::initialize<TUSD>(
            publisher,
            string::utf8(b"Braid Test USD"),
            string::utf8(b"TUSD"),
            6,
            true,
        );
        coin::destroy_burn_cap(burn);
        coin::destroy_freeze_cap(freeze);
        move_to(publisher, Faucet { mint });
    }

    /// Mint `amount` base units. Returns the coin so Move code can use it.
    public fun mint(amount: u64): Coin<TUSD> acquires Faucet {
        coin::mint(amount, &borrow_global<Faucet>(@braid_test_coins).mint)
    }

    /// Mint straight to the caller. The form a plain `aptos move run` wants.
    public entry fun mint_to_sender(caller: &signer, amount: u64) acquires Faucet {
        aptos_account::deposit_coins(signer::address_of(caller), mint(amount));
    }

    #[test_only]
    public fun init_for_testing(publisher: &signer) { init_module(publisher) }
}
