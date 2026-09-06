/// A crit-bit tree keyed by `u64`, used to hold an order book's price levels.
///
/// # Why not a plain table
///
/// A book needs the *best* price constantly -- every match starts by asking
/// "what is the lowest ask" -- and needs to walk outward from there as levels
/// are consumed. A hash table gives none of that: it can find a known price but
/// cannot say which price is smallest without scanning everything.
///
/// A crit-bit tree keeps keys in order, so the minimum and maximum are cached
/// pointers rather than searches, and insertion and removal are proportional to
/// the number of bits in a key rather than the number of orders.
///
/// # How it works
///
/// The tree branches on single bits. Each internal node stores a *mask* with
/// exactly one bit set -- the highest bit on which the keys below it disagree.
/// Descending, a key goes right when it has that bit and left when it does not,
/// which is why an in-order walk comes out sorted: at every branch, everything
/// with the bit set is larger than everything without it.
///
/// Only bits that actually distinguish stored keys get a node, so the depth
/// tracks how similar the keys are rather than how many there are. Prices in a
/// book cluster tightly, which is the case this structure is best at.
///
/// # Index encoding
///
/// Internal nodes and leaves live in separate tables but are referred to by one
/// index space, so a child pointer can name either. Leaves have the top bit set
/// and internal nodes do not, which makes "is this a leaf" a comparison rather
/// than a lookup.
module braid_clob::critbit {
    use sui::table::{Self, Table};
    use braid_math::full_math;

    /// The key is already in the tree.
    const EKeyExists: u64 = 0;
    /// No such key.
    const EKeyNotFound: u64 = 1;
    /// Asked for the extreme of an empty tree.
    const EEmptyTree: u64 = 2;

    /// Leaf indices carry this bit; internal indices do not.
    const PARTITION: u64 = 0x8000000000000000;
    /// A null pointer. Not a valid index of either kind.
    const NONE: u64 = 0xFFFFFFFFFFFFFFFF;

    public struct InternalNode has store, drop {
        /// One bit set: the highest bit on which the subtrees disagree.
        mask: u64,
        left: u64,
        right: u64,
        parent: u64,
    }

    public struct Leaf<V: store> has store {
        key: u64,
        value: V,
        parent: u64,
    }

    public struct CritbitTree<V: store> has store {
        root: u64,
        internal: Table<u64, InternalNode>,
        leaves: Table<u64, Leaf<V>>,
        /// Cached extremes, so best-bid and best-ask are reads, not searches.
        min_leaf: u64,
        max_leaf: u64,
        next_internal: u64,
        next_leaf: u64,
        size: u64,
    }

    // ------------------------------------------------------------------ //
    // Construction                                                       //
    // ------------------------------------------------------------------ //

    public fun empty<V: store>(ctx: &mut TxContext): CritbitTree<V> {
        CritbitTree {
            root: NONE,
            internal: table::new(ctx),
            leaves: table::new(ctx),
            min_leaf: NONE,
            max_leaf: NONE,
            next_internal: 0,
            next_leaf: 0,
            size: 0,
        }
    }

    public fun size<V: store>(tree: &CritbitTree<V>): u64 { tree.size }

    public fun is_empty<V: store>(tree: &CritbitTree<V>): bool { tree.size == 0 }

    public fun is_leaf_index(index: u64): bool { index >= PARTITION && index != NONE }

    public fun none_index(): u64 { NONE }

    // ------------------------------------------------------------------ //
    // Lookup                                                             //
    // ------------------------------------------------------------------ //

    /// Descend to the leaf a key would occupy. Does not check it matches --
    /// the tree only branches on bits that distinguish *stored* keys, so a
    /// missing key still lands somewhere.
    fun descend<V: store>(tree: &CritbitTree<V>, key: u64): u64 {
        let mut current = tree.root;
        while (current < PARTITION) {
            let node = table::borrow(&tree.internal, current);
            current = if (key & node.mask != 0) { node.right } else { node.left };
        };
        current
    }

    /// `(found, leaf_index)`.
    public fun find<V: store>(tree: &CritbitTree<V>, key: u64): (bool, u64) {
        if (tree.root == NONE) return (false, NONE);
        let leaf = descend(tree, key);
        if (table::borrow(&tree.leaves, leaf).key == key) { (true, leaf) } else { (false, NONE) }
    }

    public fun contains<V: store>(tree: &CritbitTree<V>, key: u64): bool {
        let (found, _) = find(tree, key);
        found
    }

    public fun borrow_leaf<V: store>(tree: &CritbitTree<V>, index: u64): &V {
        &table::borrow(&tree.leaves, index).value
    }

    public fun borrow_leaf_mut<V: store>(tree: &mut CritbitTree<V>, index: u64): &mut V {
        &mut table::borrow_mut(&mut tree.leaves, index).value
    }

    public fun leaf_key<V: store>(tree: &CritbitTree<V>, index: u64): u64 {
        table::borrow(&tree.leaves, index).key
    }

    // ------------------------------------------------------------------ //
    // Extremes                                                           //
    // ------------------------------------------------------------------ //

    /// Index of the smallest key. `NONE` if empty.
    public fun min_leaf<V: store>(tree: &CritbitTree<V>): u64 { tree.min_leaf }

    /// Index of the largest key. `NONE` if empty.
    public fun max_leaf<V: store>(tree: &CritbitTree<V>): u64 { tree.max_leaf }

    public fun min_key<V: store>(tree: &CritbitTree<V>): u64 {
        assert!(tree.size > 0, EEmptyTree);
        table::borrow(&tree.leaves, tree.min_leaf).key
    }

    public fun max_key<V: store>(tree: &CritbitTree<V>): u64 {
        assert!(tree.size > 0, EEmptyTree);
        table::borrow(&tree.leaves, tree.max_leaf).key
    }

    fun leftmost<V: store>(tree: &CritbitTree<V>, from: u64): u64 {
        let mut current = from;
        while (current < PARTITION) {
            current = table::borrow(&tree.internal, current).left;
        };
        current
    }

    fun rightmost<V: store>(tree: &CritbitTree<V>, from: u64): u64 {
        let mut current = from;
        while (current < PARTITION) {
            current = table::borrow(&tree.internal, current).right;
        };
        current
    }

    // ------------------------------------------------------------------ //
    // Insertion                                                          //
    // ------------------------------------------------------------------ //

    /// The highest bit on which two keys differ, as a mask with one bit set.
    fun critical_bit(a: u64, b: u64): u64 {
        let difference = a ^ b;
        let bits = full_math::bit_length((difference as u256));
        1u64 << ((bits - 1) as u8)
    }

    fun set_parent<V: store>(tree: &mut CritbitTree<V>, index: u64, parent: u64) {
        if (index >= PARTITION) {
            table::borrow_mut(&mut tree.leaves, index).parent = parent;
        } else {
            table::borrow_mut(&mut tree.internal, index).parent = parent;
        };
    }

    /// Insert a key. Returns the leaf index, which stays valid until removal.
    public fun insert<V: store>(tree: &mut CritbitTree<V>, key: u64, value: V): u64 {
        let leaf_index = PARTITION + tree.next_leaf;
        tree.next_leaf = tree.next_leaf + 1;

        if (tree.root == NONE) {
            table::add(&mut tree.leaves, leaf_index, Leaf { key, value, parent: NONE });
            tree.root = leaf_index;
            tree.min_leaf = leaf_index;
            tree.max_leaf = leaf_index;
            tree.size = 1;
            return leaf_index
        };

        let closest = descend(tree, key);
        let closest_key = table::borrow(&tree.leaves, closest).key;
        assert!(closest_key != key, EKeyExists);

        let mask = critical_bit(closest_key, key);

        // Descend again, stopping where the branch becomes less significant
        // than the new one -- that is where the new node belongs.
        let mut parent = NONE;
        let mut current = tree.root;
        while (current < PARTITION) {
            let node = table::borrow(&tree.internal, current);
            if (node.mask <= mask) break;
            parent = current;
            current = if (key & node.mask != 0) { node.right } else { node.left };
        };

        table::add(&mut tree.leaves, leaf_index, Leaf { key, value, parent: NONE });

        let internal_index = tree.next_internal;
        tree.next_internal = tree.next_internal + 1;
        // The side the new key falls on is decided by the critical bit.
        let (left, right) = if (key & mask != 0) { (current, leaf_index) } else { (leaf_index, current) };
        table::add(&mut tree.internal, internal_index, InternalNode { mask, left, right, parent });

        set_parent(tree, current, internal_index);
        set_parent(tree, leaf_index, internal_index);

        if (parent == NONE) {
            tree.root = internal_index;
        } else {
            let p = table::borrow_mut(&mut tree.internal, parent);
            if (p.left == current) { p.left = internal_index } else { p.right = internal_index };
        };

        tree.size = tree.size + 1;
        if (key < table::borrow(&tree.leaves, tree.min_leaf).key) { tree.min_leaf = leaf_index };
        if (key > table::borrow(&tree.leaves, tree.max_leaf).key) { tree.max_leaf = leaf_index };

        leaf_index
    }

    // ------------------------------------------------------------------ //
    // Removal                                                            //
    // ------------------------------------------------------------------ //

    /// Remove by leaf index, returning the stored value.
    ///
    /// Removing a leaf also removes its parent branch: with one child gone the
    /// branch no longer distinguishes anything, so the surviving sibling is
    /// promoted into its place. That is what keeps the tree free of nodes that
    /// only have one child.
    public fun remove_leaf<V: store>(tree: &mut CritbitTree<V>, index: u64): V {
        let Leaf { key: _, value, parent } = table::remove(&mut tree.leaves, index);
        tree.size = tree.size - 1;

        if (parent == NONE) {
            // The tree was a single leaf.
            tree.root = NONE;
            tree.min_leaf = NONE;
            tree.max_leaf = NONE;
            return value
        };

        let InternalNode { mask: _, left, right, parent: grandparent } =
            table::remove(&mut tree.internal, parent);
        let sibling = if (left == index) { right } else { left };

        set_parent(tree, sibling, grandparent);
        if (grandparent == NONE) {
            tree.root = sibling;
        } else {
            let g = table::borrow_mut(&mut tree.internal, grandparent);
            if (g.left == parent) { g.left = sibling } else { g.right = sibling };
        };

        tree.min_leaf = leftmost(tree, tree.root);
        tree.max_leaf = rightmost(tree, tree.root);
        value
    }

    public fun remove<V: store>(tree: &mut CritbitTree<V>, key: u64): V {
        let (found, index) = find(tree, key);
        assert!(found, EKeyNotFound);
        remove_leaf(tree, index)
    }

    /// Remove and return the smallest entry as `(key, value)`.
    public fun pop_min<V: store>(tree: &mut CritbitTree<V>): (u64, V) {
        assert!(tree.size > 0, EEmptyTree);
        let index = tree.min_leaf;
        let key = table::borrow(&tree.leaves, index).key;
        (key, remove_leaf(tree, index))
    }

    /// Remove and return the largest entry as `(key, value)`.
    public fun pop_max<V: store>(tree: &mut CritbitTree<V>): (u64, V) {
        assert!(tree.size > 0, EEmptyTree);
        let index = tree.max_leaf;
        let key = table::borrow(&tree.leaves, index).key;
        (key, remove_leaf(tree, index))
    }

    // ------------------------------------------------------------------ //
    // Teardown                                                           //
    // ------------------------------------------------------------------ //

    /// Destroy an empty tree. A non-empty one cannot be dropped, because its
    /// values might not be droppable -- the caller has to drain it first.
    public fun destroy_empty<V: store>(tree: CritbitTree<V>) {
        let CritbitTree {
            root: _, internal, leaves, min_leaf: _, max_leaf: _,
            next_internal: _, next_leaf: _, size,
        } = tree;
        assert!(size == 0, EEmptyTree);
        table::destroy_empty(internal);
        table::destroy_empty(leaves);
    }
}
