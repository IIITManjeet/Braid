//! Rust mirror of the read-only half of `braid_clob::market`: what a swap
//! against the book would fill, and for how much.
//!
//! The book is represented by what matching actually reads -- the total
//! resting at each price level. Individual orders and their queue positions
//! decide *who* is filled, never how much the taker gets, so a snapshot of
//! level totals is enough to price a swap exactly.

pub const PRICE_SCALE: u64 = 1_000_000_000;
pub const BPS_DENOM: u64 = 10_000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Book {
    pub tick_size: u64,
    pub lot_size: u64,
    pub taker_fee_bps: u64,
    /// `(price, total)`, best first: ascending.
    pub asks: Vec<(u64, u64)>,
    /// `(price, total)`, best first: descending.
    pub bids: Vec<(u64, u64)>,
}

fn quote_value(price: u64, quantity: u64) -> u64 {
    ((price as u128) * (quantity as u128) / PRICE_SCALE as u128) as u64
}

/// `ceil(amount * fee_bps / 10000)`, as `full_math::mul_div_ceil_u64`.
fn fee_on(amount: u64, fee_bps: u64) -> u64 {
    let n = amount as u128 * fee_bps as u128;
    let d = BPS_DENOM as u128;
    (n / d + u128::from(n % d != 0)) as u64
}

impl Book {
    pub fn new(tick_size: u64, lot_size: u64, taker_fee_bps: u64) -> Book {
        Book { tick_size, lot_size, taker_fee_bps, asks: Vec::new(), bids: Vec::new() }
    }

    /// Add resting quantity at a level, keeping both sides sorted best-first.
    pub fn rest(&mut self, price: u64, quantity: u64, is_bid: bool) {
        let side = if is_bid { &mut self.bids } else { &mut self.asks };
        match side.iter().position(|&(p, _)| p == price) {
            Some(i) => side[i].1 += quantity,
            None => {
                side.push((price, quantity));
                if is_bid {
                    side.sort_by(|a, b| b.0.cmp(&a.0));
                } else {
                    side.sort_by(|a, b| a.0.cmp(&b.0));
                }
            }
        }
    }

    /// `market::base_for_budget`: `(base, quote_spent, worst_price)`.
    fn base_for_budget(&self, budget: u64) -> (u64, u64, u64) {
        let mut left = budget;
        let mut base = 0;
        let mut worst = 0;
        for &(price, available) in &self.asks {
            let affordable = (left as u128 * PRICE_SCALE as u128 / price as u128).min(u64::MAX as u128) as u64;
            let affordable = affordable - affordable % self.lot_size;
            let take = available.min(affordable);
            if take == 0 {
                break;
            }
            base += take;
            left -= quote_value(price, take);
            worst = price;
            if take < available {
                break;
            }
        }
        (base, budget - left, worst)
    }

    /// `market::quote_quote_for_base`: `(base_out_after_fee, quote_used)`.
    pub fn quote_quote_for_base(&self, amount_in: u64) -> (u64, u64) {
        let (base, spent, _) = self.base_for_budget(amount_in);
        (base - fee_on(base, self.taker_fee_bps), spent)
    }

    /// `market::quote_base_for_quote`: `(quote_out_after_fee, base_used)`.
    pub fn quote_base_for_quote(&self, amount_in: u64) -> (u64, u64) {
        let quantity = amount_in - amount_in % self.lot_size;
        if quantity == 0 {
            return (0, 0);
        }
        let mut filled = 0u64;
        let mut notional = 0u128;
        for &(price, available) in &self.bids {
            if filled == quantity || price < self.tick_size {
                break;
            }
            let take = available.min(quantity - filled);
            filled += take;
            notional += price as u128 * take as u128;
        }
        let proceeds = (notional / PRICE_SCALE as u128) as u64;
        (proceeds - fee_on(proceeds, self.taker_fee_bps), filled)
    }

    /// Execute a quote-for-base swap against the snapshot, consuming depth, so
    /// several quotes can be chained. Returns what `quote_quote_for_base` did.
    pub fn take_quote_for_base(&mut self, amount_in: u64) -> (u64, u64) {
        let result = self.quote_quote_for_base(amount_in);
        let (mut base, _, _) = self.base_for_budget(amount_in);
        while base > 0 {
            let level = &mut self.asks[0];
            let take = level.1.min(base);
            level.1 -= take;
            base -= take;
            if level.1 == 0 {
                self.asks.remove(0);
            }
        }
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The book seeded on testnet, before the first swaps.
    fn live() -> Book {
        let mut b = Book::new(100_000, 10_000, 10);
        b.rest(1_000_100_000, 2_000_000, false);
        b.rest(1_000_500_000, 2_000_000, false);
        b.rest(1_001_000_000, 2_000_000, false);
        b.rest(999_900_000, 2_000_000, true);
        b.rest(999_500_000, 2_000_000, true);
        b
    }

    #[test]
    fn reproduces_the_live_testnet_swaps() {
        let b = live();
        // 3,000,000 TUSD in: 2,987,010 TETH out, 2,990,695 spent.
        assert_eq!(b.quote_quote_for_base(3_000_000), (2_987_010, 2_990_695));
        // 1,505,000 TETH in: 1,498,350 TUSD out, 1,500,000 used.
        assert_eq!(b.quote_base_for_quote(1_505_000), (1_498_350, 1_500_000));
    }

    #[test]
    fn matches_the_move_market_tests() {
        // market_tests::a_book: tick 1e7, lot 100, fee 10.
        let mut b = Book::new(10_000_000, 100, 10);
        b.rest(1_000_000_000, 500, false);
        b.rest(1_010_000_000, 500, false);
        b.rest(1_020_000_000, 500, false);
        b.rest(990_000_000, 500, true);
        b.rest(980_000_000, 500, true);
        assert_eq!(b.quote_quote_for_base(1200), (1098, 1107));
        assert_eq!(b.quote_base_for_quote(750), (690, 700));
    }

    #[test]
    fn taking_consumes_depth() {
        let mut b = live();
        b.take_quote_for_base(3_000_000);
        assert_eq!(b.asks, vec![(1_000_500_000, 1_010_000), (1_001_000_000, 2_000_000)]);
    }
}
