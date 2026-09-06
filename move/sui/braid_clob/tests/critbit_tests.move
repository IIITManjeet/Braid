#[test_only]
module braid_clob::critbit_tests {
    use sui::test_scenario::{Self as ts};
    use braid_clob::critbit::{Self, CritbitTree};

    const OWNER: address = @0xA;

    fun drain(tree: &mut CritbitTree<u64>): vector<u64> {
        let mut out = vector<u64>[];
        while (!critbit::is_empty(tree)) {
            let (k, _v) = critbit::pop_min(tree);
            out.push_back(k);
        };
        out
    }

    /// Store the key as its own value. Scaling it would overflow for the
    /// large keys some of these tests deliberately use.
    fun insert_all(tree: &mut CritbitTree<u64>, keys: vector<u64>) {
        let mut i = 0;
        while (i < keys.length()) {
            critbit::insert(tree, keys[i], keys[i]);
            i = i + 1;
        };
    }

    // ---------------------------------------------------------------- //
    // Basics                                                           //
    // ---------------------------------------------------------------- //

    #[test]
    fun an_empty_tree_knows_it_is_empty() {
        let mut sc = ts::begin(OWNER);
        {
            let tree = critbit::empty<u64>(sc.ctx());
            assert!(critbit::is_empty(&tree), 0);
            assert!(critbit::size(&tree) == 0, 1);
            assert!(critbit::min_leaf(&tree) == critbit::none_index(), 2);
            assert!(!critbit::contains(&tree, 42), 3);
            critbit::destroy_empty(tree);
        };
        sc.end();
    }

    #[test]
    fun one_key_is_both_the_minimum_and_the_maximum() {
        let mut sc = ts::begin(OWNER);
        {
            let mut tree = critbit::empty<u64>(sc.ctx());
            critbit::insert(&mut tree, 500, 5000);

            assert!(critbit::size(&tree) == 1, 0);
            assert!(critbit::min_key(&tree) == 500, 1);
            assert!(critbit::max_key(&tree) == 500, 2);
            assert!(critbit::contains(&tree, 500), 3);

            let (k, v) = critbit::pop_min(&mut tree);
            assert!(k == 500 && v == 5000, 4);
            critbit::destroy_empty(tree);
        };
        sc.end();
    }

    #[test]
    fun lookups_find_what_was_inserted_and_nothing_else() {
        let mut sc = ts::begin(OWNER);
        {
            let mut tree = critbit::empty<u64>(sc.ctx());
            insert_all(&mut tree, vector[100, 200, 300]);

            let (found, index) = critbit::find(&tree, 200);
            assert!(found, 0);
            assert!(*critbit::borrow_leaf(&tree, index) == 200, 1);
            assert!(critbit::leaf_key(&tree, index) == 200, 2);

            // A key that would land on an existing leaf but is not stored.
            let (missing, _) = critbit::find(&tree, 250);
            assert!(!missing, 3);

            drain(&mut tree);
            critbit::destroy_empty(tree);
        };
        sc.end();
    }

    // ---------------------------------------------------------------- //
    // Ordering -- the property the book depends on                     //
    // ---------------------------------------------------------------- //

    #[test]
    fun keys_come_out_sorted_however_they_went_in() {
        let mut sc = ts::begin(OWNER);
        {
            // Deliberately unsorted, with values that share high bits the way
            // real prices do.
            let mut tree = critbit::empty<u64>(sc.ctx());
            insert_all(&mut tree, vector[500, 100, 900, 300, 700, 200, 800, 400, 600]);
            assert!(critbit::size(&tree) == 9, 0);

            let sorted = drain(&mut tree);
            let expected = vector[100u64, 200, 300, 400, 500, 600, 700, 800, 900];
            assert!(sorted == expected, 1);
            critbit::destroy_empty(tree);
        };
        sc.end();
    }

    #[test]
    fun the_extremes_track_insertions() {
        let mut sc = ts::begin(OWNER);
        {
            let mut tree = critbit::empty<u64>(sc.ctx());

            critbit::insert(&mut tree, 500, 1);
            assert!(critbit::min_key(&tree) == 500 && critbit::max_key(&tree) == 500, 0);

            critbit::insert(&mut tree, 700, 1);
            assert!(critbit::min_key(&tree) == 500 && critbit::max_key(&tree) == 700, 1);

            critbit::insert(&mut tree, 300, 1);
            assert!(critbit::min_key(&tree) == 300 && critbit::max_key(&tree) == 700, 2);

            // Inserting between the extremes leaves them alone.
            critbit::insert(&mut tree, 600, 1);
            assert!(critbit::min_key(&tree) == 300 && critbit::max_key(&tree) == 700, 3);

            drain(&mut tree);
            critbit::destroy_empty(tree);
        };
        sc.end();
    }

    #[test]
    fun the_extremes_track_removals() {
        let mut sc = ts::begin(OWNER);
        {
            let mut tree = critbit::empty<u64>(sc.ctx());
            insert_all(&mut tree, vector[100, 200, 300, 400, 500]);

            critbit::remove(&mut tree, 100);
            assert!(critbit::min_key(&tree) == 200, 0);
            critbit::remove(&mut tree, 500);
            assert!(critbit::max_key(&tree) == 400, 1);

            // Removing from the middle moves neither.
            critbit::remove(&mut tree, 300);
            assert!(critbit::min_key(&tree) == 200 && critbit::max_key(&tree) == 400, 2);

            drain(&mut tree);
            critbit::destroy_empty(tree);
        };
        sc.end();
    }

    #[test]
    fun popping_from_both_ends_meets_in_the_middle() {
        let mut sc = ts::begin(OWNER);
        {
            let mut tree = critbit::empty<u64>(sc.ctx());
            insert_all(&mut tree, vector[10, 20, 30, 40, 50]);

            let (lo, _) = critbit::pop_min(&mut tree);
            let (hi, _) = critbit::pop_max(&mut tree);
            assert!(lo == 10 && hi == 50, 0);

            let (lo2, _) = critbit::pop_min(&mut tree);
            let (hi2, _) = critbit::pop_max(&mut tree);
            assert!(lo2 == 20 && hi2 == 40, 1);

            assert!(critbit::size(&tree) == 1, 2);
            assert!(critbit::min_key(&tree) == 30, 3);

            drain(&mut tree);
            critbit::destroy_empty(tree);
        };
        sc.end();
    }

    // ---------------------------------------------------------------- //
    // Shapes that stress the branching                                 //
    // ---------------------------------------------------------------- //

    #[test]
    fun keys_sharing_high_bits_still_order_correctly() {
        let mut sc = ts::begin(OWNER);
        {
            // Real prices cluster: these differ only in the low bits, which is
            // exactly the case a crit-bit tree is built for.
            let mut tree = critbit::empty<u64>(sc.ctx());
            insert_all(&mut tree, vector[
                1000000003, 1000000001, 1000000004, 1000000002, 1000000000,
            ]);
            let sorted = drain(&mut tree);
            assert!(sorted == vector[
                1000000000u64, 1000000001, 1000000002, 1000000003, 1000000004,
            ], 0);
            critbit::destroy_empty(tree);
        };
        sc.end();
    }

    #[test]
    fun adjacent_powers_of_two_branch_at_the_right_bit() {
        let mut sc = ts::begin(OWNER);
        {
            // Each of these differs from its neighbour in the highest bit,
            // which is the branch the tree has to get right.
            let mut tree = critbit::empty<u64>(sc.ctx());
            insert_all(&mut tree, vector[
                1u64 << 62, 1u64 << 10, 1u64 << 40, 1, 1u64 << 20,
            ]);
            let sorted = drain(&mut tree);
            assert!(sorted == vector[
                1u64, 1u64 << 10, 1u64 << 20, 1u64 << 40, 1u64 << 62,
            ], 0);
            critbit::destroy_empty(tree);
        };
        sc.end();
    }

    #[test]
    fun zero_and_the_maximum_key_are_ordinary_keys() {
        let mut sc = ts::begin(OWNER);
        {
            let mut tree = critbit::empty<u64>(sc.ctx());
            insert_all(&mut tree, vector[0, 18446744073709551615, 12345]);
            assert!(critbit::min_key(&tree) == 0, 0);
            assert!(critbit::max_key(&tree) == 18446744073709551615, 1);
            let sorted = drain(&mut tree);
            assert!(sorted == vector[0u64, 12345, 18446744073709551615], 2);
            critbit::destroy_empty(tree);
        };
        sc.end();
    }

    #[test]
    fun ascending_insertion_is_handled() {
        // A degenerate order for a naive tree; the crit-bit shape depends on
        // key bits rather than insertion order, so it should not matter.
        let mut sc = ts::begin(OWNER);
        {
            let mut tree = critbit::empty<u64>(sc.ctx());
            let mut i: u64 = 1;
            while (i <= 40) { critbit::insert(&mut tree, i, i); i = i + 1; };
            assert!(critbit::size(&tree) == 40, 0);
            assert!(critbit::min_key(&tree) == 1 && critbit::max_key(&tree) == 40, 1);

            let sorted = drain(&mut tree);
            let mut j = 0;
            while (j < 40) { assert!(sorted[j] == (j as u64) + 1, 2); j = j + 1; };
            critbit::destroy_empty(tree);
        };
        sc.end();
    }

    #[test]
    fun descending_insertion_is_handled() {
        let mut sc = ts::begin(OWNER);
        {
            let mut tree = critbit::empty<u64>(sc.ctx());
            let mut i: u64 = 40;
            while (i >= 1) { critbit::insert(&mut tree, i, i); i = i - 1; };
            assert!(critbit::size(&tree) == 40, 0);

            let sorted = drain(&mut tree);
            let mut j = 0;
            while (j < 40) { assert!(sorted[j] == (j as u64) + 1, 1); j = j + 1; };
            critbit::destroy_empty(tree);
        };
        sc.end();
    }

    #[test]
    fun the_tree_survives_interleaved_inserts_and_removals() {
        // The pattern a live book actually produces: levels appear, get eaten,
        // and reappear while others persist.
        let mut sc = ts::begin(OWNER);
        {
            let mut tree = critbit::empty<u64>(sc.ctx());
            insert_all(&mut tree, vector[50, 20, 80, 10, 60, 90, 30]);

            critbit::remove(&mut tree, 20);
            critbit::remove(&mut tree, 80);
            critbit::insert(&mut tree, 70, 700);
            critbit::insert(&mut tree, 40, 400);
            critbit::remove(&mut tree, 50);
            critbit::insert(&mut tree, 20, 200);

            assert!(critbit::size(&tree) == 7, 0);
            let sorted = drain(&mut tree);
            assert!(sorted == vector[10u64, 20, 30, 40, 60, 70, 90], 1);
            critbit::destroy_empty(tree);
        };
        sc.end();
    }

    #[test]
    fun values_can_be_edited_in_place() {
        // A price level's resting quantity changes as orders fill, without the
        // level itself moving.
        let mut sc = ts::begin(OWNER);
        {
            let mut tree = critbit::empty<u64>(sc.ctx());
            let index = critbit::insert(&mut tree, 100, 1000);

            let slot = critbit::borrow_leaf_mut(&mut tree, index);
            *slot = *slot - 250;
            assert!(*critbit::borrow_leaf(&tree, index) == 750, 0);

            drain(&mut tree);
            critbit::destroy_empty(tree);
        };
        sc.end();
    }

    // ---------------------------------------------------------------- //
    // Guards                                                           //
    // ---------------------------------------------------------------- //

    #[test]
    #[expected_failure(abort_code = braid_clob::critbit::EKeyExists)]
    fun inserting_a_duplicate_key_is_rejected() {
        let mut sc = ts::begin(OWNER);
        {
            let mut tree = critbit::empty<u64>(sc.ctx());
            critbit::insert(&mut tree, 100, 1);
            critbit::insert(&mut tree, 100, 2);
            drain(&mut tree);
            critbit::destroy_empty(tree);
        };
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_clob::critbit::EKeyNotFound)]
    fun removing_a_missing_key_is_rejected() {
        let mut sc = ts::begin(OWNER);
        {
            let mut tree = critbit::empty<u64>(sc.ctx());
            critbit::insert(&mut tree, 100, 1);
            critbit::remove(&mut tree, 200);
            drain(&mut tree);
            critbit::destroy_empty(tree);
        };
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_clob::critbit::EEmptyTree)]
    fun popping_an_empty_tree_is_rejected() {
        let mut sc = ts::begin(OWNER);
        {
            let mut tree = critbit::empty<u64>(sc.ctx());
            let (_k, _v) = critbit::pop_min(&mut tree);
            critbit::destroy_empty(tree);
        };
        sc.end();
    }
}
