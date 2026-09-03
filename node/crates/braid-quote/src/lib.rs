//! A bit-exact Rust replica of Braid's on-chain pricing math.
//!
//! Each module mirrors one Move module function-for-function. The point is not
//! to have a second implementation — it is to have a second implementation that
//! can be *diffed* against the chain. `sui client ptb --dev-inspect` can call
//! the published pricing functions without submitting a transaction, so random
//! inputs can be pushed through both and compared to the unit.
//!
//! That only works because the Move math modules take and return plain
//! integers, with no Sui types anywhere in them. Keeping them object-free was a
//! day-one constraint chosen for exactly this test.

pub mod cpmm;
pub mod full_math;
pub mod stable;
