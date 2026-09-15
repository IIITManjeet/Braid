//! A bit-exact Rust replica of Braid's on-chain pricing math.
//!
//! Each module mirrors one Move module function-for-function. The point is not
//! to have a second implementation -- it is to have a second implementation that
//! can be *diffed* against the chain. `braid-difftest` generates random cases,
//! computes each answer here, and emits them as Move tests that the Move VM
//! checks against the real source.
//!
//! That only works because the Move math modules take and return plain
//! integers, with no Sui types anywhere in them. Keeping them object-free was a
//! day-one constraint chosen for exactly this test. The two venues whose price
//! depends on stored state -- the concentrated pool's ticks and the book's
//! levels -- are mirrored as snapshots of exactly that state.

pub mod clmm;
pub mod clob;
pub mod cpmm;
pub mod full_math;
pub mod stable;
