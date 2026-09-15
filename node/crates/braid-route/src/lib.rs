//! Splitting one exact-in order across the four venues.
//!
//! # The objective
//!
//! Given `X` of the input token and venues with output functions `f_i`,
//! choose `x_i` with `sum(x_i) <= X` to maximise `sum(f_i(x_i))`. The legs
//! touch different objects, so they do not interact: the route's total is
//! exactly the sum of each venue's quote at its own allocation. That is what
//! lets a plan computed here be enforced to the unit on chain.
//!
//! # Marginal-price equalisation, discretely
//!
//! For smooth concave `f_i` the optimum is where every venue in use has the
//! same marginal output `f_i'(x_i)` -- if one paid more for the next unit, the
//! unit should move there. Here the `f_i` are not smooth. They are integer
//! functions with floor rounding, the book moves in whole lots and is flat
//! within a level, and a concentrated pool's slope jumps at every initialized
//! tick. So the equalisation is done on finite differences instead:
//!
//! 1. **Fill.** Hand the input out in chunks, each to the venue whose output
//!    rises most for it. For concave `f_i` this greedy is already optimal at
//!    the chunk's resolution.
//! 2. **Rebalance.** Try moving `step` from any venue to any other, keeping
//!    every move that raises the total, until none does. Then halve `step` and
//!    repeat, down to a single unit. This is what repairs the places greedy
//!    gets wrong -- a lot boundary that made one chunk look worthless, a tick
//!    crossing that made one look better than its neighbours.
//!
//! Unspent input is modelled as a venue that pays nothing, so moving input out
//! of a leg that cannot use it is just another rebalancing move.
//!
//! # What it guarantees
//!
//! Not the global optimum of an arbitrary integer function; the search is
//! local. It does guarantee that no single transfer of any power-of-two size
//! between two venues improves the result, that the result is never worse
//! than the best single venue (that allocation is tried explicitly), and that
//! every leg it emits is one the chain will accept.
//!
//! Against exhaustive search it can fall short by rounding: every leg's
//! output is floored, so the total is a staircase, and the search can settle
//! a step below the top. The tests measure that at no more than one unit per
//! leg on the cases small enough to search exhaustively.

use braid_quote::{clmm, clob, cpmm, stable};

pub mod snapshot;

/// One venue, in the direction the order trades through it.
#[derive(Debug, Clone)]
pub enum Venue {
    Cpmm { reserve_in: u64, reserve_out: u64, fee_bps: u64 },
    Stable { reserve_in: u64, reserve_out: u64, amp: u64, fee_bps: u64 },
    Clmm { pool: clmm::Pool, zero_for_one: bool },
    ClobBuyBase { book: clob::Book },
    ClobSellBase { book: clob::Book },
}

impl Venue {
    pub fn kind(&self) -> &'static str {
        match self {
            Venue::Cpmm { .. } => "cpmm",
            Venue::Stable { .. } => "stable",
            Venue::Clmm { .. } => "clmm",
            Venue::ClobBuyBase { .. } | Venue::ClobSellBase { .. } => "clob",
        }
    }

    /// `(output, input_spent)` for a leg of `amount`.
    ///
    /// A leg the chain would abort -- a pool asserting a non-zero output, a
    /// solver failing to converge -- quotes as `(0, 0)`, so the optimizer sees
    /// it as worthless and never keeps input there.
    pub fn quote(&self, amount: u64) -> (u64, u64) {
        if amount == 0 {
            return (0, 0);
        }
        match self {
            Venue::Cpmm { reserve_in, reserve_out, fee_bps } => {
                match cpmm::amount_out(amount, *reserve_in, *reserve_out, *fee_bps) {
                    Ok(out) if out > 0 => (out, amount),
                    _ => (0, 0),
                }
            }
            Venue::Stable { reserve_in, reserve_out, amp, fee_bps } => {
                match stable::amount_out(amount, *reserve_in, *reserve_out, *amp, *fee_bps) {
                    Ok(out) if out > 0 => (out, amount),
                    _ => (0, 0),
                }
            }
            Venue::Clmm { pool, zero_for_one } => match pool.quote(amount, *zero_for_one) {
                Ok((spent, out)) => (out, spent),
                Err(_) => (0, 0),
            },
            Venue::ClobBuyBase { book } => book.quote_quote_for_base(amount),
            Venue::ClobSellBase { book } => book.quote_base_for_quote(amount),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Leg {
    /// Index into the venue list.
    pub venue: usize,
    /// What the route hands the venue.
    pub amount: u64,
    /// What the venue consumes of it; the rest returns to the route.
    pub spent: u64,
    pub out: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Plan {
    pub amount_in: u64,
    /// Non-empty legs, in venue order.
    pub legs: Vec<Leg>,
    pub total_out: u64,
    /// Input the route will return: never allocated, or handed back by a leg.
    pub unspent: u64,
    /// `(venue, output)` of the best all-in-one-venue alternative.
    pub best_single: Option<(usize, u64)>,
}

/// Chunks the fill phase hands out. Enough that one chunk is a small slice of
/// any sensible order, few enough that the fill is cheap; rebalancing takes
/// the resolution the rest of the way down.
const FILL_CHUNKS: u64 = 256;

/// Offer `amount` to a venue and keep only what it consumes.
///
/// Returns `(amount, out)` with `amount` trimmed to the venue's spend. A book
/// buys whole lots and a concentrated pool can run out of range, and in both
/// cases the rest of the offer comes back. Pricing that remainder as worthless
/// is the mistake to avoid: it is still input, and another venue can use it.
/// Trimming is repeated because re-quoting the trimmed amount can, at a range
/// edge, consume slightly less again.
fn settle(venue: &Venue, amount: u64) -> (u64, u64) {
    let (mut out, mut spent) = venue.quote(amount);
    let mut amount = spent;
    for _ in 0..4 {
        (out, spent) = venue.quote(amount);
        if spent == amount {
            break;
        }
        amount = spent;
    }
    if out == 0 { (0, 0) } else { (amount, out) }
}

/// `a_gain / a_used > b_gain / b_used`, without division.
fn better_rate(a_gain: u64, a_used: u64, b_gain: u64, b_used: u64) -> bool {
    a_gain as u128 * b_used as u128 > b_gain as u128 * a_used as u128
}

pub fn optimize(venues: &[Venue], amount_in: u64) -> Plan {
    let n = venues.len();
    // Every allocation is kept equal to what its venue actually consumes, so
    // `left` is all the input not yet doing anything.
    let mut alloc = vec![0u64; n];
    let mut outs = vec![0u64; n];
    let mut left = amount_in;

    // --- fill ---------------------------------------------------------------
    //
    // Chunks go to the best *rate*, output per unit consumed, not the biggest
    // gain per chunk offered. The difference is the book: offered a chunk, it
    // buys whole lots and hands back the rest, and by gain-per-offer it would
    // lose to any pool on every chunk and never be used at all.
    let chunk = (amount_in / FILL_CHUNKS).max(1);
    while left > 0 {
        let mut c = chunk.min(left);
        let pick = loop {
            let mut best: Option<(usize, u64, u64)> = None; // (venue, new_alloc, new_out)
            for i in 0..n {
                let (a, o) = settle(&venues[i], alloc[i] + c);
                if a <= alloc[i] || o <= outs[i] {
                    continue;
                }
                let replace = match best {
                    None => true,
                    Some((j, bj, oj)) => {
                        better_rate(o - outs[i], a - alloc[i], oj - outs[j], bj - alloc[j])
                    }
                };
                if replace {
                    best = Some((i, a, o));
                }
            }
            // Too small for anything to use -- a lot, or a fee rounding the
            // whole chunk away. Grow it until something can.
            match best {
                Some(b) => break Some(b),
                None if c < left => c = (c * 2).min(left),
                None => break None,
            }
        };
        let Some((i, a, o)) = pick else { break };
        left -= a - alloc[i];
        alloc[i] = a;
        outs[i] = o;
    }

    // --- rebalance ----------------------------------------------------------
    //
    // Each candidate offers `step` more to `to`, sees how much it actually
    // takes, and funds exactly that from the unspent input or from another
    // venue. Kept if the total rises.
    //
    // Steps start at the size of the whole order, not the fill chunk. A venue
    // with a minimum useful size -- the book's lot -- larger than a chunk gets
    // nothing from the fill, and if rebalancing only ever offered it chunks it
    // would never get anything at all. That was a real miss: a 828,352 order
    // went entirely to the stable pool, 227 units short of what splitting it
    // with the book pays.
    let mut step = amount_in.checked_next_power_of_two().unwrap_or(1 << 63);
    while step > 0 {
        loop {
            let mut improved = false;
            for to in 0..n {
                let (a_to, o_to) = settle(&venues[to], alloc[to] + step);
                if a_to <= alloc[to] {
                    continue;
                }
                let need = a_to - alloc[to];

                if left >= need && o_to > outs[to] {
                    left -= need;
                    alloc[to] = a_to;
                    outs[to] = o_to;
                    improved = true;
                    continue;
                }

                for from in 0..n {
                    if from == to || alloc[from] < need {
                        continue;
                    }
                    let (a_from, o_from) = settle(&venues[from], alloc[from] - need);
                    // Taking `need` from a book can free more than `need`: it
                    // gives up a whole lot. Offer everything freed to `to`, or
                    // a lot-sized move would be judged on only part of its
                    // proceeds and never made.
                    let freed = alloc[from] - a_from;
                    let (a_to, o_to) =
                        if freed == need { (a_to, o_to) } else { settle(&venues[to], alloc[to] + freed) };
                    if a_to < alloc[to] {
                        continue;
                    }
                    if o_to as u128 + o_from as u128 > outs[to] as u128 + outs[from] as u128 {
                        left += freed - (a_to - alloc[to]);
                        alloc[from] = a_from;
                        outs[from] = o_from;
                        alloc[to] = a_to;
                        outs[to] = o_to;
                        improved = true;
                        break;
                    }
                }
            }
            if !improved {
                break;
            }
        }
        step /= 2;
    }

    // --- never worse than one venue -----------------------------------------
    let best_single = (0..n)
        .map(|i| (i, venues[i].quote(amount_in).0))
        .max_by_key(|&(i, out)| (out, std::cmp::Reverse(i)));
    let split_total: u64 = outs.iter().sum();
    if let Some((i, single)) = best_single {
        if single > split_total {
            alloc.iter_mut().for_each(|a| *a = 0);
            alloc[i] = amount_in;
        }
    }

    build_plan(venues, amount_in, &alloc, best_single)
}

/// Price an explicit allocation. Also what `optimize` finishes with, so a plan
/// is always the replica's verdict on its own legs, never an accumulator.
pub fn build_plan(
    venues: &[Venue],
    amount_in: u64,
    alloc: &[u64],
    best_single: Option<(usize, u64)>,
) -> Plan {
    let mut legs = Vec::new();
    for (venue, &amount) in alloc.iter().enumerate() {
        if amount == 0 {
            continue;
        }
        let (out, spent) = venues[venue].quote(amount);
        if out == 0 {
            // The chain would abort this leg; leave its input in the route.
            continue;
        }
        legs.push(Leg { venue, amount, spent, out });
    }
    let total_out = legs.iter().map(|l| l.out).sum();
    let spent: u64 = legs.iter().map(|l| l.spent).sum();
    Plan { amount_in, legs, total_out, unspent: amount_in - spent, best_single }
}

/// `total * (10000 - slippage_bps) / 10000`, floored.
pub fn min_out(total_out: u64, slippage_bps: u64) -> u64 {
    (total_out as u128 * (10_000 - slippage_bps.min(10_000)) as u128 / 10_000) as u64
}

pub mod fixtures {
    use super::*;

    /// `braid_router::test_world::world`, as seen by a USD -> ETH order, in
    /// the leg order `buy_eth` takes: `[cpmm, stable, clmm, clob]`.
    ///
    /// The generated route tests are what keep this honest: they execute plans
    /// computed against this copy on the Move one, at a `min_out` of exactly
    /// the predicted output.
    pub fn router_test_world() -> Vec<Venue> {
        let mut pool = clmm::Pool::new(1 << 64, 30, 60).unwrap();
        pool.add_liquidity(-600, 600, 5_000_000, 5_000_000).unwrap();
        let mut book = clob::Book::new(100_000, 10_000, 10);
        book.rest(1_000_100_000, 2_000_000, false);
        book.rest(1_000_500_000, 2_000_000, false);
        book.rest(1_001_000_000, 2_000_000, false);
        book.rest(999_900_000, 2_000_000, true);
        book.rest(999_500_000, 2_000_000, true);
        vec![
            Venue::Cpmm { reserve_in: 10_000_000, reserve_out: 10_000_000, fee_bps: 30 },
            Venue::Stable { reserve_in: 10_000_000, reserve_out: 10_000_000, amp: 10_000, fee_bps: 4 },
            Venue::Clmm { pool, zero_for_one: true },
            Venue::ClobBuyBase { book },
        ]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn world() -> Vec<Venue> {
        fixtures::router_test_world()
    }

    #[test]
    fn a_plan_is_exactly_the_sum_of_its_legs() {
        let venues = world();
        let plan = optimize(&venues, 8_000_000);
        let legs_in: u64 = plan.legs.iter().map(|l| l.amount).sum();
        assert!(legs_in <= plan.amount_in);
        for leg in &plan.legs {
            assert_eq!(venues[leg.venue].quote(leg.amount), (leg.out, leg.spent));
        }
        assert_eq!(plan.total_out, plan.legs.iter().map(|l| l.out).sum::<u64>());
    }

    #[test]
    fn the_split_beats_every_single_venue_and_the_hand_split() {
        let venues = world();
        let plan = optimize(&venues, 8_000_000);
        for (i, v) in venues.iter().enumerate() {
            assert!(plan.total_out > v.quote(8_000_000).0, "venue {i}");
        }
        // route_tests::a_split_beats_sending_everything_to_any_one_venue.
        let hand = build_plan(&venues, 8_000_000, &[50_000, 3_900_000, 600_000, 3_450_000], None);
        assert!(plan.total_out >= hand.total_out, "{} < {}", plan.total_out, hand.total_out);
    }

    #[test]
    fn no_single_transfer_improves_the_result() {
        let venues = world();
        for amount in [10_000, 777_777, 3_000_000, 8_000_000, 25_000_000] {
            let plan = optimize(&venues, amount);
            let mut alloc = vec![0u64; venues.len()];
            for leg in &plan.legs {
                alloc[leg.venue] = leg.amount;
            }
            for step in [1u64, 10, 1_000, 10_000, 100_000] {
                for from in 0..venues.len() {
                    for to in 0..venues.len() {
                        if from == to || alloc[from] < step {
                            continue;
                        }
                        let mut moved = alloc.clone();
                        moved[from] -= step;
                        moved[to] += step;
                        let other = build_plan(&venues, amount, &moved, None);
                        assert!(
                            other.total_out <= plan.total_out,
                            "amount {amount}: moving {step} from {from} to {to} gains {}",
                            other.total_out - plan.total_out
                        );
                    }
                }
            }
        }
    }

    #[test]
    fn two_identical_pools_split_near_evenly_and_optimally() {
        let pool = Venue::Cpmm { reserve_in: 1_000_000, reserve_out: 1_000_000, fee_bps: 30 };
        let venues = [pool.clone(), pool];
        let total = 200_000;
        let plan = optimize(&venues, total);
        assert_eq!(plan.legs.len(), 2);

        // Near the even split the total is flat to within floor rounding, so
        // "exactly half" is not the property. Against every split within 2%
        // of even, exhaustively: each leg's output is floored, so the total is
        // a staircase, and a power-of-two search can settle one step below the
        // top. At most a unit per leg -- this case lands exactly one short.
        let best = (98_000..=102_000)
            .map(|x| venues[0].quote(x).0 + venues[1].quote(total - x).0)
            .max()
            .unwrap();
        assert!(plan.total_out <= best);
        assert!(best - plan.total_out <= plan.legs.len() as u64, "{} vs {best}: {:?}", plan.total_out, plan.legs);
        let diff = plan.legs[0].amount.abs_diff(plan.legs[1].amount);
        assert!(diff < total / 500, "{:?}", plan.legs);
    }

    #[test]
    fn mid_size_orders_match_an_exhaustive_search_over_stable_and_the_book() {
        // The two best venues here, searched exhaustively over every whole
        // number of lots the book could take. The plan may use the other two
        // venues as well, so it must do at least this well, less rounding.
        let venues = world();
        for amount in [120_000u64, 300_000, 828_352, 830_110, 2_000_000, 5_000_000] {
            let plan = optimize(&venues, amount);
            let mut best = 0;
            for lots in 0..=amount / 10_000 {
                let (book_out, book_spent) = venues[3].quote(lots * 10_011);
                if book_spent > amount {
                    break;
                }
                best = best.max(book_out + venues[1].quote(amount - book_spent).0);
            }
            assert!(
                plan.total_out + plan.legs.len() as u64 >= best,
                "{amount}: plan {} < exhaustive {best}",
                plan.total_out
            );
        }
    }

    #[test]
    fn the_book_is_used_despite_whole_lots() {
        // By gain per chunk offered the book loses to the stable pool on every
        // chunk, because it hands back what does not make a whole lot. By
        // rate per unit consumed it is the best venue here, and the plan must
        // take its full depth.
        let venues = world();
        let plan = optimize(&venues, 8_000_000);
        let clob = plan.legs.iter().find(|l| venues[l.venue].kind() == "clob").expect("book unused");
        assert_eq!((clob.spent, clob.out), (6_003_200, 5_994_000));
    }

    #[test]
    fn a_trade_too_small_for_the_book_goes_elsewhere_and_dust_is_not_emitted() {
        let venues = world();
        let plan = optimize(&venues, 5_000);
        // 5,000 buys no whole 10,000-unit lot, so the book must get nothing.
        assert!(plan.legs.iter().all(|l| venues[l.venue].kind() != "clob"));
        assert!(plan.legs.iter().all(|l| l.out > 0));
    }

    #[test]
    fn min_out_floors() {
        assert_eq!(min_out(1_000_000, 50), 995_000);
        assert_eq!(min_out(999, 1), 998);
        assert_eq!(min_out(5, 20_000), 0);
    }
}
