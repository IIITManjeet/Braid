'use client';

import type { Venue } from '@/lib/api';
import { fmt } from '@/lib/format';
import { venueColor, venueLabel } from '@/lib/venues';
import { useWorld } from '@/components/WorldProvider';
import { Card, Empty, ExternalLink, KV, Loading, Pill, Swatch, Table } from '@/components/ui';
import BarsH from '@/components/charts/BarsH';
import { shortAddr } from '@/lib/format';

export default function VenuesPage() {
  const { world, loading } = useWorld();
  if (loading || !world) return <Loading>Loading venue state</Loading>;

  return (
    <>
      <Card
        title="Four venues, in increasing order of difficulty"
        sub="The router splits one order across all of them. They share no state, which is exactly why a route’s total is the sum of its legs."
      >
        <div className="grid four">
          {world.venues.map((v) => (
            <div className="stat" key={v.kind}>
              <div className="label">
                <Swatch color={venueColor(v.kind)} />
                {venueLabel(v.kind)}
              </div>
              <div className="value sm">{v.label}</div>
              <div className="note">{v.blurb}</div>
            </div>
          ))}
        </div>
      </Card>

      {world.venues.map((v) => (
        <Detail key={v.kind} venue={v} />
      ))}
    </>
  );
}

function Detail({ venue }: { venue: Venue }) {
  return (
    <section className="card">
      <div className="row between" style={{ marginBottom: 12 }}>
        <h2 style={{ margin: 0, fontSize: 15 }}>
          <Swatch color={venueColor(venue.kind)} />
          {venue.label} — {venueLabel(venue.kind)}
        </h2>
        {venue.object ? (
          <ExternalLink href={`https://suiscan.xyz/testnet/object/${venue.object}`}>
            {shortAddr(venue.object, 8)}
          </ExternalLink>
        ) : (
          <Pill>fixture</Pill>
        )}
      </div>
      <p className="sub">{venue.blurb}</p>
      <Body venue={venue} />
    </section>
  );
}

function Body({ venue }: { venue: Venue }) {
  switch (venue.kind) {
    case 'cpmm':
      return (
        <>
          <KV
            pairs={[
              ['Reserve in', fmt(venue.reserveIn)],
              ['Reserve out', fmt(venue.reserveOut)],
              ['Fee', `${venue.feeBps} bps`],
              ['k', fmt(venue.invariant)],
            ]}
          />
          <p className="hint">
            The fee is charged on the input and rounding goes to the pool, so k never decreases.
          </p>
        </>
      );

    case 'stable':
      return (
        <>
          <KV
            pairs={[
              ['Reserve in', fmt(venue.reserveIn)],
              ['Reserve out', fmt(venue.reserveOut)],
              ['Amplification A', fmt(venue.amp)],
              ['Fee', `${venue.feeBps} bps`],
            ]}
          />
          <p className="hint">
            The Curve invariant. D and y are both solved by Newton–Raphson; there are states where
            the iteration orbits instead of converging, which braid_stable resolves rather than
            reverting on.
          </p>
        </>
      );

    case 'clmm': {
      const ticks = venue.ticks ?? [];
      return (
        <>
          <KV
            pairs={[
              ['Current tick', fmt(venue.tick)],
              ['sqrt price (Q64.64)', venue.sqrtPrice],
              ['Active liquidity', fmt(Number(venue.liquidity))],
              ['Fee', `${venue.feeBps} bps`],
              ['Tick spacing', venue.tickSpacing],
              ['Direction', venue.zeroForOne ? 'A → B (zero for one)' : 'B → A'],
            ]}
          />
          <h3 style={{ fontSize: 13, margin: '16px 0 8px' }}>
            Initialized ticks ({ticks.length})
          </h3>
          {ticks.length ? (
            <Table
              rowKey={(t) => String(t.tick)}
              columns={[
                { head: 'Tick', num: true, render: (t) => fmt(t.tick) },
                { head: 'Liquidity gross', num: true, render: (t) => fmt(Number(t.liquidityGross)) },
                { head: 'Liquidity net', num: true, render: (t) => fmt(Number(t.liquidityNet)) },
                {
                  head: '',
                  render: (t) => (t.tick === venue.tick ? <Pill kind="good">current</Pill> : null),
                },
              ]}
              rows={ticks}
            />
          ) : (
            <Empty>No initialized ticks.</Empty>
          )}
          <p className="hint">
            A swap steps from one initialized tick to the next, and the bitmap is what makes finding
            it cheap — including skipping whole empty words, which a naive sorted-list
            implementation gets wrong.
          </p>
        </>
      );
    }

    case 'clob': {
      const asks = venue.asks ?? [];
      const bids = venue.bids ?? [];
      // Prices are scaled integers on chain; the decimal is shown beside the
      // raw value rather than instead of it.
      const price = (p: number) => (p / 1e9).toFixed(6);
      const rows = [
        ...[...asks].reverse().map(([p, q]) => ({ side: 'ask' as const, price: p, qty: q })),
        ...bids.map(([p, q]) => ({ side: 'bid' as const, price: p, qty: q })),
      ];

      return (
        <>
          <KV
            pairs={[
              ['Tick size', fmt(venue.tickSize)],
              ['Lot size', fmt(venue.lotSize)],
              ['Taker fee', `${venue.takerFeeBps} bps`],
              ['Direction', venue.buyBase ? 'quote → base (buying base)' : 'base → quote (selling base)'],
            ]}
          />
          <h3 style={{ fontSize: 13, margin: '16px 0 8px' }}>Resting depth</h3>
          {rows.length ? (
            <>
              <BarsH
                rows={rows.map((r) => ({
                  label: `${r.side} ${price(r.price)}`,
                  value: r.qty,
                  color: r.side === 'ask' ? 'var(--critical)' : 'var(--good)',
                  note: `${fmt(r.qty)} base units resting`,
                }))}
                unit="resting quantity"
              />
              <Table
                rowKey={(r, i) => `${r.side}-${r.price}-${i}`}
                columns={[
                  {
                    head: 'Side',
                    render: (r) => <Pill kind={r.side === 'ask' ? 'bad' : 'good'}>{r.side}</Pill>,
                  },
                  { head: 'Price', num: true, render: (r) => price(r.price) },
                  { head: 'Raw price', num: true, render: (r) => fmt(r.price) },
                  { head: 'Resting', num: true, render: (r) => fmt(r.qty) },
                ]}
                rows={rows}
              />
            </>
          ) : (
            <Empty>The book is empty on this side.</Empty>
          )}
          <p className="hint">
            The book trades whole lots, so it hands back anything that does not make one. Pricing
            that remainder as worthless is the mistake the optimizer avoids by ranking venues on
            output per unit consumed rather than per unit offered.
          </p>
        </>
      );
    }

    default:
      return null;
  }
}
