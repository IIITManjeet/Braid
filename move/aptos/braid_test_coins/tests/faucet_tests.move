#[test_only]
module braid_test_coins::faucet_tests {
    use aptos_framework::account;
    use aptos_framework::coin;

    use braid_test_coins::teth::{Self, TETH};
    use braid_test_coins::tusd::{Self, TUSD};

    #[test]
    fun anyone_can_mint_to_themselves() {
        // Genesis creates this on a real network; `aptos_account::deposit_coins`
        // consults it, and a unit test starts from empty storage.
        let framework = account::create_account_for_test(@aptos_framework);
        coin::create_coin_conversion_map(&framework);
        let publisher = account::create_account_for_test(@braid_test_coins);
        tusd::init_for_testing(&publisher);
        teth::init_for_testing(&publisher);

        let stranger = account::create_account_for_test(@0x5EED);
        tusd::mint_to_sender(&stranger, 1_000_000);
        teth::mint_to_sender(&stranger, 2_000_000_000);
        assert!(coin::balance<TUSD>(@0x5EED) == 1_000_000, 0);
        assert!(coin::balance<TETH>(@0x5EED) == 2_000_000_000, 1);
        assert!(coin::decimals<TUSD>() == 6 && coin::decimals<TETH>() == 9, 2);
    }
}
